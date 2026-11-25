-- MEDIVO Step 7 / 013: tests for forecast jobs. Rolled back at the end.
begin;

create or replace function public._f_act(p uuid) returns void
language plpgsql as $f$
begin
  execute 'reset role';
  perform set_config('request.jwt.claim.sub', p::text, true);
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', p::text, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  execute 'set local role authenticated';
end $f$;
grant execute on function public._f_act(uuid) to public;

do $$
declare
  v_t uuid := '11111111-1111-1111-1111-111111111111';
  v_pu uuid; v_mg uuid;
  v_med uuid; v_br uuid; v_run uuid; v_run2 uuid;
  r jsonb; n int; pts jsonb;
begin
  select id into v_pu from auth.users where email = 'purchaser@medivo.test';
  select id into v_mg from auth.users where email = 'manager@medivo.test';
  if v_pu is null or v_mg is null then raise exception 'Create the demo users first.'; end if;
  select id into v_med from public.medicines where tenant_id = v_t and product_code = 'NAPA500';
  select id into v_br from public.branches where tenant_id = v_t and name = 'Uttara';

  perform public._f_act(v_pu);

  -- A: a run is accepted as queued
  r := public.start_forecast_run(v_med, v_br, 7, 'model', 'fx-hash-1');
  if not (r ->> 'ok')::boolean or r ->> 'status' <> 'queued' or (r ->> 'reused')::boolean then
    raise exception 'FAIL A: %', r;
  end if;
  v_run := (r ->> 'run_id')::uuid;
  raise notice 'PASS A: a forecast job is accepted';

  -- B: the same input returns the same run (idempotent)
  r := public.start_forecast_run(v_med, v_br, 7, 'model', 'fx-hash-1');
  if (r ->> 'run_id')::uuid <> v_run or (r ->> 'attempt')::int <> 2 then raise exception 'FAIL B: %', r; end if;
  raise notice 'PASS B: the same input reuses the same run id';

  -- C: cannot finish a run that is not running
  pts := (select jsonb_agg(jsonb_build_object('day', to_char(current_date + g, 'YYYY-MM-DD'),
                                              'value', 10 + g, 'low', 8, 'high', 12, 'baseline', 9))
            from generate_series(0, 6) g);
  r := public.complete_forecast_run(v_run, pts, '{}'::jsonb);
  if (r ->> 'status')::int is distinct from 409 then raise exception 'FAIL C: %', r; end if;
  raise notice 'PASS C: a queued run cannot be completed (409)';

  -- D: wrong number of points is refused
  r := public.begin_forecast_run(v_run);
  if not (r ->> 'ok')::boolean then raise exception 'FAIL D begin: %', r; end if;
  r := public.complete_forecast_run(v_run, jsonb_build_array(jsonb_build_object('day', '2026-01-01', 'value', 1)), '{}'::jsonb);
  if (r ->> 'status')::int is distinct from 422 then raise exception 'FAIL D: %', r; end if;
  raise notice 'PASS D: a result with the wrong size is refused (422)';

  -- E: a valid result is stored
  r := public.complete_forecast_run(v_run, pts, jsonb_build_object('mae', 3.1));
  if not (r ->> 'ok')::boolean or r ->> 'status' <> 'succeeded' then raise exception 'FAIL E: %', r; end if;
  raise notice 'PASS E: a valid result is stored';

  -- F: the same input again does not recompute
  r := public.start_forecast_run(v_med, v_br, 7, 'model', 'fx-hash-1');
  if not (r ->> 'reused')::boolean or r ->> 'status' <> 'succeeded' then raise exception 'FAIL F: %', r; end if;
  raise notice 'PASS F: a finished run is reused, not recomputed';

  -- G: a crashed run resumes with the same id
  r := public.start_forecast_run(v_med, v_br, 14, 'baseline', 'fx-hash-2');
  v_run2 := (r ->> 'run_id')::uuid;
  perform public.begin_forecast_run(v_run2);
  r := public.start_forecast_run(v_med, v_br, 14, 'baseline', 'fx-hash-2');
  if (r ->> 'run_id')::uuid <> v_run2 or (r ->> 'attempt')::int <> 2 or r ->> 'status' <> 'queued' then
    raise exception 'FAIL G: %', r;
  end if;
  raise notice 'PASS G: an unfinished run is resumed with the same id (attempt 2)';

  -- H: a failed run can be recorded
  r := public.fail_forecast_run(v_run2, 'test_failure');
  if r ->> 'status' <> 'failed' then raise exception 'FAIL H: %', r; end if;
  raise notice 'PASS H: a failure is recorded';

  -- I: manual forecast needs an assumption and a sane percentage
  r := public.start_forecast_run(v_med, v_br, 7, 'manual', 'fx-hash-3', '  ', jsonb_build_object('percent', 10));
  if (r ->> 'status')::int is distinct from 422 then raise exception 'FAIL I1: %', r; end if;
  r := public.start_forecast_run(v_med, v_br, 7, 'manual', 'fx-hash-3', 'School holiday', jsonb_build_object('percent', 500));
  if (r ->> 'status')::int is distinct from 422 then raise exception 'FAIL I2: %', r; end if;
  r := public.start_forecast_run(v_med, v_br, 7, 'manual', 'fx-hash-3', 'School holiday', jsonb_build_object('percent', 10));
  if not (r ->> 'ok')::boolean then raise exception 'FAIL I3: %', r; end if;
  raise notice 'PASS I: manual forecasts need an assumption and a valid percentage';

  -- J: the branch manager cannot run forecasts
  perform public._f_act(v_mg);
  r := public.start_forecast_run(v_med, v_br, 7, 'model', 'fx-hash-4');
  if (r ->> 'status')::int is distinct from 403 then raise exception 'FAIL J: %', r; end if;
  raise notice 'PASS J: the branch manager is denied (403)';

  -- K: a finished run cannot be changed, even by the database owner
  execute 'reset role';
  begin
    update public.forecast_runs set points = '[]'::jsonb where id = v_run;
    raise exception 'FAIL K: a finished run was changed';
  exception when sqlstate 'PT409' then
    raise notice 'PASS K: a finished run is immutable';
  end;

  -- L: the job steps are in the audit chain
  perform public._f_act(v_pu);
  select count(*) into n from public.audit_log
   where action in ('forecast job accepted', 'forecast job started', 'forecast job succeeded', 'forecast run reused');
  if n < 4 then raise exception 'FAIL L: only % audit entries', n; end if;
  raise notice 'PASS L: job steps are in the audit chain';

  execute 'reset role';
  raise notice 'ALL FORECAST TESTS PASSED';
end $$;

rollback;