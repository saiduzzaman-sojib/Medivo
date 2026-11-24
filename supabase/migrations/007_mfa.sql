-- MEDIVO Step 3B / 007: the database itself requires the second step.
-- With require_mfa = true, a session that only passed the password (aal1)
-- sees nothing and can do nothing. Recalls also need a code typed in the
-- last 5 minutes (a "fresh" check).

alter table public.tenants
  add column if not exists require_mfa boolean not null default false;

create or replace function public.mfa_ok() returns boolean
language sql stable as $$
  select coalesce(auth.jwt() ->> 'aal', '') = 'aal2'
$$;

create or replace function public.mfa_fresh(p_seconds integer default 300) returns boolean
language sql stable as $$
  select coalesce((
    select max((e ->> 'timestamp')::bigint)
      from jsonb_array_elements(coalesce(auth.jwt() -> 'amr', '[]'::jsonb)) e
     where e ->> 'method' = 'totp'
  ), 0) >= extract(epoch from now())::bigint - p_seconds
$$;

create or replace function public.auth_tenant() returns uuid
language sql stable security definer set search_path = public as $$
  select pr.tenant_id
    from public.profiles pr
    join public.tenants t on t.id = pr.tenant_id
   where pr.id = auth.uid() and pr.active and (not t.require_mfa or public.mfa_ok())
$$;

create or replace function public.auth_role() returns public.user_role
language sql stable security definer set search_path = public as $$
  select pr.role
    from public.profiles pr
    join public.tenants t on t.id = pr.tenant_id
   where pr.id = auth.uid() and pr.active and (not t.require_mfa or public.mfa_ok())
$$;

create or replace function public.has_permission(p text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1
      from public.profiles pr
      join public.tenants t on t.id = pr.tenant_id
      join public.role_permissions rp on rp.role = pr.role
     where pr.id = auth.uid() and pr.active and rp.permission = p
       and (not t.require_mfa or public.mfa_ok())
  )
$$;

create or replace function public.my_access() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'user_id', pr.id,
    'full_name', pr.full_name,
    'tenant_id', pr.tenant_id,
    'tenant_name', t.name,
    'role', pr.role,
    'permissions', coalesce((select jsonb_agg(rp.permission order by rp.permission)
                               from public.role_permissions rp where rp.role = pr.role), '[]'::jsonb))
    from public.profiles pr join public.tenants t on t.id = pr.tenant_id
   where pr.id = auth.uid() and pr.active and (not t.require_mfa or public.mfa_ok())
$$;

-- Recall now needs a code typed in the last 5 minutes.
create or replace function public.recall_batch(p_batch uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_tenant uuid := public.auth_tenant();
  v_mfa boolean;
  v_n integer;
  v_detail jsonb := jsonb_build_object('batch_id', p_batch);
begin
  if not public.has_permission('approve_recall') then
    return public._deny(403, 'Your role cannot approve recalls.', 'recall_batch', v_detail);
  end if;
  select require_mfa_for_recall into v_mfa from public.tenants where id = v_tenant;
  if coalesce(v_mfa, false) and not public.mfa_fresh() then
    return public._deny(403, 'A fresh verification code is required to approve a recall.', 'recall_batch', v_detail);
  end if;
  if p_reason is null or btrim(p_reason) = '' then
    return public._deny(422, 'A reason is required.', 'recall_batch', v_detail);
  end if;
  update public.batches
     set recalled = true, recalled_by = auth.uid(), version = version + 1
   where id = p_batch and tenant_id = v_tenant and not recalled;
  get diagnostics v_n = row_count;
  if v_n = 0 then
    return public._deny(409, 'Batch not found or already recalled.', 'recall_batch', v_detail);
  end if;
  update public.transfers
     set state = 'rejected', decided_by = auth.uid(), decided_at = now()
   where batch_id = p_batch and tenant_id = v_tenant and state = 'pending';
  perform public.write_audit('batch recalled', true, v_detail || jsonb_build_object('reason', p_reason));
  return jsonb_build_object('ok', true);
end $$;

revoke execute on function public.mfa_ok(), public.mfa_fresh(integer) from public, anon;
grant execute on function public.mfa_ok(), public.mfa_fresh(integer) to authenticated;

-- Switch it on for the demo tenant.
update public.tenants
   set require_mfa = true, require_mfa_for_recall = true
 where id = '11111111-1111-1111-1111-111111111111';