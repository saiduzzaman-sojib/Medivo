-- MEDIVO Step 5 / 011: tests for the import rules. Rolled back at the end.
begin;

create or replace function public._t_act(p uuid) returns void
language plpgsql as $f$
begin
  execute 'reset role';
  perform set_config('request.jwt.claim.sub', p::text, true);
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', p::text, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  execute 'set local role authenticated';
end $f$;
grant execute on function public._t_act(uuid) to public;

do $$
declare
  v_pu uuid; v_mg uuid;
  r jsonb;
  d text := to_char(current_date - 1, 'YYYY-MM-DD');
begin
  select id into v_pu from auth.users where email = 'purchaser@medivo.test';
  select id into v_mg from auth.users where email = 'manager@medivo.test';
  if v_pu is null or v_mg is null then raise exception 'Create the demo users first.'; end if;

  perform public._t_act(v_pu);

  -- A: a personal column rejects the whole file
  r := public.import_sales(jsonb_build_array(jsonb_build_object(
         'date', d, 'branch', 'Uttara', 'product_code', 'NAPA500', 'quantity', '10', 'patient_name', 'X')), 'hash-a');
  if (r ->> 'status')::int is distinct from 422 then raise exception 'FAIL A: %', r; end if;
  raise notice 'PASS A: personal columns reject the file';

  -- B: good rows are saved, bad rows are listed
  r := public.import_sales(jsonb_build_array(
         jsonb_build_object('date', d, 'branch', 'Uttara', 'product_code', 'NAPA500', 'quantity', '10'),
         jsonb_build_object('date', d, 'branch', 'Mirpur', 'product_code', 'ORS', 'quantity', '7'),
         jsonb_build_object('date', d, 'branch', 'Nowhere', 'product_code', 'ORS', 'quantity', '7'),
         jsonb_build_object('date', d, 'branch', 'Gulshan', 'product_code', 'ORS', 'quantity', '3.5'),
         jsonb_build_object('date', d, 'branch', 'Gulshan', 'product_code', 'ORS', 'quantity', '=1+1')), 'hash-b');
  if not (r ->> 'ok')::boolean or (r ->> 'accepted')::int <> 2 or (r ->> 'rejected')::int <> 3 then
    raise exception 'FAIL B: %', r;
  end if;
  raise notice 'PASS B: 2 rows accepted, 3 rejected with reasons';

  -- C: the same file again is not imported twice
  r := public.import_sales(jsonb_build_array(
         jsonb_build_object('date', d, 'branch', 'Uttara', 'product_code', 'NAPA500', 'quantity', '10')), 'hash-b');
  if not (r ->> 'duplicate')::boolean then raise exception 'FAIL C: %', r; end if;
  raise notice 'PASS C: a repeated file reuses the first import';

  -- D: the branch manager cannot import
  perform public._t_act(v_mg);
  r := public.import_sales(jsonb_build_array(
         jsonb_build_object('date', d, 'branch', 'Uttara', 'product_code', 'NAPA500', 'quantity', '1')), 'hash-d');
  if (r ->> 'status')::int is distinct from 403 then raise exception 'FAIL D: %', r; end if;
  raise notice 'PASS D: the branch manager is denied (403)';

  -- E: freshness lists all four branches
  if jsonb_array_length(public.sales_freshness()) <> 4 then
    raise exception 'FAIL E: %', public.sales_freshness();
  end if;
  raise notice 'PASS E: data freshness lists every branch';

  execute 'reset role';
  raise notice 'ALL IMPORT TESTS PASSED';
end $$;

rollback;