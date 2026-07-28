-- ═══════════════════════════════════════════════════════════════
-- Reversible reset — putting a night aside instead of deleting it
-- ═══════════════════════════════════════════════════════════════
-- Already live on the project. This file is the deployed definition.
--
-- Reset used to delete a night's result rows outright, and Club.rate()
-- writes absolute ratings rather than deltas, so the ratings it had moved
-- could never be put back. Both halves are recoverable now.
--
-- rating_before is captured at archive time, which works because the client
-- calls Club.archive() before Club.rate(): at the moment a night is banked,
-- every member's stored rating is still their pre-session one. No client
-- change was needed for it.
--
-- Rows that predate this column have rating_before null, and the restore
-- skips those rather than blanking a rating that has since moved on.

alter table public.results add column if not exists rating_before numeric;
alter table public.results add column if not exists removed_at timestamptz;

create index if not exists results_live_idx on public.results (club, code) where removed_at is null;

-- ── banking a night records what each player was rated first ──
create or replace function public.sideout_archive(
  p_club text, p_code text, p_title text, p_rows jsonb)
returns integer
language plpgsql
security definer
set search_path = public
as $function$
declare n int;
begin
  insert into public.results (club, code, title, member, name, games, wins, losses,
                              pf, pa, crowns, paid, rating_before)
  select coalesce(p_club,'sideout'), p_code, p_title,
         nullif(r->>'m','')::uuid, r->>'n',
         coalesce((r->>'g')::int,0), coalesce((r->>'w')::int,0), coalesce((r->>'l')::int,0),
         coalesce((r->>'pf')::int,0), coalesce((r->>'pa')::int,0), coalesce((r->>'c')::int,0),
         coalesce((r->>'paid')::boolean, false),
         m.rating
    from jsonb_array_elements(p_rows) r
    left join public.members m
      on m.id = nullif(r->>'m','')::uuid
     and m.club = coalesce(p_club,'sideout')
   where coalesce((r->>'g')::int,0) > 0;
  get diagnostics n = row_count;
  begin
    perform public.sideout_keep_cover(p_club, p_code);
  exception when others then null;   -- a missing picture must never fail an archive
  end;
  return n;
end $function$;

-- ── resetting puts the rows aside and the ratings back ──
create or replace function public.sideout_unarchive(p_club text, p_code text)
returns integer
language plpgsql
security definer
set search_path = public
as $function$
declare
  c text := coalesce(p_club, 'sideout');
  caller text;
  v_deleted integer;
begin
  if p_code is null or length(trim(p_code)) = 0 then
    raise exception 'A session code is required.';
  end if;

  -- sideout_session_delete's guard, word for word: resetting a night and
  -- deleting one are the same privilege and must not drift apart.
  if auth.uid() is null then raise exception 'sign in first'; end if;
  select role into caller from public.members
   where club = c and user_id = auth.uid();
  if caller is null or caller not in ('owner','organizer') then
    raise exception 'only an organizer can reset a session';
  end if;

  update public.members m
     set rating = r.rating_before
    from public.results r
   where r.club = c and r.code = p_code and r.removed_at is null
     and r.member = m.id and m.club = c
     and r.rating_before is not null;

  update public.results
     set removed_at = now()
   where club = c and code = p_code and removed_at is null;

  get diagnostics v_deleted = row_count;
  perform public.sideout_log(c, 'session.reset', p_code, v_deleted || ' results');
  return v_deleted;
end $function$;

-- ── and the undo ──
-- Ratings are not recalculated: they were put back as they were, and working
-- them forward again would need the game-by-game log, which does not outlive
-- the session row. The night returns to the ladder; ratings stay where the
-- reset left them until the next night moves them.
create or replace function public.sideout_restore(p_club text, p_code text)
returns integer
language plpgsql
security definer
set search_path = public
as $function$
declare
  c text := coalesce(p_club, 'sideout');
  caller text;
  v_back integer;
begin
  if auth.uid() is null then raise exception 'sign in first'; end if;
  select role into caller from public.members
   where club = c and user_id = auth.uid();
  if caller is null or caller not in ('owner','organizer') then
    raise exception 'only an organizer can restore a session';
  end if;

  -- If the night has been played again since the reset, its new rows are
  -- already on the ladder and putting the old ones back would count it twice.
  if exists (select 1 from public.results
              where club = c and code = p_code and removed_at is null) then
    raise exception 'That night has been played again since it was reset.';
  end if;

  update public.results set removed_at = null
   where club = c and code = p_code and removed_at is not null;
  get diagnostics v_back = row_count;

  perform public.sideout_log(c, 'session.restore', p_code, v_back || ' results');
  return v_back;
end $function$;

revoke all on function public.sideout_restore(text, text) from public;
grant execute on function public.sideout_restore(text, text) to anon, authenticated;

-- ═══════════════════════════════════════════════════════════════
-- Every reader of `results` skips the rows a reset put aside.
-- Without this the soft delete would be worse than the hard one: the night
-- would still be on the ladder while appearing to have been reset.
-- sideout_past and sideout_recap carry the same filter and live in their
-- own files.
-- ═══════════════════════════════════════════════════════════════

create or replace function public.sideout_ladder(p_club text, p_season boolean default false)
returns table(key text, member uuid, name text, nights bigint, games bigint, wins bigint,
              losses bigint, pf bigint, pa bigint, crowns bigint, last_seen timestamptz)
language sql
security definer
set search_path = public
as $function$
  select coalesce(r.member::text, 'n:' || lower(trim(r.name)))            as key,
         (array_agg(r.member) filter (where r.member is not null))[1]  as member,
         (array_agg(r.name order by r.played_at desc))[1]                 as name,
         count(*)                                                         as nights,
         sum(r.games)::bigint, sum(r.wins)::bigint, sum(r.losses)::bigint,
         sum(r.pf)::bigint, sum(r.pa)::bigint, sum(r.crowns)::bigint,
         max(r.played_at)
    from public.results r
   where r.club = coalesce(p_club,'sideout')
     and r.removed_at is null
     and (not coalesce(p_season, false)
          or r.played_at >= public.sideout_season_start(p_club))
   group by 1
   order by sum(r.wins) desc, sum(r.pf) - sum(r.pa) desc;
$function$;

create or replace function public.sideout_points(p_club text)
returns table(member uuid, name text, nights integer, points integer)
language sql
stable
security definer
set search_path = public
as $function$
  with ranked as (
    select r.member, r.name, r.code,
           row_number() over (partition by r.code
                              order by r.wins desc, (r.pf - r.pa) desc, r.games desc) as pos
      from public.results r
     where r.club = coalesce(p_club,'sideout')
       and r.removed_at is null
  )
  select (array_agg(k.member) filter (where k.member is not null))[1],
         min(k.name),
         count(*)::int,
         sum(1
             + case when k.pos <= 10 then 1 else 0 end
             + case when k.pos <= 3  then 1 else 0 end)::int
    from ranked k
   group by coalesce(k.member::text, 'n:' || lower(trim(k.name)));
$function$;

create or replace function public.sideout_takings(p_club text, p_code text)
returns table(name text, member uuid, paid boolean)
language sql
stable
security definer
set search_path = public
as $function$
  select r.name, r.member, r.paid
    from public.results r
   where r.club = coalesce(p_club,'sideout') and r.code = p_code
     and r.removed_at is null
     and exists (select 1 from public.members me
                  where me.club = r.club and me.user_id = auth.uid()
                    and me.role in ('owner','organizer'))
   order by r.paid, lower(r.name);
$function$;
