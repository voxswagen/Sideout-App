-- ═══════════════════════════════════════════════════════════════
-- sideout_past — the ended nights behind the home feed
-- ═══════════════════════════════════════════════════════════════
-- Already live on the project. This file is the deployed definition.
--
-- The `owing` column is the reason this is worth keeping written down.
-- The past feed is readable by anon, so a count of who still owes cannot
-- simply be selected: it comes back null unless the caller is an owner or
-- organizer of the club, and the card only draws the line when it is not
-- null. That null is the permission check — there is no second rule in the
-- client that could drift away from this one.

drop function if exists public.sideout_past(text);

create function public.sideout_past(p_club text)
returns table(code text, title text, played_at timestamptz,
              players integer, games integer, cover text, owing integer)
language sql
stable
security definer
set search_path = public
as $$
  select r.code,
         min(r.title),
         max(r.played_at),
         count(*)::int,
         (sum(r.games) / 4)::int,
         -- The kept copy first, falling back to the live session for
         -- a night that ended before this table existed.
         coalesce(max(cv.cover), max(nullif(s.snapshot->>'cover',''))),
         -- Checking the club constant rather than r.club keeps this out
         -- of the group by.
         case when exists (
                select 1 from public.members me
                 where me.club = coalesce(p_club, 'sideout')
                   and me.user_id = auth.uid()
                   and me.role in ('owner', 'organizer'))
              then (count(*) filter (where not coalesce(r.paid, false)))::int
         end
    from public.results r
    left join public.session_covers cv
      on cv.code = r.code and cv.club = r.club
    left join public.sessions s
      on s.code = r.code and s.club = r.club
   where r.club = coalesce(p_club, 'sideout')
     -- a night that was reset is put aside, not deleted; it must not show
     and r.removed_at is null
   group by r.code
   order by 3 desc
   limit 60;
$$;

grant execute on function public.sideout_past(text) to anon, authenticated;


-- ═══════════════════════════════════════════════════════════════
-- sideout_upcoming — the nights still to come behind the home feed
-- ═══════════════════════════════════════════════════════════════
-- Already live on the project. This file is the deployed definition.
--
-- `group_id` is on the end because the session card's "next session" line
-- has to find the next night the same group is running, and this was the
-- obvious place to ask — except it never said which group anything belonged
-- to, so there was no telling one group's next Friday from another's. On the
-- end, where a client reading fields by name cannot notice it arriving.
--
-- "By link only" hides a session from the club, not from the people who run
-- it: staff see everything their club has on, because they are the ones who
-- have to manage it.

drop function if exists public.sideout_upcoming(text);

create function public.sideout_upcoming(p_club text)
returns table(code text, title text, starts_at timestamptz,
              ends_at timestamptz, venue text, repeat text,
              cap integer, joined integer, waiting integer, live boolean,
              ended boolean, mine boolean, cover text, group_id uuid)
language sql
stable
security definer
set search_path = public
as $$
  select s.code,
         nullif(s.snapshot->>'title',''),
         case when s.snapshot->>'startsAt' ~ '^[0-9]+$'
              then to_timestamp(((s.snapshot->>'startsAt')::bigint)/1000.0) end,
         case when s.snapshot->>'endsAt' ~ '^[0-9]+$'
              then to_timestamp(((s.snapshot->>'endsAt')::bigint)/1000.0) end,
         nullif(s.snapshot->>'venue',''),
         nullif(s.snapshot->>'repeat',''),
         coalesce((s.snapshot->>'cap')::int, 0),
         coalesce(jsonb_array_length(s.snapshot->'roster'), 0),
         coalesce(jsonb_array_length(s.snapshot->'waiting'), 0),
         public.sideout_started(s.snapshot),
         coalesce((s.snapshot->>'ended')::boolean, false),
         -- am I on this one? matched through my member record, so it
         -- follows the account rather than the device.
         exists (
           select 1
             from public.joiners j
             join public.members me
               on me.club = s.club and me.user_id = auth.uid()
            where j.code = s.code
              and j.kind = 'join'
              and (j.member = me.id
                   or lower(j.name) = lower(coalesce(me.alias, me.name)))
              -- a withdrawal the host has not processed yet still
              -- counts: the card should not claim you are in
              and not exists (
                select 1 from public.joiners w
                 where w.code = s.code and w.kind = 'leave' and not w.taken
                   and w.member = me.id)
         ),
         nullif(s.snapshot->>'cover',''),
         s.group_id
    from public.sessions s
   where s.club = coalesce(p_club,'sideout')
     and (s.listed or exists (
           select 1 from public.members me
            where me.club = s.club and me.user_id = auth.uid()
              and me.role in ('owner','organizer')))
     and not coalesce((s.snapshot->>'ended')::boolean, false)
   order by 3 nulls last, s.updated_at desc
   limit 40;
$$;

grant execute on function public.sideout_upcoming(text) to anon, authenticated;
