-- ═══════════════════════════════════════════════════════════════
-- CHAT — conversations, and who may read them
-- ═══════════════════════════════════════════════════════════════
-- Already live on the project. This file is the deployed definition.
--
-- Three faults were found here on 6 August 2026, and between them chat had
-- been dark for most of the club for months. They are worth writing down
-- because none of them looked like what they were.
--
-- 1. `sideout_chat_send` existed TWICE — the original three-argument form and
--    a five-argument one added for replies and photos. PostgREST resolves an
--    RPC by the argument names it is given and cannot choose between two
--    functions when the extra arguments of one default, so a client sending
--    three got "300 Could not choose the best candidate function". The
--    current client sends five and worked; every phone still running a build
--    cached from before replies existed sent three and could not send at all.
--    On an installed PWA that is most phones. The old one is dropped below.
--    Replace an RPC, never add one beside it.
--
-- 2. `sideout_chat_messages` returns a column called `member`, and its own
--    body compared an unqualified `member` to the caller. Postgres could not
--    tell the table's column from the function's OUT parameter and raised
--    "column reference member is ambiguous" on EVERY call, for every message,
--    from the day reactions went in. The conversation list comes from a
--    different function and kept working, so chats appeared and then opened
--    empty. Every column in here is qualified now, including the ones that
--    are not ambiguous yet.
--
-- 3. The client caught the error and said nothing, so an unreadable
--    conversation looked exactly like an unused one. That is what made it
--    take months to find. Chat.pull() now surfaces it.
--
-- The other theme in this file: `sessions` is a working copy that gets
-- deleted, `results` is the permanent record. Anything a night still needs
-- to be true of it afterwards has to come from results.

