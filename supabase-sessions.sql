-- ===========================================================================
-- Sessions: saving one, and deleting one so that it stays deleted.
--
-- What is deployed, mirrored back here so the repo and the project do not
-- quietly disagree.
-- ===========================================================================

-- Deleting a session did not stick.
--
-- sideout_session_delete removes the joiners, the key and the row. Properly
-- gone. But any phone still holding that night in local storage keeps calling
-- sideout_save on its next beat, and sideout_save ends in an upsert:
--
--   insert into sessions (...) on conflict (code) do update ...
--
-- With no row left to conflict with, that is an insert. And the missing
-- session_keys row does not stop it either, because sideout_save puts the key
-- back from whatever PIN the phone is carrying. So the night reappeared, with
-- its old code, from the first phone that touched anything -- and it was the
-- beat that did it, which fires on every keystroke, not the once-per-open
-- resume() that had already been guarded.
--
-- This has to be answered here rather than in the app: the phone doing it is
-- often one that will not get a new build for days.
create table if not exists public.session_tombs (
  code       text primary key,
  club       text,
  killed_at  timestamptz not null default now(),
  killed_by  uuid
);

alter table public.session_tombs enable row level security;
-- No policies: nothing outside a SECURITY DEFINER function has any business
-- reading or writing this.
revoke all on public.session_tombs from anon, authenticated;


create or replace function public.sideout_session_delete(p_club text, p_code text)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare c text := coalesce(p_club, 'sideout'); caller text; me uuid;
begin
  if auth.uid() is null then raise exception 'sign in first'; end if;
  select role into caller from public.members
   where club = c and user_id = auth.uid();
  if caller is null or caller not in ('owner','organizer') then
    raise exception 'only an organizer can delete a session';
  end if;
  if not exists (select 1 from public.sessions where code = p_code and club = c) then
    raise exception 'no such session in this club';
  end if;

  select id into me from public.members where club = c and user_id = auth.uid();

  -- Written before the delete, so there is no window in which the row is gone
  -- and a beat arriving in that instant can put it back.
  insert into public.session_tombs (code, club, killed_by)
  values (p_code, c, me)
  on conflict (code) do update set killed_at = now(), killed_by = excluded.killed_by;

  delete from public.joiners      where code = p_code;
  delete from public.session_keys where code = p_code;
  perform public.sideout_log(c, 'session.delete', p_code, null);
  delete from public.sessions     where code = p_code and club = c;
end $function$;


-- There is exactly one of these. There used to be two -- a six-argument twin
-- without p_group -- and an overloaded sideout_* is a broken one: PostgREST
-- resolves an RPC by the argument names it is given and cannot choose between
-- two candidates when the extra arguments of one default. That is the fault
-- that killed chat for the whole club and blanked Matchups. The twin is
-- dropped; replace this one, never add beside it.
-- Replaced, not added beside: an overloaded sideout_* function is a broken
-- one, and this gained an argument. Both signatures are dropped first.
--
-- `p_seen` is the `updated_at` the caller last saw. Given one, the write is
-- refused if the row has moved on since — which turns "your co-host's points
-- vanished" into an answer the client can act on: read what they wrote, put
-- your own courts back on top, and save again. It defaults to null so a
-- client that does not send it behaves exactly as before, which is what
-- keeps phones on a stale cache working the day this lands.
drop function if exists public.sideout_save(text,text,jsonb,jsonb,text,boolean,uuid);
drop function if exists public.sideout_save(text,text,jsonb,jsonb,text,boolean,uuid,timestamptz);

create function public.sideout_save(
  p_code text, p_pin text, p_state jsonb, p_snapshot jsonb,
  p_club text default null, p_listed boolean default null, p_group uuid default null,
  p_seen timestamptz default null)
returns timestamptz
language plpgsql
security definer
set search_path to 'public'
as $function$
declare existing text; stamp timestamptz := now(); prior uuid;
begin
  if p_code is null or char_length(p_code) < 4 then raise exception 'bad code'; end if;
  if p_pin  is null or char_length(p_pin)  < 4 then raise exception 'bad pin';  end if;

  -- A night somebody deleted is not a gap to be filled in. The client matches
  -- on this wording to put its own copy down rather than beating for ever.
  --
  -- A tombstone has one job: outlive the phones still beating a night that was
  -- deleted. A phone closed or reopened once since is no longer a threat --
  -- Live.resume() puts its copy down on the way in. Permanent tombstones would
  -- slowly poison the code space instead, because goLive() rolls a random
  -- five-character code and one that had ever been deleted could never be
  -- issued again. Thirty days outlives any stale phone and keeps the pool whole.
  if exists (select 1 from public.session_tombs
              where code = p_code and killed_at > now() - interval '30 days') then
    raise exception 'session deleted';
  end if;

  -- Somebody else wrote between the copy this caller is holding and now.
  -- Raised rather than merged here: the server has no idea which court each
  -- of them was standing at, and the client does.
  if p_seen is not null and exists (
       select 1 from public.sessions s
        where s.code = p_code and s.updated_at > p_seen) then
    raise exception 'stale';
  end if;

  select pin into existing from public.session_keys where code = p_code;

  if existing is null then
    insert into public.session_keys (code, pin) values (p_code, p_pin);
  elsif existing <> p_pin then
    raise exception 'PIN does not match';
  end if;

  -- Only checked when the group is actually changing. A running session saves
  -- every few seconds, and re-checking each of those would lock out a co-host
  -- who has the PIN and is legitimately keeping the board up to date.
  select group_id into prior from public.sessions where code = p_code;
  if p_group is not null and p_group is distinct from prior
     and not public.sideout_may_organize_group(p_club, p_group) then
    raise exception 'not an organizer of that group';
  end if;

  insert into public.sessions (code, state, snapshot, club, listed, group_id, updated_at)
  values (p_code, p_state, p_snapshot, p_club, coalesce(p_listed, false), p_group, stamp)
  on conflict (code) do update
    set state = excluded.state, snapshot = excluded.snapshot,
        club = coalesce(excluded.club, public.sessions.club),
        listed = coalesce(p_listed, public.sessions.listed),
        group_id = coalesce(p_group, public.sessions.group_id),
        updated_at = stamp;

  return stamp;
