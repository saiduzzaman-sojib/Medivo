-- MEDIVO Step 2 / 006: security tests. Run the WHOLE file in the SQL editor.
-- Everything is rolled back at the end, so no data is changed.
-- Success = a series of "PASS" notices and "ALL TESTS PASSED". Any "FAIL" stops it.

begin;

create or replace function public._test_act(p uuid) returns void
language plpgsql as $f$
begin
  execute 'reset role';
  perform set_config('request.jwt.claim.sub', p::text, true);
  perform set_config('request.jwt.claims', json_build_object(
    'sub', p::text,
    'role', 'authenticated',
    'aal', 'aal2',
    'amr', json_build_array(json_build_object('method', 'totp', 'timestamp', extract(epoch from now())::bigint))
  )::text, true);
  execute 'set local role authenticated';
end $f$;
grant execute on function public._test_act(uuid) to public;

do $$
declare
  v_t uuid := '11111111-1111-1111-1111-111111111111';
  v_plan uuid := '33333333-3333-3333-3333-333333333333';
  v_ph uuid; v_pu uuid; v_mg uuid;
  v_med uuid; v_br uuid; v_tr uuid; v_ver int;
  r jsonb; n int; rec record;
begin
  select id into v_ph from auth.users where email = 'pharmacist@medivo.test';
  select id into v_pu from auth.users where email = 'purchaser@medivo.test';
  select id into v_mg from auth.users where email = 'manager@medivo.test';
  if v_ph is null or v_pu is null or v_mg is null then
    raise exception 'Create the three demo users and run 005 first.';
  end if;

  insert into public.tenants (id, name) values ('99999999-9999-9999-9999-999999999999', 'Other chain') on conflict do nothing;
  insert into public.branches (tenant_id, name) values ('99999999-9999-9999-9999-999999999999', 'Secret branch') on conflict do nothing;
  select id into v_med from public.medicines where tenant_id = v_t and product_code = 'NAPA500';
  select id into v_br from public.branches where tenant_id = v_t and name = 'Dhanmondi';

  -- 1 tenant isolation
  perform public._test_act(v_ph);
  select count(*) into n from public.branches where name = 'Secret branch';
  if n <> 0 then raise exception 'FAIL 1: another tenant''s data is visible'; end if;
  raise notice 'PASS 1: users cannot see another tenant''s data';

  -- 2 no direct writes
  begin
    insert into public.batches (tenant_id, medicine_id, branch_id, batch_code, quantity, expires_on)
    values (v_t, v_med, v_br, 'HACK-1', 5, current_date + 30);
    raise exception 'FAIL 2: a direct insert was allowed';
  exception when insufficient_privilege then
    raise notice 'PASS 2: direct writes are blocked';
  end;

  -- 3 expired stock rejected with 422
  r := public.add_batch(v_med, v_br, 'T-EXP', 10, current_date - 1);
  if (r->>'ok')::boolean or (r->>'status')::int <> 422 then raise exception 'FAIL 3: %', r; end if;
  raise notice 'PASS 3: expired stock is rejected (422)';

  -- 4 wrong role denied and audited
  perform public._test_act(v_pu);
  r := public.add_batch(v_med, v_br, 'T-NEW', 10, current_date + 30);
  if (r->>'ok')::boolean or (r->>'status')::int <> 403 then raise exception 'FAIL 4: %', r; end if;
  select count(*) into n from public.audit_log where action = 'add_batch denied' and not ok;
  if n < 1 then raise exception 'FAIL 4: the denial was not audited'; end if;
  raise notice 'PASS 4: wrong role is denied (403) and the denial is audited';

  -- 5 approval before review -> 409
  perform public._test_act(v_ph);
  select version into v_ver from public.stock_plans where id = v_plan;
  r := public.approve_plan(v_plan, v_ver, true);
  if (r->>'ok')::boolean or (r->>'status')::int <> 409 then raise exception 'FAIL 5: %', r; end if;
  raise notice 'PASS 5: approval needs a review first (409)';

  -- 6 pharmacist cannot review, purchaser stale version -> 409, correct -> ok
  r := public.review_plan(v_plan, v_ver);
  if (r->>'status')::int is distinct from 403 then raise exception 'FAIL 6a: %', r; end if;
  perform public._test_act(v_pu);
  r := public.review_plan(v_plan, v_ver + 5);
  if (r->>'status')::int is distinct from 409 then raise exception 'FAIL 6b: %', r; end if;
  r := public.review_plan(v_plan, v_ver);
  if not (r->>'ok')::boolean then raise exception 'FAIL 6c: %', r; end if;
  v_ver := (r->>'version')::int;
  raise notice 'PASS 6: only the purchaser reviews, stale versions are refused (409)';

  -- 7 approval blocked until moved batches are validated
  perform public._test_act(v_ph);
  r := public.approve_plan(v_plan, v_ver, true);
  if (r->>'status')::int is distinct from 422 then raise exception 'FAIL 7: %', r; end if;
  for rec in select distinct batch_id from public.transfers where plan_id = v_plan loop
    r := public.validate_batch(rec.batch_id);
    if not (r->>'ok')::boolean then raise exception 'FAIL 7 validate: %', r; end if;
  end loop;
  raise notice 'PASS 7: moved batches must be validated before approval';

  -- 8 handling rules must be confirmed, then approval works
  r := public.approve_plan(v_plan, v_ver, false);
  if (r->>'status')::int is distinct from 422 then raise exception 'FAIL 8a: %', r; end if;
  r := public.approve_plan(v_plan, v_ver, true);
  if not (r->>'ok')::boolean then raise exception 'FAIL 8b: %', r; end if;
  raise notice 'PASS 8: the pharmacist locks the plan after the checks';

  -- 9 transfers: only the branch manager, and only once
  select id into v_tr from public.transfers where plan_id = v_plan and state = 'pending' limit 1;
  r := public.decide_transfer(v_tr, true);
  if (r->>'status')::int is distinct from 403 then raise exception 'FAIL 9a: %', r; end if;
  perform public._test_act(v_mg);
  r := public.decide_transfer(v_tr, true);
  if not (r->>'ok')::boolean then raise exception 'FAIL 9b: %', r; end if;
  r := public.decide_transfer(v_tr, true);
  if (r->>'status')::int is distinct from 409 then raise exception 'FAIL 9c: %', r; end if;
  raise notice 'PASS 9: only the branch manager decides transfers, once (409 on repeat)';

  -- 10 recall: manager only
  perform public._test_act(v_ph);
  select id into rec from public.batches where batch_code = 'B-6001';
  r := public.recall_batch(rec.id, 'test');
  if (r->>'status')::int is distinct from 403 then raise exception 'FAIL 10a: %', r; end if;
  perform public._test_act(v_mg);
  r := public.recall_batch(rec.id, 'test recall');
  if not (r->>'ok')::boolean then raise exception 'FAIL 10b: %', r; end if;
  raise notice 'PASS 10: only the branch manager recalls batches';

  -- 11 approved plan is immutable, even for the database owner
  execute 'reset role';
  begin
    update public.stock_plans set orders = '[1]'::jsonb where id = v_plan;
    raise exception 'FAIL 11: an approved plan was changed';
  exception when sqlstate 'PT409' then
    raise notice 'PASS 11: approved plans are immutable';
  end;

  -- 12 audit log is append-only
  begin
    delete from public.audit_log;
    raise exception 'FAIL 12: the audit log was changed';
  exception when sqlstate 'PT409' then
    raise notice 'PASS 12: the audit log is append-only';
  end;

  -- 13 hash chain verifies
  perform public._test_act(v_ph);
  r := public.verify_audit_chain();
  if not (r->>'ok')::boolean then raise exception 'FAIL 13: %', r; end if;
  raise notice 'PASS 13: audit chain intact (% entries)', r->>'checked';

  -- 14 the app can ask what it is allowed to do
  r := public.my_access();
  if r->>'role' <> 'pharmacist' or jsonb_array_length(r->'permissions') <> 9 then raise exception 'FAIL 14: %', r; end if;
  raise notice 'PASS 14: my_access returns the role and permissions';

  execute 'reset role';
  raise notice 'ALL TESTS PASSED';
end $$;

rollback;