-- ── who may read a conversation ────────────────────────────────────────
-- A DM is its two people. A session chat used to be worked out from the
-- sessions row — the joiners rows for that code, or the roster inside the
-- snapshot — and both die with the session. When it went, everyone who had
-- played that night lost the conversation about it. The results are the last
-- word: anyone banked into the night may read its chat.
create or replace function public.sideout_chat_may(p_chat uuid, p_me uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare c record; v_name text; v_role text;
begin
  select * into c from public.chats where id = p_chat;
  if not found or p_me is null then return false; end if;
  if c.kind = 'dm' then return p_me in (c.a, c.b); end if;

  -- You said something in here. Two people wrote in the run-up chat for OG
  -- Bardagulan and then could not open it again: that night was re-created
  -- under a new code before it was played, so the session they had been
  -- talking in was deleted, and neither of them got a game, so neither is in
  -- the results either. Every other route in runs through one or the other.
  -- Having written in a conversation is the one claim housekeeping cannot
  -- take away, and it lets nobody in who was not already there.
  if exists (select 1 from public.chat_messages x
              where x.chat = p_chat and x.member = p_me) then
    return true;
  end if;

  select coalesce(alias, name), role into v_name, v_role
    from public.members where id = p_me;
  if v_role in ('owner','organizer') then return true; end if;

  -- joined through the link
  if exists (
    select 1 from public.joiners j
     where j.code = c.code and j.kind = 'join'
       and (j.member = p_me or lower(j.name) = lower(v_name))) then
    return true;
  end if;

  -- or on the night's own roster, which is where anybody added at the door is
  if exists (
    select 1
      from public.sessions s,
           lateral jsonb_array_elements(coalesce(s.snapshot->'roster','[]'::jsonb)) r
     where s.code = c.code
       and (r->>'m' = p_me::text or lower(r->>'n') = lower(v_name))) then
    return true;
  end if;

  -- or banked into the night, which outlasts both of those
  return exists (
    select 1 from public.results r
     where r.code = c.code
       and r.removed_at is null
       and (r.member = p_me or lower(trim(r.name)) = lower(trim(v_name))));
end;
$$;

grant execute on function public.sideout_chat_may(uuid, uuid) to anon, authenticated;


-- ── the messages in one conversation ───────────────────────────────────
create or replace function public.sideout_chat_messages(
  p_club text, p_chat uuid, p_since timestamptz default null)
returns table(id uuid, member uuid, name text, photo text, body text, image text,
              created_at timestamptz, mine boolean, reply_to uuid,
              reply_name text, reply_body text, reactions jsonb, my_reaction text,
              kind text)
language plpgsql
security definer
set search_path = public
as $$
declare v_me uuid;
begin
  v_me := public.sideout_me(p_club);
  if not public.sideout_chat_may(p_chat, v_me) then raise exception 'not your conversation'; end if;
  return query
    select m.id, m.member, coalesce(mem.alias, mem.name), mem.photo, m.body, m.image,
           m.created_at, coalesce(m.member = v_me, false),
           m.reply_to,
           (select coalesce(rm.alias, rm.name) from public.chat_messages rp
              join public.members rm on rm.id = rp.member where rp.id = m.reply_to),
           (select case when rp.image is not null and coalesce(rp.body,'') = ''
                        then 'a photo' else left(rp.body, 90) end
              from public.chat_messages rp where rp.id = m.reply_to),
           coalesce((select jsonb_object_agg(e.emoji, e.n)
                       from (select rx.emoji, count(*)::int as n
                               from public.chat_reactions rx
                              where rx.message = m.id group by rx.emoji) e), '{}'::jsonb),
           (select rx2.emoji from public.chat_reactions rx2
             where rx2.message = m.id and rx2.member = v_me),
           m.kind
      -- LEFT, because picksilog has no members row and an inner join would
      -- silently drop every notice it has ever posted
      from public.chat_messages m
      left join public.members mem on mem.id = m.member
     where m.chat = p_chat
       and (p_since is null or m.created_at > p_since)
     order by m.created_at
     limit 300;
end;
$$;

grant execute on function public.sideout_chat_messages(text, uuid, timestamptz) to anon, authenticated;


-- ── a conversation may be named ────────────────────────────────────────
-- A session chat takes its name from the session, then from the banked
-- results. A night that was set up, chatted in, and then re-created under a
-- new code before it was played has neither: the conversation is real, the
-- messages in it are real, and nothing knows what it was called. So a chat
-- may carry a name of its own, used ahead of everything else. Nothing writes
-- it automatically; it is for exactly that case.
alter table public.chats add column if not exists title text;


-- ── the list of conversations ──────────────────────────────────────────
-- A session chat took its name from the sessions row and nothing else, so
-- once that row went the conversation was called "Open play" — the night it
-- belongs to, unnamed, for everybody who played it. The banked title is the
-- fallback.
--
-- A night that is over says so, because a list of conversations gives no
-- other clue which of them are finished and which are tonight. "Finished" is
-- the snapshot saying so, or the night having been banked at all — banking
-- is what ending does. A chat with neither a session nor any results is left
-- alone: nothing says it is over and nothing knows what it was called.
create or replace function public.sideout_chats(p_club text)
returns table(id uuid, kind text, code text, title text, photo text,
              last_body text, last_at timestamptz, unread integer, who uuid)
language plpgsql
security definer
set search_path = public
as $$
declare v_me uuid;
begin
  v_me := public.sideout_me(p_club);
  if v_me is null then return; end if;
  return query
    with mine as (
      select c.* from public.chats c
       where c.club = coalesce(p_club,'sideout')
         and (
           (c.kind = 'dm' and v_me in (c.a, c.b))
           or (c.kind = 'session' and exists (
                 select 1 from public.chat_messages x where x.chat = c.id)
               and public.sideout_chat_may(c.id, v_me))
         )
         -- cleared, and nothing said since
         and not exists (
           select 1 from public.chat_reads r
            where r.chat = c.id and r.member = v_me and r.hidden_at is not null
              and r.hidden_at >= coalesce((select max(x.created_at)
                    from public.chat_messages x where x.chat = c.id), c.created_at))
    )
    select m.id, m.kind, m.code,
           case when m.kind = 'dm'
                then (select coalesce(o.alias, o.name) from public.members o
                       where o.id = case when m.a = v_me then m.b else m.a end)
                else (
                  select case when coalesce(x.ended, false) or x.banked is not null
                              then '[FINISHED] ' else '' end
                      || coalesce(m.title, x.snap, x.banked, 'Open play')
                    from (select
                           (select nullif(s.snapshot->>'title','') from public.sessions s
                             where s.code = m.code and s.club = m.club) as snap,
                           (select coalesce((s.snapshot->>'ended')::boolean, false)
                              from public.sessions s
                             where s.code = m.code and s.club = m.club) as ended,
                           (select min(r.title) from public.results r
                             where r.code = m.code and r.club = m.club
                               and r.removed_at is null) as banked) x
                ) end,
           case when m.kind = 'dm'
                then (select o.photo from public.members o
                       where o.id = case when m.a = v_me then m.b else m.a end)
                -- the cover outlives the session too, in session_covers
                else coalesce(
                       (select nullif(s.snapshot->>'cover','') from public.sessions s
                         where s.code = m.code and s.club = m.club),
                       (select cv.cover from public.session_covers cv
                         where cv.code = m.code and cv.club = m.club)) end,
           (select x.body from public.chat_messages x where x.chat = m.id
             order by x.created_at desc limit 1),
           m.last_at,
           -- `is distinct from`, so a notice with no author counts
           (select count(*)::int from public.chat_messages x
             where x.chat = m.id and x.member is distinct from v_me
               and x.created_at > coalesce(
                     (select r.seen_at from public.chat_reads r
                       where r.chat = m.id and r.member = v_me), 'epoch'::timestamptz)),
           case when m.kind = 'dm'
                then case when m.a = v_me then m.b else m.a end else null end
      from mine m
     order by m.last_at desc
     limit 100;
end;
$$;

grant execute on function public.sideout_chats(text) to anon, authenticated;


-- ── the overload that broke sending ────────────────────────────────────
-- Applied 6 August 2026. Kept here so nobody adds it back.
drop function if exists public.sideout_chat_send(p_club text, p_chat uuid, p_body text);


-- ── picksilog says the night is done ───────────────────────────────────
-- Called from sideout_archive, wrapped there so a notice failing to post can
-- never fail an archive. It is the moment everyone in the conversation wants
-- and nothing was marking it: the talking simply stopped, and whether the
-- night had been written up was something you had to go and find out.
--
-- A message with no author needed two things the table did not have: a kind,
-- so the client can draw it as a notice rather than as somebody's bubble,
-- and a nullable member, because picksilog is not one.
alter table public.chat_messages add column if not exists kind text not null default 'said';
alter table public.chat_messages alter column member drop not null;

-- Creates the conversation if the night never had one, because the notice is
-- the point: it is how the people who played find out the results are up.
create or replace function public.sideout_chat_recap(p_club text, p_code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare c text := coalesce(p_club,'sideout'); v_chat uuid; v_players int; v_games int;
begin
  select count(*)::int, (coalesce(sum(r.games),0) / 4)::int
    into v_players, v_games
    from public.results r
   where r.club = c and r.code = p_code and r.removed_at is null;
  if coalesce(v_players,0) = 0 then return null; end if;

  select id into v_chat from public.chats
   where club = c and kind = 'session' and code = p_code;
  if v_chat is null then
    insert into public.chats(club, kind, code) values (c, 'session', p_code)
    returning id into v_chat;
  end if;

  -- banked twice is still one night
  if exists (select 1 from public.chat_messages
              where chat = v_chat and kind = 'recap') then
    return v_chat;
  end if;

  insert into public.chat_messages(chat, member, body, kind)
  values (v_chat, null,
          'That is the night done — ' || v_players || ' played, ' ||
          v_games || ' game' || case when v_games = 1 then '' else 's' end || '.',
          'recap');

  update public.chats set last_at = now() where id = v_chat;
  return v_chat;
end;
$$;

-- Nobody calls this from a phone; sideout_archive calls it for them.
revoke all on function public.sideout_chat_recap(text, text) from anon, authenticated;
