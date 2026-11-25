-- MEDIVO Step 7 / 012: forecast runs as jobs.
-- A run is created once per input fingerprint (idempotent), moves
-- queued -> running -> succeeded | failed, and a succeeded run can never change.

alter table public.forecast_runs
  add column if not exists metrics jsonb not null default '{}'::jsonb,
  add column if not exists params jsonb not null default '{}'::jsonb,
  add column if not exists attempts integer not null default 0,
  add column if not exists finished_at timestamptz;

create or replace function public.forecast_run_guard() returns trigger
language plpgsql as $$
begin
  if old.status = 'succeeded' then
    raise exception 'MEDIVO_409: a finished forecast run cannot be changed' using errcode = 'PT409';
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end $$;
create trigger forecast_run_guard_trg before update or delete on public.forecast_runs
  for each row execute function public.forecast_run_guard();

create or replace function public._forecast_allowed(p_source text) returns boolean
language sql stable security definer set search_path = public as $$
  select case when p_source = 'manual'
              then public.has_permission('manual_forecast')
              else public.has_permission('run_forecast') end
$$;

create or replace function public.start_forecast_run(
  p_medicine uuid, p_branch uuid, p_horizon integer, p_source text,
  p_input_hash text, p_assumption text default null, p_params jsonb default '{}'::jsonb
) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_tenant uuid := public.auth_tenant();
  v_run public.forecast_runs%rowtype;
  v_id uuid;
  v_pct numeric;
  v_version text;
  v_detail jsonb := jsonb_build_object('source', p_source, 'horizon', p_horizon);
begin
  if not public._forecast_allowed(p_source) then
    return public._deny(403, 'Your role cannot run this kind of forecast.', 'start_forecast_run', v_detail);
  end if;
  if p_source is null or p_source not in ('model', 'baseline', 'manual') then
    return public._deny(422, 'Unknown forecast source.', 'start_forecast_run', v_detail);
  end if;
  if p_horizon is null or p_horizon not in (7, 14, 21) then
    return public._deny(422, 'The horizon must be 7, 14 or 21 days.', 'start_forecast_run', v_detail);
  end if;
  if p_input_hash is null or btrim(p_input_hash) = '' then
    return public._deny(422, 'An input fingerprint is required.', 'start_forecast_run', v_detail);
  end if;
  if p_source = 'manual' then
    if p_assumption is null or btrim(p_assumption) = '' then
      return public._deny(422, 'Record an assumption for a manual forecast.', 'start_forecast_run', v_detail);
    end if;
    begin
      v_pct := (p_params ->> 'percent')::numeric;
    exception when others then
      v_pct := null;
    end;
    if v_pct is null or v_pct < -50 or v_pct > 100 then
      return public._deny(422, 'The adjustment must be between -50% and 100%.', 'start_forecast_run', v_detail);
    end if;
  end if;

  v_version := case p_source when 'model' then 'lag-quantile-0.3'
                             when 'baseline' then 'seasonal-naive-1.0'
                             else 'manual-1.0' end;

  select * into v_run from public.forecast_runs
   where tenant_id = v_tenant and input_hash = p_input_hash for update;
  if found then
    if v_run.medicine_id <> p_medicine or v_run.branch_id <> p_branch
       or v_run.horizon_days <> p_horizon or v_run.source <> p_source then
      return public._deny(409, 'This fingerprint belongs to a different request.', 'start_forecast_run', v_detail);
    end if;
    if v_run.status = 'succeeded' then
      perform public.write_audit('forecast run reused', true, v_detail || jsonb_build_object('run_id', v_run.id));
      return jsonb_build_object('ok', true, 'run_id', v_run.id, 'status', 'succeeded',
                                'reused', true, 'attempt', v_run.attempts);
    end if;
    update public.forecast_runs
       set status = 'queued', attempts = attempts + 1, error_code = null
     where id = v_run.id;
    perform public.write_audit('forecast job accepted', true,
      v_detail || jsonb_build_object('run_id', v_run.id, 'attempt', v_run.attempts + 1, 'resumed', true));
    return jsonb_build_object('ok', true, 'run_id', v_run.id, 'status', 'queued',
                              'reused', false, 'attempt', v_run.attempts + 1);
  end if;

  begin
    insert into public.forecast_runs (tenant_id, medicine_id, branch_id, horizon_days, source,
                                      model_version, input_hash, assumption, params, status, attempts, created_by)
    values (v_tenant, p_medicine, p_branch, p_horizon, p_source, v_version, p_input_hash,
            nullif(btrim(coalesce(p_assumption, '')), ''), coalesce(p_params, '{}'::jsonb), 'queued', 1, auth.uid())
    returning id into v_id;
  exception
    when foreign_key_violation then
      return public._deny(422, 'Unknown medicine or branch.', 'start_forecast_run', v_detail);
    when unique_violation then
      return public._deny(409, 'The same request is already being processed. Try again.', 'start_forecast_run', v_detail);
  end;
  perform public.write_audit('forecast job accepted', true,
    v_detail || jsonb_build_object('run_id', v_id, 'attempt', 1, 'model_version', v_version));
  return jsonb_build_object('ok', true, 'run_id', v_id, 'status', 'queued', 'reused', false, 'attempt', 1);
