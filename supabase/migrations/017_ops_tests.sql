-- MEDIVO Step 9 / 017: tests for the operations functions. Rolled back at the end.
begin;

do $$
declare
  v_t uuid := '11111111-1111-1111-1111-111111111111';
  v_med uuid; v_br uuid; v_n int;
  r jsonb;
begin
  select id into v_med from public.medicines where tenant_id = v_t and product_code = 'NAPA500';
  select id into v_br from public.branches where tenant_id = v_t and name = 'Uttara';

  -- A: the restore report runs and every audit chain is intact
  r := public.admin_restore_report();
  if r -> 'rows' is null or r -> 'audit' is null then raise exception 'FAIL A: %', r; end if;
  if exists (select 1 from jsonb_array_elements(r -> 'audit') e where not (e -> 'chain' ->> 'ok')::boolean) then
    raise exception 'FAIL A: an audit chain is broken: %', r -> 'audit';
  end if;
  raise notice 'PASS A: the restore report runs and the audit chains are intact';

  -- B: an expired batch is refused in normal use
  begin
    insert into public.batches (tenant_id, medicine_id, branch_id, batch_code, quantity, expires_on)
    values (v_t, v_med, v_br, 'RESTORE-TEST', 5, current_date - 1);
    raise exception 'FAIL B: an expired batch was accepted';
  exception when sqlstate 'PT422' then
    raise notice 'PASS B: an expired batch is refused in normal use';
  end;

  -- C: the same row loads when the restore flag is on
  perform set_config('medivo.restore', 'on', true);
  insert into public.batches (tenant_id, medicine_id, branch_id, batch_code, quantity, expires_on)
  values (v_t, v_med, v_br, 'RESTORE-TEST', 5, current_date - 1);
  perform set_config('medivo.restore', 'off', true);
  select count(*) into v_n from public.batches where batch_code = 'RESTORE-TEST';
  if v_n <> 1 then raise exception 'FAIL C: the row was not loaded'; end if;
  raise notice 'PASS C: a restore can load rows that have expired since the backup';

  -- D: the flag is off again afterwards
  begin
    insert into public.batches (tenant_id, medicine_id, branch_id, batch_code, quantity, expires_on)
    values (v_t, v_med, v_br, 'RESTORE-TEST-2', 5, current_date - 1);
    raise exception 'FAIL D: the restore flag stayed on';
  exception when sqlstate 'PT422' then
    raise notice 'PASS D: the restore flag does not stay on';
  end;

  -- E: the app role cannot call the admin functions
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', '00000000-0000-0000-0000-000000000001', 'role', 'authenticated', 'aal', 'aal2')::text, true);
  execute 'set local role authenticated';
  begin
    perform public.admin_restore_report();
    raise exception 'FAIL E: the app role could call an admin function';
  exception when insufficient_privilege then
    raise notice 'PASS E: the app role cannot call the admin functions';
  end;

  execute 'reset role';
  raise notice 'ALL OPS TESTS PASSED';
end $$;

rollback;