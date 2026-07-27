-- ═══════════════════════════════════════════════════════════════
-- sideout_unarchive — take one night back off the club ladder
-- ═══════════════════════════════════════════════════════════════
-- Run this once in the Supabase SQL editor.
--
-- The ladder is derived from `results` every time it is read, so
-- deleting the rows for one session code is the whole job. Nothing
-- else has to be recalculated.
--
-- IMPORTANT: the organizer guard below is written to match the
-- pattern your other admin functions use. Before running it, open
-- sideout_session_delete in the SQL editor and copy its guard
-- verbatim into the marked block — that way there is exactly one
-- definition of "may organize" and this cannot drift out of step
-- with the rest.

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
  v_deleted integer;
begin
  if p_code is null or length(trim(p_code)) = 0 then
    raise exception 'A session code is required.';
  end if;

  -- ── organizer guard ──────────────────────────────────────────
  -- Replace this block with the same check sideout_session_delete
  -- uses. It is here so the function is never callable by an
  -- ordinary member holding the publishable key.
  if not exists (
    select 1
    from public.members m
    where m.club = p_club
      and m.user_id = auth.uid()
      and m.role in ('owner', 'organizer')
  ) then
    raise exception 'Only an owner or organizer of this club can reset a session.';
  end if;
  -- ─────────────────────────────────────────────────────────────

  delete from public.results r
   where r.club = p_club
     and r.code = p_code;

  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

revoke all on function public.sideout_unarchive(text, text) from public;
grant execute on function public.sideout_unarchive(text, text) to anon, authenticated;
