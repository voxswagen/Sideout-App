-- ═══════════════════════════════════════════════════════════════
-- sideout_unarchive — take one night back off the club ladder
-- ═══════════════════════════════════════════════════════════════
-- Already live on the project. This file is the deployed definition,
-- kept here so the function can be read without opening the dashboard
-- and re-run from scratch if it ever needs rebuilding.
--
-- The ladder is derived from `results` every time it is read, so
-- deleting the rows for one session code is the whole job. Nothing
-- else has to be recalculated.

create or replace function public.sideout_unarchive(
  p_club text,
  p_code text
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  c text := coalesce(p_club, 'sideout');
  caller text;
  v_deleted integer;
begin
  if p_code is null or length(trim(p_code)) = 0 then
    raise exception 'A session code is required.';
  end if;

  -- This guard is sideout_session_delete's, word for word. Resetting a night
  -- and deleting one are the same privilege, so the two should never drift
  -- into slightly different answers to "may this person organize?". If one
  -- changes, change the other in the same sitting.
  if auth.uid() is null then raise exception 'sign in first'; end if;
  select role into caller from public.members
   where club = c and user_id = auth.uid();
  if caller is null or caller not in ('owner','organizer') then
    raise exception 'only an organizer can reset a session';
  end if;

  delete from public.results r
   where r.club = c
     and r.code = p_code;

  get diagnostics v_deleted = row_count;

  -- Logged after the delete, not before, so the audit row can say how many
  -- results actually went. A reset cannot be undone -- Club.rate() writes
  -- absolute ratings rather than deltas -- so this count is the only surviving
  -- record that the night was ever on the ladder at all.
  perform public.sideout_log(c, 'session.reset', p_code, v_deleted || ' results');

  return v_deleted;
end;
$$;

revoke all on function public.sideout_unarchive(text, text) from public;
grant execute on function public.sideout_unarchive(text, text) to anon, authenticated;
