-- MEDIVO Step 4 / 009: sign-in and sign-out are written to the audit chain.
-- Only these four event names are accepted, so the app cannot write anything else.

create or replace function public.log_session_event(p_event text) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if p_event not in ('signed in', 'signed out', 'app locked', 'app unlocked') then
    raise exception 'MEDIVO_422: unknown event' using errcode = 'PT422';
  end if;
  perform public.write_audit(p_event, true, jsonb_build_object('client', 'app'));
end $$;

revoke execute on function public.log_session_event(text) from public, anon;
grant execute on function public.log_session_event(text) to authenticated;