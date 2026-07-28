-- ═══════════════════════════════════════════════════════════════
-- sideout_player — one player's whole record, for their own page
-- ═══════════════════════════════════════════════════════════════
-- Already live on the project. This file is the deployed definition.
--
-- Built on `results` rather than on the game logs, because the logs live on
-- the session row and sideout_cleanup deletes those after seven days. A
-- record that quietly stopped going back more than a week would be worse
-- than not having one at all.
--
-- That does mean there are no partner or nemesis figures here. Who you
-- played with, and who beat you, exists only in the log — and the log does
-- not last long enough to build a season out of. Keeping those would need
-- them written into `results` at archive time, which is a bigger change.
--
-- Reads the caller's own record by default. Passing a member id reads
-- somebody else's, which is fair: the ladder already shows the whole club
-- everyone's wins. Nothing private is in here — no email, no phone, and
-- deliberately no payment.

create or replace function public.sideout_player(
  p_club text,
  p_member uuid default null
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with who as (
    select coalesce(
             p_member,
             (select m.id from public.members m
               where m.club = coalesce(p_club,'sideout') and m.user_id = auth.uid()
               limit 1)) as id
  ),
  card as (
    select m.id, coalesce(m.alias, m.name) as name, m.rating, m.rating_games, m.dupr, m.photo
      from public.members m, who
     where m.club = coalesce(p_club,'sideout') and m.id = who.id
  ),
  -- every night this person is in, with where they finished on it
  nights as (
    select r.code, r.title, r.played_at, r.games, r.wins, r.losses,
           r.pf, r.pa, r.crowns,
           (select count(*) + 1
              from public.results o
             where o.club = r.club and o.code = r.code and o.removed_at is null
               and (o.wins > r.wins
                    or (o.wins = r.wins and (o.pf - o.pa) > (r.pf - r.pa)))) as pos,
           (select count(*) from public.results o
             where o.club = r.club and o.code = r.code and o.removed_at is null) as field
      from public.results r, who
     where r.club = coalesce(p_club,'sideout')
       and r.member = who.id
       and r.removed_at is null
  )
  select case when (select id from card) is null then null else
    jsonb_build_object(
      'member',   (select id from card),
      'name',     (select name from card),
      'rating',   (select rating from card),
      'settled',  coalesce((select rating_games from card), 0) >= 6,
      'dupr',     (select dupr from card),
      'totals', (select jsonb_build_object(
                   'nights', count(*),
                   'games',  coalesce(sum(games), 0),
                   'wins',   coalesce(sum(wins), 0),
                   'losses', coalesce(sum(losses), 0),
                   'crowns', coalesce(sum(crowns), 0),
                   'wins_on_the_night', count(*) filter (where pos = 1),
                   'podiums', count(*) filter (where pos <= 3),
                   'first',  min(played_at),
                   'last',   max(played_at))
                 from nights),
      'nights', (select coalesce(jsonb_agg(jsonb_build_object(
                   'code', code, 'title', title, 'played_at', played_at,
                   'games', games, 'wins', wins, 'losses', losses,
                   'crowns', crowns, 'pos', pos, 'field', field)
                   order by played_at desc), '[]'::jsonb)
                 from nights))
  end;
$$;

grant execute on function public.sideout_player(text, uuid) to anon, authenticated;