end $$;

create or replace function public.begin_forecast_run(p_run uuid)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_tenant uuid := public.auth_tenant();
  v_run public.forecast_runs%rowtype;
  v_detail jsonb := jsonb_build_object('run_id', p_run);
begin
  select * into v_run from public.forecast_runs where id = p_run and tenant_id = v_tenant for update;
  if not found then
    return public._deny(422, 'Run not found.', 'begin_forecast_run', v_detail);
  end if;
  if not public._forecast_allowed(v_run.source) then
    return public._deny(403, 'Your role cannot run this kind of forecast.', 'begin_forecast_run', v_detail);
  end if;
  if v_run.status = 'succeeded' then
    return public._deny(409, 'This run is already finished.', 'begin_forecast_run', v_detail);
  end if;
  update public.forecast_runs set status = 'running' where id = p_run;
  perform public.write_audit('forecast job started', true, v_detail);
  return jsonb_build_object('ok', true, 'run_id', p_run, 'status', 'running');
end $$;

create or replace function public.complete_forecast_run(p_run uuid, p_points jsonb, p_metrics jsonb)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_tenant uuid := public.auth_tenant();
  v_run public.forecast_runs%rowtype;
  e jsonb;
  v_detail jsonb := jsonb_build_object('run_id', p_run);
begin
  select * into v_run from public.forecast_runs where id = p_run and tenant_id = v_tenant for update;
  if not found then
    return public._deny(422, 'Run not found.', 'complete_forecast_run', v_detail);
  end if;
  if not public._forecast_allowed(v_run.source) then
    return public._deny(403, 'Your role cannot run this kind of forecast.', 'complete_forecast_run', v_detail);
  end if;
  if v_run.status <> 'running' then
    return public._deny(409, 'The run is not in progress.', 'complete_forecast_run', v_detail);
  end if;
  if p_points is null or jsonb_typeof(p_points) <> 'array' or jsonb_array_length(p_points) <> v_run.horizon_days then
    return public._deny(422, 'The result must have one point per day of the horizon.', 'complete_forecast_run', v_detail);
  end if;
  for e in select value from jsonb_array_elements(p_points) loop
    if jsonb_typeof(e) <> 'object' or (e ->> 'day') is null or (e ->> 'value') !~ '^[0-9]+(\.[0-9]+)?$' then
      return public._deny(422, 'Every point needs a day and a value of zero or more.', 'complete_forecast_run', v_detail);
    end if;
  end loop;
  update public.forecast_runs
     set points = p_points, metrics = coalesce(p_metrics, '{}'::jsonb),
         status = 'succeeded', finished_at = now(), error_code = null
   where id = p_run;
  perform public.write_audit('forecast job succeeded', true,
    v_detail || jsonb_build_object('input_hash', v_run.input_hash, 'model_version', v_run.model_version));
  return jsonb_build_object('ok', true, 'run_id', p_run, 'status', 'succeeded');
end $$;

create or replace function public.fail_forecast_run(p_run uuid, p_code text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_tenant uuid := public.auth_tenant();
  v_run public.forecast_runs%rowtype;
  v_detail jsonb := jsonb_build_object('run_id', p_run);
begin
  select * into v_run from public.forecast_runs where id = p_run and tenant_id = v_tenant for update;
  if not found then
    return public._deny(422, 'Run not found.', 'fail_forecast_run', v_detail);
  end if;
  if not public._forecast_allowed(v_run.source) then
    return public._deny(403, 'Your role cannot run this kind of forecast.', 'fail_forecast_run', v_detail);
  end if;
  if v_run.status not in ('queued', 'running') then
    return public._deny(409, 'This run is already finished.', 'fail_forecast_run', v_detail);
  end if;
  update public.forecast_runs
     set status = 'failed', error_code = left(coalesce(nullif(btrim(p_code), ''), 'unknown'), 60), finished_at = now()
   where id = p_run;
  perform public.write_audit('forecast job failed', false,
    v_detail || jsonb_build_object('code', left(coalesce(p_code, 'unknown'), 60)));
  return jsonb_build_object('ok', true, 'run_id', p_run, 'status', 'failed');
end $$;

revoke execute on function public._forecast_allowed(text) from public, anon, authenticated;
revoke execute on function
  public.start_forecast_run(uuid, uuid, integer, text, text, text, jsonb),
  public.begin_forecast_run(uuid),
  public.complete_forecast_run(uuid, jsonb, jsonb),
  public.fail_forecast_run(uuid, text)
from public, anon;
grant execute on function
  public.start_forecast_run(uuid, uuid, integer, text, text, text, jsonb),
  public.begin_forecast_run(uuid),
  public.complete_forecast_run(uuid, jsonb, jsonb),
  public.fail_forecast_run(uuid, text)
to authenticated;