-- MEDIVO Step 2 / 003: the only way the app changes data.
-- Every function: checks the role, scopes to the caller's tenant, checks the
-- version where relevant, and writes a hash-chained audit entry.
-- Domain failures return {"ok": false, "status": 403|409|422, "message": ...}
-- AND are audited (an exception would roll the audit entry back).

create or replace function public._deny(p_status integer, p_msg text, p_action text, p_detail jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.write_audit(p_action || ' denied', false,
    p_detail || jsonb_build_object('status', p_status, 'message', p_msg));
  return jsonb_build_object('ok', false, 'status', p_status, 'message', p_msg);
end $$;

-- What the app needs after sign-in: tenant, role and permissions.
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
   where pr.id = auth.uid() and pr.active
$$;

create or replace function public.add_batch(
  p_medicine uuid, p_branch uuid, p_code text, p_quantity integer, p_expires date
) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_tenant uuid := public.auth_tenant();
  v_id uuid;
  v_detail jsonb := jsonb_build_object('code', p_code);
begin
  if not public.has_permission('add_batch') then
    return public._deny(403, 'Your role cannot add batches.', 'add_batch', v_detail);
  end if;
  if p_code is null or btrim(p_code) = '' or p_quantity is null or p_quantity <= 0 or p_expires is null then
    return public._deny(422, 'Enter a batch code, a quantity above zero and an expiry date.', 'add_batch', v_detail);
  end if;
  if p_expires <= current_date then
    return public._deny(422, 'Expired stock cannot be added.', 'add_batch', v_detail);
  end if;
  begin
    insert into public.batches (tenant_id, medicine_id, branch_id, batch_code, quantity, expires_on, created_by)
    values (v_tenant, p_medicine, p_branch, btrim(p_code), p_quantity, p_expires, auth.uid())
    returning id into v_id;
  exception
    when unique_violation then
      return public._deny(409, 'This batch code already exists.', 'add_batch', v_detail);
    when foreign_key_violation then
      return public._deny(422, 'Unknown medicine or branch.', 'add_batch', v_detail);
  end;
  perform public.write_audit('batch added', true, v_detail || jsonb_build_object('batch_id', v_id));
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

create or replace function public.validate_batch(p_batch uuid)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_tenant uuid := public.auth_tenant();
  v_n integer;
  v_detail jsonb := jsonb_build_object('batch_id', p_batch);
begin
  if not public.has_permission('validate_stock') then
    return public._deny(403, 'Your role cannot validate stock.', 'validate_batch', v_detail);
  end if;
  update public.batches
     set validated = true, validated_by = auth.uid(), version = version + 1
   where id = p_batch and tenant_id = v_tenant and not recalled and expires_on > current_date;
  get diagnostics v_n = row_count;
  if v_n = 0 then
    return public._deny(422, 'This batch cannot be validated (not found, expired or recalled).', 'validate_batch', v_detail);
  end if;
  perform public.write_audit('batch validated', true, v_detail);
  return jsonb_build_object('ok', true);
end $$;

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
  if coalesce(v_mfa, false) and coalesce(auth.jwt() ->> 'aal', '') <> 'aal2' then
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

create or replace function public.review_plan(p_plan uuid, p_expected_version integer)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_tenant uuid := public.auth_tenant();
  v_plan public.stock_plans%rowtype;
  v_detail jsonb := jsonb_build_object('plan_id', p_plan);
begin
  if not public.has_permission('review_plan') then
    return public._deny(403, 'Your role cannot review plans.', 'review_plan', v_detail);
  end if;
  select * into v_plan from public.stock_plans where id = p_plan and tenant_id = v_tenant for update;
  if not found then
    return public._deny(422, 'Plan not found.', 'review_plan', v_detail);
  end if;
  if v_plan.state not in ('draft', 'returned') then
    return public._deny(409, 'This plan is not open for review.', 'review_plan', v_detail);
  end if;
  if v_plan.version <> p_expected_version then
    return public._deny(409, 'The plan changed. Refresh and review again.', 'review_plan', v_detail);
  end if;
  update public.stock_plans
     set state = 'reviewed', reviewed_by = auth.uid(),
         reviewed_version = v_plan.version + 1, version = v_plan.version + 1
   where id = p_plan;
  perform public.write_audit('plan reviewed', true, v_detail || jsonb_build_object('version', v_plan.version + 1));
  return jsonb_build_object('ok', true, 'version', v_plan.version + 1);
end $$;

create or replace function public.approve_plan(p_plan uuid, p_expected_version integer, p_handling_confirmed boolean)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_tenant uuid := public.auth_tenant();
  v_plan public.stock_plans%rowtype;
  v_hash text;
  v_detail jsonb := jsonb_build_object('plan_id', p_plan);
begin
  if not public.has_permission('approve_plan') then
    return public._deny(403, 'Your role cannot approve plans.', 'approve_plan', v_detail);
  end if;
  select * into v_plan from public.stock_plans where id = p_plan and tenant_id = v_tenant for update;
  if not found then
    return public._deny(422, 'Plan not found.', 'approve_plan', v_detail);
  end if;
  if v_plan.state <> 'reviewed' then
    return public._deny(409, 'A purchaser review is required first.', 'approve_plan', v_detail);
  end if;
  if v_plan.version <> p_expected_version or v_plan.reviewed_version is distinct from v_plan.version then
    return public._deny(409, 'The plan changed after review. Review it again.', 'approve_plan', v_detail);
  end if;
  if p_handling_confirmed is not true then
    return public._deny(422, 'Confirm that handling rules were followed.', 'approve_plan', v_detail);
  end if;
  if exists (
    select 1 from public.transfers t
      join public.batches b on b.id = t.batch_id and b.tenant_id = t.tenant_id
     where t.plan_id = p_plan and t.tenant_id = v_tenant and t.state <> 'rejected' and not b.validated
  ) then
    return public._deny(422, 'Validate the moved batches first.', 'approve_plan', v_detail);
  end if;
  v_hash := encode(digest(
    v_plan.moves::text || '|' || v_plan.orders::text || '|' ||
    coalesce(v_plan.forecast_run_id::text, '') || '|' || (v_plan.revision + 1)::text, 'sha256'), 'hex');
  update public.stock_plans
     set state = 'approved', approved_by = auth.uid(), approved_at = now(),
         revision = revision + 1, content_hash = v_hash, version = version + 1
   where id = p_plan;
  perform public.write_audit('plan approved', true,
    v_detail || jsonb_build_object('revision', v_plan.revision + 1, 'hash', v_hash));
  return jsonb_build_object('ok', true, 'revision', v_plan.revision + 1, 'hash', v_hash);
end $$;

create or replace function public.return_plan(p_plan uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_tenant uuid := public.auth_tenant();
  v_plan public.stock_plans%rowtype;
  v_detail jsonb := jsonb_build_object('plan_id', p_plan);
begin
  if not (public.has_permission('review_plan') or public.has_permission('approve_plan')) then
    return public._deny(403, 'Your role cannot return plans.', 'return_plan', v_detail);
  end if;
  if p_reason is null or btrim(p_reason) = '' then
    return public._deny(422, 'A reason is required.', 'return_plan', v_detail);
  end if;
  select * into v_plan from public.stock_plans where id = p_plan and tenant_id = v_tenant for update;
  if not found then
    return public._deny(422, 'Plan not found.', 'return_plan', v_detail);
  end if;
  if v_plan.state not in ('draft', 'reviewed') then
    return public._deny(409, 'This plan can no longer be returned.', 'return_plan', v_detail);
  end if;
  update public.stock_plans
     set state = 'returned', reviewed_by = null, reviewed_version = null, version = version + 1
   where id = p_plan;
  perform public.write_audit('plan returned', true, v_detail || jsonb_build_object('reason', p_reason));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.decide_transfer(p_transfer uuid, p_approve boolean)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_tenant uuid := public.auth_tenant();
  v_t public.transfers%rowtype;
  v_exp date;
  v_rec boolean;
  v_detail jsonb := jsonb_build_object('transfer_id', p_transfer, 'approve', p_approve);
begin
  if not public.has_permission('approve_transfer') then
    return public._deny(403, 'Your role cannot approve transfers.', 'decide_transfer', v_detail);
  end if;
  select * into v_t from public.transfers where id = p_transfer and tenant_id = v_tenant for update;
  if not found then
    return public._deny(422, 'Transfer not found.', 'decide_transfer', v_detail);
  end if;
  if v_t.state <> 'pending' then
    return public._deny(409, 'This transfer was already decided.', 'decide_transfer', v_detail);
  end if;
  if p_approve then
    select expires_on, recalled into v_exp, v_rec from public.batches
     where id = v_t.batch_id and tenant_id = v_tenant;
    if v_exp is null or v_exp <= current_date or v_rec then
      return public._deny(422, 'The batch is expired or recalled.', 'decide_transfer', v_detail);
    end if;
  end if;
  update public.transfers
     set state = case when p_approve then 'approved'::public.transfer_state else 'rejected'::public.transfer_state end,
         decided_by = auth.uid(), decided_at = now()
   where id = p_transfer;
  perform public.write_audit(case when p_approve then 'transfer approved' else 'transfer rejected' end, true, v_detail);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.record_outcome(p_plan uuid, p_label text, p_baseline numeric, p_plan_cost numeric)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_tenant uuid := public.auth_tenant();
  v_state public.plan_state;
  v_detail jsonb := jsonb_build_object('plan_id', p_plan);
begin
  if not public.has_permission('record_outcome') then
    return public._deny(403, 'Your role cannot record outcomes.', 'record_outcome', v_detail);
  end if;
  select state into v_state from public.stock_plans where id = p_plan and tenant_id = v_tenant;
  if v_state is distinct from 'approved' then
    return public._deny(422, 'Only an approved plan can have an outcome.', 'record_outcome', v_detail);
  end if;
  if p_label is null or btrim(p_label) = '' or p_baseline is null or p_baseline < 0 or p_plan_cost is null or p_plan_cost < 0 then
    return public._deny(422, 'Enter a label and costs of zero or more.', 'record_outcome', v_detail);
  end if;
  begin
    insert into public.outcomes (tenant_id, plan_id, cycle_label, baseline_cost, plan_cost, recorded_by)
    values (v_tenant, p_plan, btrim(p_label), p_baseline, p_plan_cost, auth.uid());
  exception when unique_violation then
    return public._deny(409, 'An outcome is already recorded for this plan.', 'record_outcome', v_detail);
  end;
  perform public.write_audit('outcome recorded', true, v_detail);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.verify_audit_chain()
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_tenant uuid := public.auth_tenant();
  r public.audit_log%rowtype;
  v_prev text := repeat('0', 64);
  v_n integer := 0;
begin
  if not public.has_permission('view_audit') then
    return public._deny(403, 'Your role cannot view the audit log.', 'verify_audit_chain');
  end if;
  for r in select * from public.audit_log where tenant_id = v_tenant order by id loop
    if r.prev_hash <> v_prev
       or r.row_hash <> public.audit_hash(r.prev_hash, r.tenant_id, r.actor_id, r.action, r.ok, r.detail, r.created_at) then
      return jsonb_build_object('ok', false, 'checked', v_n, 'first_bad_id', r.id);
    end if;
    v_prev := r.row_hash;
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'checked', v_n);
end $$;

-- Function privileges: internal helpers are NOT callable by the app. -------------
revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on function
  public.auth_tenant(), public.auth_role(), public.has_permission(text),
  public.my_access(),
  public.add_batch(uuid, uuid, text, integer, date),
  public.validate_batch(uuid),
  public.recall_batch(uuid, text),
  public.review_plan(uuid, integer),
  public.approve_plan(uuid, integer, boolean),
  public.return_plan(uuid, text),
  public.decide_transfer(uuid, boolean),
  public.record_outcome(uuid, text, numeric, numeric),
  public.verify_audit_chain()
to authenticated;