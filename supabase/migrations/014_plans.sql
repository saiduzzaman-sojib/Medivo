-- MEDIVO Step 8 / 014: saving a generated plan.
-- The plan and its transfers are written in one step. If any transfer breaks a
-- rule (whole packs, expired or recalled stock, quantity in the batch), nothing is saved.

alter table public.stock_plans
  add column if not exists horizon_days integer check (horizon_days in (7, 14, 21)),
  add column if not exists source text check (source in ('model', 'baseline')),
  add column if not exists input_hash text,
  add column if not exists risk_before numeric(14, 2),
  add column if not exists risk_after numeric(14, 2);

create unique index if not exists stock_plans_input_hash_uq
  on public.stock_plans (tenant_id, input_hash) where input_hash is not null;

create or replace function public.create_plan(
  p_horizon integer, p_source text, p_input_hash text,
  p_moves jsonb, p_orders jsonb, p_risk_before numeric, p_risk_after numeric,
  p_transfers jsonb
) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_tenant uuid := public.auth_tenant();
  v_existing public.stock_plans%rowtype;
  v_id uuid;
  e jsonb;
  v_b public.batches%rowtype;
  v_qty integer;
  v_msg text;
  v_detail jsonb := jsonb_build_object('horizon', p_horizon, 'source', p_source);
begin
  if not public.has_permission('run_forecast') then
    return public._deny(403, 'Your role cannot generate plans.', 'create_plan', v_detail);
  end if;
  if p_horizon is null or p_horizon not in (7, 14, 21) then
    return public._deny(422, 'The horizon must be 7, 14 or 21 days.', 'create_plan', v_detail);
  end if;
  if p_source is null or p_source not in ('model', 'baseline') then
    return public._deny(422, 'The forecast source must be model or baseline.', 'create_plan', v_detail);
  end if;
  if p_input_hash is null or btrim(p_input_hash) = '' then
    return public._deny(422, 'An input fingerprint is required.', 'create_plan', v_detail);
  end if;
  if p_moves is null or p_orders is null or p_transfers is null
     or jsonb_typeof(p_moves) <> 'array' or jsonb_typeof(p_orders) <> 'array'
     or jsonb_typeof(p_transfers) <> 'array' then
    return public._deny(422, 'Moves, orders and transfers must be lists.', 'create_plan', v_detail);
  end if;
  if jsonb_array_length(p_moves) > 200 or jsonb_array_length(p_orders) > 200
     or jsonb_array_length(p_transfers) > 200 then
    return public._deny(422, 'The plan is too large.', 'create_plan', v_detail);
  end if;
  if p_risk_before is null or p_risk_before < 0 or p_risk_after is null or p_risk_after < 0 then
    return public._deny(422, 'Risk values must be zero or more.', 'create_plan', v_detail);
  end if;

  select * into v_existing from public.stock_plans
   where tenant_id = v_tenant and input_hash = p_input_hash;
  if found then
    perform public.write_audit('plan generation reused', true,
      v_detail || jsonb_build_object('plan_id', v_existing.id));
    return jsonb_build_object('ok', true, 'plan_id', v_existing.id, 'reused', true,
                              'state', v_existing.state, 'version', v_existing.version);
  end if;

  begin
    insert into public.stock_plans (tenant_id, moves, orders, horizon_days, source, input_hash,
                                    risk_before, risk_after, created_by)
    values (v_tenant, p_moves, p_orders, p_horizon, p_source, p_input_hash,
            p_risk_before, p_risk_after, auth.uid())
    returning id into v_id;

    for e in select value from jsonb_array_elements(p_transfers) loop
      v_qty := (e ->> 'quantity')::integer;
      select * into v_b from public.batches
       where id = (e ->> 'batch_id')::uuid and tenant_id = v_tenant;
      if not found
         or v_b.branch_id <> (e ->> 'from_branch_id')::uuid
         or v_b.medicine_id <> (e ->> 'medicine_id')::uuid then
        raise exception 'MEDIVO_422: a transfer does not match its batch';
      end if;
      if v_qty is null or v_qty <= 0 or v_qty > v_b.quantity then
        raise exception 'MEDIVO_422: a transfer quantity is not available in its batch';
      end if;
      insert into public.transfers (tenant_id, plan_id, medicine_id, batch_id,
                                    from_branch_id, to_branch_id, quantity)
      values (v_tenant, v_id, v_b.medicine_id, v_b.id, v_b.branch_id,
              (e ->> 'to_branch_id')::uuid, v_qty);
    end loop;
  exception when others then
    v_msg := regexp_replace(sqlerrm, '^MEDIVO_[0-9]+: ', '');
    return public._deny(422, 'The plan was not saved: ' || left(v_msg, 140), 'create_plan', v_detail);
  end;

  perform public.write_audit('plan generated', true, v_detail || jsonb_build_object(
    'plan_id', v_id, 'transfers', jsonb_array_length(p_transfers), 'orders', jsonb_array_length(p_orders)));
  return jsonb_build_object('ok', true, 'plan_id', v_id, 'reused', false, 'state', 'draft', 'version', 1);
end $$;

revoke execute on function public.create_plan(integer, text, text, jsonb, jsonb, numeric, numeric, jsonb)
  from public, anon;
grant execute on function public.create_plan(integer, text, text, jsonb, jsonb, numeric, numeric, jsonb)
  to authenticated;