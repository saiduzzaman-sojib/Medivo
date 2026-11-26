-- MEDIVO Step 8 / 015: tests for saving plans. Rolled back at the end.
begin;

create or replace function public._p_act(p uuid) returns void
language plpgsql as $f$
begin
  execute 'reset role';
  perform set_config('request.jwt.claim.sub', p::text, true);
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', p::text, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  execute 'set local role authenticated';
end $f$;
grant execute on function public._p_act(uuid) to public;

do $$
declare
  v_t uuid := '11111111-1111-1111-1111-111111111111';
  v_pu uuid; v_mg uuid;
  v_napa uuid; v_uttara uuid; v_mirpur uuid; v_gulshan uuid;
  v_b_ok uuid; v_b_exp uuid; v_b_small uuid; v_azi uuid; v_dhaka uuid;
  v_plan uuid; v_ver int;
  r jsonb; n int;
  good jsonb; bad_pack jsonb; bad_expired jsonb; bad_qty jsonb;
begin
  select id into v_pu from auth.users where email = 'purchaser@medivo.test';
  select id into v_mg from auth.users where email = 'manager@medivo.test';
  if v_pu is null or v_mg is null then raise exception 'Create the demo users first.'; end if;

  select id into v_napa from public.medicines where tenant_id = v_t and product_code = 'NAPA500';
  select id into v_azi from public.medicines where tenant_id = v_t and product_code = 'AZI500';
  select id into v_uttara from public.branches where tenant_id = v_t and name = 'Uttara';
  select id into v_mirpur from public.branches where tenant_id = v_t and name = 'Mirpur';
  select id into v_gulshan from public.branches where tenant_id = v_t and name = 'Gulshan';
  select id into v_dhaka from public.branches where tenant_id = v_t and name = 'Dhanmondi';
  select id into v_b_ok from public.batches where tenant_id = v_t and batch_code = 'B-2291';
  select id into v_b_exp from public.batches where tenant_id = v_t and batch_code = 'B-2295';
  select id into v_b_small from public.batches where tenant_id = v_t and batch_code = 'B-6001';

  good := jsonb_build_array(jsonb_build_object(
    'medicine_id', v_napa, 'batch_id', v_b_ok, 'from_branch_id', v_uttara, 'to_branch_id', v_mirpur, 'quantity', 200));
  bad_pack := jsonb_build_array(jsonb_build_object(
    'medicine_id', v_napa, 'batch_id', v_b_ok, 'from_branch_id', v_uttara, 'to_branch_id', v_mirpur, 'quantity', 150));
  bad_expired := jsonb_build_array(jsonb_build_object(
    'medicine_id', v_napa, 'batch_id', v_b_exp, 'from_branch_id', v_gulshan, 'to_branch_id', v_mirpur, 'quantity', 100));
  bad_qty := jsonb_build_array(jsonb_build_object(
    'medicine_id', v_azi, 'batch_id', v_b_small, 'from_branch_id', v_gulshan, 'to_branch_id', v_dhaka, 'quantity', 96));

  perform public._p_act(v_pu);

  -- A: a plan with a valid transfer is saved as a draft
  r := public.create_plan(14, 'model', 'plan-hash-1', '[]'::jsonb, '[]'::jsonb, 1056, 576, good);
  if not (r ->> 'ok')::boolean or (r ->> 'reused')::boolean or r ->> 'state' <> 'draft' then
    raise exception 'FAIL A: %', r;
  end if;
  v_plan := (r ->> 'plan_id')::uuid;
  select count(*) into n from public.transfers where plan_id = v_plan;
  if n <> 1 then raise exception 'FAIL A: % transfers', n; end if;
  raise notice 'PASS A: a plan and its transfer are saved together';

  -- B: the same inputs reuse the same plan
  r := public.create_plan(14, 'model', 'plan-hash-1', '[]'::jsonb, '[]'::jsonb, 1056, 576, good);
  if not (r ->> 'reused')::boolean or (r ->> 'plan_id')::uuid <> v_plan then raise exception 'FAIL B: %', r; end if;
  raise notice 'PASS B: the same inputs reuse the same plan';

  -- C: a transfer that is not whole packs saves nothing
  r := public.create_plan(14, 'model', 'plan-hash-2', '[]'::jsonb, '[]'::jsonb, 0, 0, bad_pack);
  if (r ->> 'status')::int is distinct from 422 then raise exception 'FAIL C: %', r; end if;
  select count(*) into n from public.stock_plans where input_hash = 'plan-hash-2';
  if n <> 0 then raise exception 'FAIL C: a partial plan was kept'; end if;
  raise notice 'PASS C: a non-pack transfer is refused and nothing is kept (422)';

  -- D: an expired batch cannot be transferred
  r := public.create_plan(14, 'model', 'plan-hash-3', '[]'::jsonb, '[]'::jsonb, 0, 0, bad_expired);
  if (r ->> 'status')::int is distinct from 422 then raise exception 'FAIL D: %', r; end if;
  raise notice 'PASS D: an expired batch is refused (422)';

  -- E: a quantity larger than the batch is refused
  r := public.create_plan(14, 'model', 'plan-hash-4', '[]'::jsonb, '[]'::jsonb, 0, 0, bad_qty);
  if (r ->> 'status')::int is distinct from 422 then raise exception 'FAIL E: %', r; end if;
  raise notice 'PASS E: more than the batch holds is refused (422)';

  -- F: the purchaser can review the new plan
  select version into v_ver from public.stock_plans where id = v_plan;
  r := public.review_plan(v_plan, v_ver);
  if not (r ->> 'ok')::boolean then raise exception 'FAIL F: %', r; end if;
  raise notice 'PASS F: the new plan can be reviewed';

  -- G: the branch manager cannot generate plans
  perform public._p_act(v_mg);
  r := public.create_plan(14, 'model', 'plan-hash-5', '[]'::jsonb, '[]'::jsonb, 0, 0, '[]'::jsonb);
  if (r ->> 'status')::int is distinct from 403 then raise exception 'FAIL G: %', r; end if;
  raise notice 'PASS G: the branch manager is denied (403)';

  -- H: bad input is refused
  perform public._p_act(v_pu);
  r := public.create_plan(10, 'model', 'plan-hash-6', '[]'::jsonb, '[]'::jsonb, 0, 0, '[]'::jsonb);
  if (r ->> 'status')::int is distinct from 422 then raise exception 'FAIL H1: %', r; end if;
  r := public.create_plan(14, 'manual', 'plan-hash-6', '[]'::jsonb, '[]'::jsonb, 0, 0, '[]'::jsonb);
  if (r ->> 'status')::int is distinct from 422 then raise exception 'FAIL H2: %', r; end if;
  r := public.create_plan(14, 'model', 'plan-hash-6', '[]'::jsonb, '[]'::jsonb, -5, 0, '[]'::jsonb);
  if (r ->> 'status')::int is distinct from 422 then raise exception 'FAIL H3: %', r; end if;
  raise notice 'PASS H: invalid input is refused (422)';

  execute 'reset role';
  raise notice 'ALL PLAN TESTS PASSED';
end $$;

rollback;