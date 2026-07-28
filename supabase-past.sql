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
