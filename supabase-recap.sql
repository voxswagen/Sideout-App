-- ═══════════════════════════════════════════════════════════════
-- sideout_recap — one night, as a page anyone can be shown
-- ═══════════════════════════════════════════════════════════════
-- Already live on the project. This file is the deployed definition.
--
-- Deliberately not a read of `state`. That column carries the host PIN,
-- internal ratings, the waiting list and the venue notes, and runs to most
-- of a megabyte on a busy night. This assembles only what the recap page
-- shows, so the rest cannot leak by accident. The same night comes back at
-- about 141 kB, nearly all of it the cover photo.
--
-- No organizer check: a share link is meant to open for whoever is sent it,
-- signed in or not. The session code is the only key, which is the same
-- bargain the join link already makes.
--
-- Returns null when the night has no banked results. A session that was
-- reset has nothing to recap, and the client says so rather than drawing an
-- empty table.
--
-- Ordering matters here. The app unshifts each finished game onto the front
-- of state.log, so the stored order runs the night backwards. Games come
-- back round, then court, then as recorded.
--
-- The group and the venue ride along for the story card, which puts the
-- group's name, its home court and its logo across the top — so a night run
-- under Sideout Society is posted as Sideout Society rather than as whatever
-- the whole app happens to be called. Both are null for a night filed under
-- no group, which the card reads as "fall back to the club" rather than as
-- an error.

create or replace function public.sideout_recap(p_club text, p_code text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with head as (
    select min(r.title) as title,
           max(r.played_at) as played_at,
           count(*)::int as players
      from public.results r
     where r.club = coalesce(p_club, 'sideout') and r.code = p_code
       and r.removed_at is null
  ),
  board as (
    select coalesce(jsonb_agg(jsonb_build_object(
             'name',   r.name,
             'games',  r.games,
             'wins',   r.wins,
             'losses', r.losses,
             'pf',     r.pf,
             'pa',     r.pa,
             'crowns', r.crowns)
             order by r.wins desc nulls last,
                      (coalesce(r.pf, 0) - coalesce(r.pa, 0)) desc,
                      lower(r.name)), '[]'::jsonb) as rows
      from public.results r
     where r.club = coalesce(p_club, 'sideout') and r.code = p_code
       and r.removed_at is null
  ),
  -- The log lives on the session, which outlives the night but can be
  -- deleted on its own. An empty list here is normal, not an error.
  games as (
    select coalesce(jsonb_agg(jsonb_build_object(
             'r',    g->'r',
             'court', g->'c',
             'king', coalesce(g->'king', 'false'::jsonb),
             'win',  coalesce(g->'win',  '[]'::jsonb),
             'lose', coalesce(g->'lose', '[]'::jsonb))
             order by (g->>'r')::int nulls last,
                      (g->>'c')::int nulls last,
                      ord), '[]'::jsonb) as rows
      from public.sessions s
      cross join lateral jsonb_array_elements(
             coalesce(s.state->'log', '[]'::jsonb)) with ordinality as t(g, ord)
     where s.club = coalesce(p_club, 'sideout') and s.code = p_code
  ),
  pic as (
    select coalesce(max(cv.cover), max(nullif(s.snapshot->>'cover', ''))) as img
      from public.results r
      left join public.session_covers cv on cv.code = r.code and cv.club = r.club
      left join public.sessions s        on s.code  = r.code and s.club  = r.club
     where r.club = coalesce(p_club, 'sideout') and r.code = p_code
       and r.removed_at is null
  ),
  -- Where it was played, as the organizer typed it. The raw venue is a
  -- pasted Maps link more often than not, so only the resolved name is
  -- handed out — it is the half that is meant to be read.
  place as (
    select nullif(s.snapshot->>'venueName', '') as venue
      from public.sessions s
     where s.club = coalesce(p_club, 'sideout') and s.code = p_code
  ),
  -- What the night actually was: when it ran, how it was played, how many
  -- courts and to what standard. All of it already stored — the snapshot for
  -- the schedule and the format, state.courtLevels for the standard — and
  -- none of it was reaching the card, which had no way to say any of it
  -- without inventing it.
  --
  -- courtLevels comes out of state rather than the snapshot because the
  -- snapshot carries each court's *tag*, which is prose written for players
  -- ("Top table", "Matched") and not the level code. Only the derived list
  -- travels; nothing else out of state is touched, and the rule that state
  -- itself is never handed out still holds.
  meta as (
    select jsonb_build_object(
             'starts_at', case when s.snapshot->>'startsAt' ~ '^[0-9]+$'
                               then (s.snapshot->>'startsAt')::bigint end,
             'ends_at',   case when s.snapshot->>'endsAt' ~ '^[0-9]+$'
                               then (s.snapshot->>'endsAt')::bigint end,
             'mode',      nullif(s.snapshot->>'mode', ''),
             'mode_name', nullif(s.snapshot->>'modeName', ''),
             'timed',     coalesce((s.snapshot->>'timed')::boolean, true),
             'mins',      nullif(s.snapshot->>'mins', '')::int,
             'target',    nullif(s.snapshot->>'target', '')::int,
             'courts',    nullif(s.state->>'nCourts', '')::int,
             'levels',    coalesce(s.state->'courtLevels', '[]'::jsonb)) as row
      from public.sessions s
     where s.club = coalesce(p_club, 'sideout') and s.code = p_code
  ),
  -- The logo is a data URL of about 20–40 kB, small beside the cover this
  -- payload already carries, and public already through sideout_groups.
  -- Nothing new is exposed by putting it here.
  grp as (
    select jsonb_build_object(
             'id',         g.id,
             'name',       g.name,
             'home_court', g.home_court,
             -- the card wears the group's colour, not the viewer's theme
             'accent',     nullif(g.theme->>'accent', ''),
             'photo',      g.photo) as row
      from public.sessions s
      join public.groups g on g.id = s.group_id
     where s.club = coalesce(p_club, 'sideout') and s.code = p_code
  )
  select case when (select players from head) = 0 then null else
    jsonb_build_object(
      'code',      p_code,
      'title',     (select title     from head),
      'played_at', (select played_at from head),
      'players',   (select players   from head),
      'venue',     (select venue     from place),
      'meta',      (select row       from meta),
      'group',     (select row       from grp),
      'cover',     (select img       from pic),
      'standings', (select rows      from board),
      'games',     (select rows      from games))
  end;
$$;

grant execute on function public.sideout_recap(text, text) to anon, authenticated;
