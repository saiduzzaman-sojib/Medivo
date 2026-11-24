-- MEDIVO Step 2 / 002: permissions, row level security, immutability, audit chain
--
-- Layers:
--  1. Row level security: a user only ever SEES rows of their own tenant,
--     and only if their role may view that data.
--  2. No direct writes: the app role has SELECT only. All changes go through
--     the functions in 003, which re-check role, tenant and version.
--  3. Triggers: approved plans are immutable, the audit log is append-only.

-- Role -> permission matrix. Same names as the Flutter Permission enum (snake_case).
create table public.role_permissions (
  role public.user_role not null,
  permission text not null,
  primary key (role, permission)
);

insert into public.role_permissions (role, permission) values
  ('pharmacist', 'view_overview'), ('pharmacist', 'view_audit'),
  ('pharmacist', 'import_data'), ('pharmacist', 'add_batch'),
  ('pharmacist', 'validate_stock'), ('pharmacist', 'run_forecast'),
  ('pharmacist', 'manual_forecast'), ('pharmacist', 'approve_plan'),
  ('pharmacist', 'record_outcome'),
  ('purchaser', 'view_overview'), ('purchaser', 'view_audit'),
  ('purchaser', 'import_data'), ('purchaser', 'run_forecast'),
  ('purchaser', 'manual_forecast'), ('purchaser', 'review_plan'),
  ('branch_manager', 'view_overview'), ('branch_manager', 'view_audit'),
  ('branch_manager', 'approve_transfer'), ('branch_manager', 'approve_recall');

-- Helpers. SECURITY DEFINER so they can read profiles without recursing into RLS.
create or replace function public.auth_tenant() returns uuid
language sql stable security definer set search_path = public as $$
  select tenant_id from public.profiles where id = auth.uid() and active
$$;

create or replace function public.auth_role() returns public.user_role
language sql stable security definer set search_path = public as $$
  select role from public.profiles where id = auth.uid() and active
$$;

create or replace function public.has_permission(p text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1
      from public.profiles pr
      join public.role_permissions rp on rp.role = pr.role
     where pr.id = auth.uid() and pr.active and rp.permission = p
  )
$$;

-- Row level security ------------------------------------------------------
alter table public.tenants enable row level security;
alter table public.profiles enable row level security;
alter table public.role_permissions enable row level security;
alter table public.audit_log enable row level security;

create policy tenants_select on public.tenants for select to authenticated
  using (id = public.auth_tenant());
create policy profiles_select on public.profiles for select to authenticated
  using (tenant_id = public.auth_tenant());
create policy role_permissions_select on public.role_permissions for select to authenticated
  using (true);
create policy audit_select on public.audit_log for select to authenticated
  using (tenant_id = public.auth_tenant() and public.has_permission('view_audit'));

do $$
declare t text;
begin
  foreach t in array array[
    'branches', 'medicines', 'batches', 'sales_imports', 'medicine_sales',
    'forecast_runs', 'stock_plans', 'transfers', 'outcomes'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format(
      'create policy %I on public.%I for select to authenticated using (tenant_id = public.auth_tenant() and public.has_permission(%L))',
      t || '_select', t, 'view_overview');
  end loop;
end $$;

-- Table privileges: the app can only READ. Nothing else is granted.
revoke all on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
grant usage on schema public to authenticated;
grant select on
  public.tenants, public.profiles, public.role_permissions, public.branches,
  public.medicines, public.batches, public.sales_imports, public.medicine_sales,
  public.forecast_runs, public.stock_plans, public.transfers, public.outcomes,
  public.audit_log
to authenticated;

-- Approved plan revisions are immutable --------------------------------------
create or replace function public.plan_guard() returns trigger
language plpgsql as $$
begin
  if old.state = 'approved' then
    raise exception 'MEDIVO_409: approved revisions are immutable' using errcode = 'PT409';
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  if new.moves is distinct from old.moves or new.orders is distinct from old.orders then
    -- Content changed: any earlier review is stale and approvals must be redone.
    new.version := greatest(new.version, old.version + 1);
    if old.state = 'reviewed' then
      new.state := 'draft';
      new.reviewed_by := null;
      new.reviewed_version := null;
    end if;
  end if;
  new.updated_at := now();
  return new;
end $$;
create trigger plan_guard_trg before update or delete on public.stock_plans
  for each row execute function public.plan_guard();

-- Audit log: append-only, hash-chained ---------------------------------------
create or replace function public.audit_block_changes() returns trigger
language plpgsql as $$
begin
  raise exception 'MEDIVO_409: the audit log is append-only' using errcode = 'PT409';
end $$;
create trigger audit_no_change_trg before update or delete on public.audit_log
  for each row execute function public.audit_block_changes();
create trigger audit_no_truncate_trg before truncate on public.audit_log
  for each statement execute function public.audit_block_changes();

create or replace function public.audit_hash(
  p_prev text, p_tenant uuid, p_actor uuid, p_action text,
  p_ok boolean, p_detail jsonb, p_ts timestamptz
) returns text
language sql stable set search_path = public, extensions as $$
  select encode(
    digest(
      p_prev || '|' || p_tenant::text || '|' || coalesce(p_actor::text, '') || '|' ||
      p_action || '|' || p_ok::text || '|' || p_detail::text || '|' ||
      extract(epoch from p_ts)::text,
      'sha256'),
    'hex')
$$;

create or replace function public.write_audit(
  p_action text, p_ok boolean default true, p_detail jsonb default '{}'::jsonb
) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_tenant uuid := public.auth_tenant();
  v_role public.user_role := public.auth_role();
  v_prev text;
  v_ts timestamptz := clock_timestamp();
begin
  if v_tenant is null then
    raise exception 'MEDIVO_403: no active profile' using errcode = 'PT403';
  end if;
  perform pg_advisory_xact_lock(hashtext(v_tenant::text));
  select row_hash into v_prev from public.audit_log
   where tenant_id = v_tenant order by id desc limit 1;
  v_prev := coalesce(v_prev, repeat('0', 64));
  insert into public.audit_log (tenant_id, actor_id, actor_role, action, ok, detail, prev_hash, row_hash, created_at)
  values (
    v_tenant, auth.uid(), v_role, p_action, p_ok, p_detail, v_prev,
    public.audit_hash(v_prev, v_tenant, auth.uid(), p_action, p_ok, p_detail, v_ts),
    v_ts);
end $$;