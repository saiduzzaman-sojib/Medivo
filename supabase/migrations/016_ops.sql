-- MEDIVO Step 9 / 016: operations.
-- 1. A restore must be able to load old rows (a batch that has expired since the
--    backup, a transfer from a batch that has expired). Normal users can never
--    switch this on: only a database connection that sets medivo.restore can.
-- 2. Integrity reports that run from the SQL editor (owner only), not from the app.

create or replace function public.batches_check_insert() returns trigger
language plpgsql as $$
begin
  if coalesce(current_setting('medivo.restore', true), '') = 'on' then
    return new;
  end if;
  if new.expires_on <= current_date then
    raise exception 'MEDIVO_422: expired stock cannot be added' using errcode = 'PT422';
  end if;
  return new;
end $$;

create or replace function public.transfers_check() returns trigger
language plpgsql as $$
declare
  v_pack integer;
  v_exp date;
  v_rec boolean;
begin
  if coalesce(current_setting('medivo.restore', true), '') = 'on' then
    return new;
  end if;
  select pack_size into v_pack from public.medicines
   where id = new.medicine_id and tenant_id = new.tenant_id;
  if v_pack is null or new.quantity % v_pack <> 0 then
    raise exception 'MEDIVO_422: transfer quantity must be whole packs' using errcode = 'PT422';
  end if;
  if tg_op = 'INSERT' then
    select expires_on, recalled into v_exp, v_rec from public.batches
     where id = new.batch_id and tenant_id = new.tenant_id;
    if v_exp is null or v_exp <= current_date or v_rec then
      raise exception 'MEDIVO_422: expired or recalled batches cannot be transferred' using errcode = 'PT422';
    end if;
  end if;
  return new;
end $$;

create or replace function public.admin_verify_audit_chain(p_tenant uuid)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  r public.audit_log%rowtype;
  v_prev text := repeat('0', 64);
  v_n integer := 0;
begin
  for r in select * from public.audit_log where tenant_id = p_tenant order by id loop
    if r.prev_hash <> v_prev
       or r.row_hash <> public.audit_hash(r.prev_hash, r.tenant_id, r.actor_id, r.action, r.ok, r.detail, r.created_at) then
      return jsonb_build_object('ok', false, 'checked', v_n, 'first_bad_id', r.id);
    end if;
    v_prev := r.row_hash;
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'checked', v_n);
end $$;

-- Run this before and after a restore and compare the two answers.
create or replace function public.admin_restore_report() returns jsonb
language sql security definer set search_path = public, extensions as $$
  select jsonb_build_object(
    'rows', jsonb_build_object(
      'tenants', (select count(*) from public.tenants),
      'profiles', (select count(*) from public.profiles),
      'branches', (select count(*) from public.branches),
      'medicines', (select count(*) from public.medicines),
      'batches', (select count(*) from public.batches),
      'medicine_sales', (select count(*) from public.medicine_sales),
      'sales_imports', (select count(*) from public.sales_imports),
      'forecast_runs', (select count(*) from public.forecast_runs),
      'stock_plans', (select count(*) from public.stock_plans),
      'transfers', (select count(*) from public.transfers),
      'outcomes', (select count(*) from public.outcomes),
      'audit_log', (select count(*) from public.audit_log)),
    'approved_plans', (select count(*) from public.stock_plans where state = 'approved'),
    'approved_without_hash', (select count(*) from public.stock_plans
                               where state = 'approved' and content_hash is null),
    'profiles_without_user', (select count(*) from public.profiles p
                               left join auth.users u on u.id = p.id where u.id is null),
    'audit', coalesce((select jsonb_agg(jsonb_build_object(
                         'tenant_id', t.id, 'chain', public.admin_verify_audit_chain(t.id)) order by t.id)
                         from public.tenants t), '[]'::jsonb)
  )
$$;

revoke execute on function public.admin_verify_audit_chain(uuid), public.admin_restore_report()
  from public, anon, authenticated;