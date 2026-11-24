-- MEDIVO Step 3B / 008: tests for the second-step rules. Rolled back at the end.
begin;

create or replace function public._test_act2(p uuid, p_aal text, p_totp_ts bigint) returns void
language plpgsql as $f$
declare
  v_amr jsonb;
begin
  execute 'reset role';
  v_amr := jsonb_build_array(jsonb_build_object('method', 'password', 'timestamp', extract(epoch from now())::bigint));
  if p_totp_ts is not null then
    v_amr := v_amr || jsonb_build_array(jsonb_build_object('method', 'totp', 'timestamp', p_totp_ts));
  end if;
  perform set_config('request.jwt.claim.sub', p::text, true);
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', p::text, 'role', 'authenticated', 'aal', p_aal, 'amr', v_amr)::text, true);
  execute 'set local role authenticated';
end $f$;
grant execute on function public._test_act2(uuid, text, bigint) to public;

do $$
declare
  v_mg uuid;
  v_b uuid;
  r jsonb;
  n int;
  v_now bigint := extract(epoch from now())::bigint;
begin
  select id into v_mg from auth.users where email = 'manager@medivo.test';
  if v_mg is null then raise exception 'Create the demo users first.'; end if;
  select id into v_b from public.batches where batch_code = 'B-6001';

  -- A: password only (aal1) -> the database shows and allows nothing
  perform public._test_act2(v_mg, 'aal1', null);
  select count(*) into n from public.batches;
  if n <> 0 then raise exception 'FAIL A: data visible without the second step'; end if;
  r := public.my_access();
  if r is not null then raise exception 'FAIL A: my_access answered at aal1: %', r; end if;
  raise notice 'PASS A: password alone shows nothing';

  -- B: verified (aal2) -> access works
  perform public._test_act2(v_mg, 'aal2', v_now);
  r := public.my_access();
  if r->>'role' <> 'branch_manager' then raise exception 'FAIL B: %', r; end if;
  raise notice 'PASS B: verified session gets its access';

  -- C: aal2 but the code was typed 10 minutes ago -> recall refused
  perform public._test_act2(v_mg, 'aal2', v_now - 600);
  r := public.recall_batch(v_b, 'stale check');
  if (r->>'status')::int is distinct from 403 then raise exception 'FAIL C: %', r; end if;
  raise notice 'PASS C: a recall needs a fresh code';

  -- D: fresh code -> recall allowed
  perform public._test_act2(v_mg, 'aal2', v_now);
  r := public.recall_batch(v_b, 'fresh check');
  if not (r->>'ok')::boolean then raise exception 'FAIL D: %', r; end if;
  raise notice 'PASS D: recall works after a fresh code';

  execute 'reset role';
  raise notice 'ALL MFA TESTS PASSED';
end $$;

rollback;