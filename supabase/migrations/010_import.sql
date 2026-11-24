-- MEDIVO Step 5 / 010: sales import and data freshness.
-- The server checks everything again, so a modified app cannot slip bad data in.

create or replace function public.sales_freshness() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(
           jsonb_build_object('branch', b.name, 'last_day', s.last_day, 'days_old', current_date - s.last_day)
           order by b.name), '[]'::jsonb)
    from public.branches b
    left join (
      select branch_id, max(day) as last_day
        from public.medicine_sales
       where tenant_id = public.auth_tenant()
       group by branch_id
    ) s on s.branch_id = b.id
   where b.tenant_id = public.auth_tenant()
     and public.has_permission('view_overview')
$$;

create or replace function public.import_sales(p_rows jsonb, p_file_hash text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_tenant uuid := public.auth_tenant();
  v_detail jsonb := jsonb_build_object('file_hash', p_file_hash);
  v_existing uuid;
  v_import uuid;
  r jsonb;
  v_i integer := 0;
  v_ok integer := 0;
  v_nerr integer := 0;
  v_errors jsonb := '[]'::jsonb;
  v_extra text;
  v_day date;
  v_branch uuid;
  v_med uuid;
  v_qty integer;
  v_flag public.sales_flag;
begin
  if not public.has_permission('import_data') then
    return public._deny(403, 'Your role cannot import sales.', 'import_sales', v_detail);
  end if;
  if p_file_hash is null or btrim(p_file_hash) = '' then
    return public._deny(422, 'A file fingerprint is required.', 'import_sales', v_detail);
  end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then
    return public._deny(422, 'The file has no rows.', 'import_sales', v_detail);
  end if;
  if jsonb_array_length(p_rows) > 5000 then
    return public._deny(422, 'The file has more than 5,000 rows.', 'import_sales', v_detail);
  end if;

  -- The same file twice is not imported twice. The first import id is reused.
  select id into v_existing from public.sales_imports
   where tenant_id = v_tenant and file_hash = p_file_hash;
  if v_existing is not null then
    perform public.write_audit('sales import repeated', true, v_detail || jsonb_build_object('import_id', v_existing));
    return jsonb_build_object('ok', true, 'duplicate', true, 'import_id', v_existing,
                              'accepted', 0, 'rejected', 0, 'errors', '[]'::jsonb);
  end if;

  -- Whole-file rule: unknown or personal columns reject the entire file.
  for r in select value from jsonb_array_elements(p_rows) loop
    if jsonb_typeof(r) <> 'object' then
      return public._deny(422, 'Every row must have named columns.', 'import_sales', v_detail);
    end if;
    select string_agg(k, ', ') into v_extra
      from jsonb_object_keys(r) k
     where k not in ('date', 'branch', 'product_code', 'quantity', 'flag');
    if v_extra is not null then
      return public._deny(422,
        'Rejected: these columns are not allowed (' || left(v_extra, 80) || '). Remove personal or unknown fields.',
        'import_sales', v_detail);
    end if;
  end loop;

  insert into public.sales_imports (tenant_id, file_hash, row_count, imported_by)
  values (v_tenant, p_file_hash, 0, auth.uid())
  returning id into v_import;

  -- Row by row: good rows are saved, bad rows are listed with the reason.
  for r in select value from jsonb_array_elements(p_rows) loop
    v_i := v_i + 1;
    begin
      if exists (select 1 from jsonb_each_text(r) kv where kv.value ~ '^\s*[=@]') then
        raise exception 'formula-like cell blocked';
      end if;
      v_day := (r ->> 'date')::date;
      if v_day is null then raise exception 'date is missing'; end if;
      if v_day > current_date then raise exception 'date is in the future'; end if;
      if v_day < current_date - 400 then raise exception 'date is older than 400 days'; end if;
      if coalesce(r ->> 'quantity', '') !~ '^[0-9]{1,9}$' then
        raise exception 'quantity must be a whole number';
      end if;
      v_qty := (r ->> 'quantity')::integer;
      v_flag := coalesce(nullif(btrim(r ->> 'flag'), ''), 'routine')::public.sales_flag;
      select id into v_branch from public.branches
       where tenant_id = v_tenant and lower(name) = lower(btrim(coalesce(r ->> 'branch', '')));
      if v_branch is null then raise exception 'unknown branch'; end if;
      select id into v_med from public.medicines
       where tenant_id = v_tenant and upper(product_code) = upper(btrim(coalesce(r ->> 'product_code', '')));
      if v_med is null then raise exception 'unknown product code'; end if;

      insert into public.medicine_sales (tenant_id, medicine_id, branch_id, day, quantity, flag, import_id)
      values (v_tenant, v_med, v_branch, v_day, v_qty, v_flag, v_import)
      on conflict (tenant_id, medicine_id, branch_id, day, flag)
      do update set quantity = excluded.quantity, import_id = excluded.import_id;
      v_ok := v_ok + 1;
    exception when others then
      v_nerr := v_nerr + 1;
      if v_nerr <= 20 then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object('row', v_i + 1, 'message', sqlerrm));
      end if;
    end;
  end loop;

  if v_ok = 0 then
    delete from public.sales_imports where id = v_import;
    perform public.write_audit('import_sales denied', false,
      v_detail || jsonb_build_object('status', 422, 'message', 'No valid rows', 'rejected', v_nerr));
    return jsonb_build_object('ok', false, 'status', 422,
      'message', 'No valid rows were found in the file.',
      'accepted', 0, 'rejected', v_nerr, 'errors', v_errors);
  end if;

  update public.sales_imports set row_count = v_ok where id = v_import;
  perform public.write_audit('sales imported', true,
    v_detail || jsonb_build_object('import_id', v_import, 'accepted', v_ok, 'rejected', v_nerr));
  return jsonb_build_object('ok', true, 'duplicate', false, 'import_id', v_import,
                            'accepted', v_ok, 'rejected', v_nerr, 'errors', v_errors);
end $$;

revoke execute on function public.sales_freshness(), public.import_sales(jsonb, text) from public, anon;
grant execute on function public.sales_freshness(), public.import_sales(jsonb, text) to authenticated;