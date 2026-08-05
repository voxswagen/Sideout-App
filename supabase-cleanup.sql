-- ═══════════════════════════════════════════════════════════════════════
-- CLEANUP — the hourly sweep, and the night it kept eating
-- ═══════════════════════════════════════════════════════════════════════
-- A copy of what is deployed, not a to-do. Applied 5 August 2026.
--
-- pg_cron runs sideout_cleanup() on the hour. It used to contain:
--
--     delete from public.sessions where updated_at < now() - interval '7 days';
--
-- which deleted every session row more than a week old, whether or not the
-- night had been played. Results are kept for ever, because the ladder is
-- derived from them — but the `sessions` row is what every list of nights
-- joins to find the group, the title and the cover. So a fortnight after a
-- session, the club's own record of it was still in `results` and had
-- vanished from the group's Sessions tab, its player list and its recap.
--
-- It also meant a night restored by hand was deleted again within the hour,
-- every hour, which is exactly what happened to PICKLEBALL BINGO three times
-- before anybody thought to look at the cron table.
--
-- What the sweep is actually for is set-ups nobody ever played: somebody opens
-- the organizer screen, half fills it in and abandons it. Those have no
-- results and no matches, and they are the only ones that should go.
create or replace function public.sideout_cleanup()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.sideout_autofinish(12);

  -- Sign-ins answer "who is still around", which is a question about now.
  -- After a month they stop being useful and start being a permanent record
  -- of when each member was on their phone, which is not something a club
  -- needs to keep. Decisions — roles, removals, seasons — are never touched:
  -- those are the accountability trail and they stay for good.
  delete from public.club_audit
   where action = 'signin' and at < now() - interval '30 days';

  -- Stale, and nothing was ever played on it.
  delete from public.sessions s
   where s.updated_at < now() - interval '7 days'
     and not exists (select 1 from public.results r where r.code = s.code)
     and not exists (select 1 from public.matches m where m.code = s.code);

  -- Joiners belong to a session; they live as long as it does.
  delete from public.joiners j
   where j.created_at < now() - interval '7 days'
     and not exists (select 1 from public.sessions s where s.code = j.code);

  delete from public.session_keys where code not in (select code from public.sessions);
end
$$;