end
$function$;

grant execute on function public.sideout_save(text,text,jsonb,jsonb,text,boolean,uuid,timestamptz)
  to anon, authenticated;
grant execute on function public.sideout_session_delete(text,text) to authenticated;


-- ===========================================================================
-- What is still on.
--
-- This was decided by one boolean on the snapshot, written by whichever phone
-- happened to be hosting. Bank a night from a device that then closes before
-- its last beat and the flag stays false for ever: the night sits at the top
-- of What's on with its own results showing under Already played a few
-- centimetres below. That is what MTFKY did.
--
-- The results own a night, not the session. Result rows for a code mean it was
-- played and banked, and no flag says otherwise -- that is the certain test and
-- it goes first. The second is for a night nobody ever banked: thirty-six hours
-- after it was due to start it is not on any more, which is all of the
-- following day for an organizer to get round to it, and the night is still
-- reachable by its card, its link and its code afterwards. A session with no
-- date at all is left alone; you cannot say a night is past when nobody has
-- said when it is.
-- ===========================================================================

create or replace function public.sideout_upcoming(p_club text)
returns table(code text, title text, starts_at timestamptz, ends_at timestamptz,
              venue text, repeat text, cap integer, joined integer, waiting integer,
              live boolean, ended boolean, mine boolean, cover text, group_id uuid)
language sql
stable security definer
set search_path to 'public'
as $function$
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
     -- "By link only" hides a session from the club, not from the
     -- people who run it. Staff see everything their club has on,
     -- because they are the ones who have to manage it.
     and (s.listed or exists (
           select 1 from public.members me
            where me.club = s.club and me.user_id = auth.uid()
              and me.role in ('owner','organizer')))
     and not coalesce((s.snapshot->>'ended')::boolean, false)
     -- banked is banked, whatever the flag says
     and not exists (
           select 1 from public.results r
            where r.code = s.code and r.club = s.club and r.removed_at is null)
     -- and a night that was due to start a day and a half ago is not on
     and coalesce(
           case when s.snapshot->>'startsAt' ~ '^[0-9]+$'
                then to_timestamp(((s.snapshot->>'startsAt')::bigint)/1000.0)
                     > now() - interval '36 hours' end,
           true)
   order by 3 nulls last, s.updated_at desc
   limit 40;
$function$;

grant execute on function public.sideout_upcoming(text) to anon, authenticated;


-- ===========================================================================
-- What is on the board, and who may join it.
--
-- sideout_upcoming gained three things, in this order of importance:
--
--   venue_name  The card only ever had the raw venue, which is a pasted Maps
--               link more often than not. parseVenue() can read a name out of
--               the long form but a shortened maps.app.goo.gl link has nothing
--               in it to read, so every card printed the words "Open in Maps"
--               where the place should be. The organizer already types the
--               name; it just never travelled.
--
--   closed      Invite only. Finding a night and getting on it are different
--               questions, and a season with fixed teams needs them apart: on
--               everybody's home page, and nobody can put themselves on it.
--
--   mine        Used to ask one question -- is there a join row for me -- which
--               is only true of people who tapped Join. An organizer who set
--               the night up and added themselves by hand never creates one,
--               so the app offered them Join for a night they were already
--               playing, with their own face in the stack underneath. Being on
--               the published roster is the same fact arrived at differently.
--
-- Dropped and recreated rather than replaced each time: create or replace
-- cannot change the columns of a returns-table function.
--
-- And sideout_join_now refuses a closed night, beside its checks for started,
-- ended and full. A lock drawn on a button is not a lock -- the link still
-- opens for anybody it was sent to.
--
--   if coalesce((s.snapshot->>'closed')::boolean, false) then
--     return 'closed';
--   end if;
--
-- See the live definitions for the full text; both are long and neither has
-- anything in it that is not explained above.
-- ===========================================================================


-- ═══════════════════════════════════════════════════════════════
-- sideout_open — an organizer opens a session without the PIN
-- ═══════════════════════════════════════════════════════════════
-- NOT DEPLOYED. Part of the pending migration.
--
-- The PIN is how a *device* proves it is allowed to write a session. That
-- was the right gate when a session could be started by anybody with a
-- phone, and it is the wrong one for an organizer of the club, whose role
-- already says it — they had to go and ask whoever started the night for
-- four digits before they could help run it.
--
-- So: an owner or organizer of the club gets the PIN handed to them for any
-- session of that club. Everybody else still has to type it. The PIN is not
-- removed or weakened; this is a second door into the same room, and it is
-- one the JWT opens.
--
-- Returns null rather than raising when the caller is not staff, so the
-- client can fall back to asking for the PIN without having to match on the
-- wording of an error.

drop function if exists public.sideout_open(text, text);

create function public.sideout_open(p_club text, p_code text)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select k.pin
    from public.session_keys k
    join public.sessions s on s.code = k.code
   where k.code = upper(btrim(p_code))
     and s.club = coalesce(p_club, 'sideout')
     and exists (
       select 1 from public.members me
        where me.club = coalesce(p_club, 'sideout')
          and me.user_id = auth.uid()
          and me.role in ('owner', 'organizer'));
$$;

grant execute on function public.sideout_open(text, text) to authenticated;
