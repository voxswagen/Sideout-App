-- ═══════════════════════════════════════════════════════════════
-- SIDEOUT — pending migration, 22 September 2026
-- ═══════════════════════════════════════════════════════════════
-- Paste into the Supabase SQL editor. Two parts, and they are independent:
-- run part one, check it, then run part two. If part two goes wrong, part
-- one has still landed and nothing is half-applied.
--
-- Neither part touches existing data. Part one replaces one read-only
-- function; part two only creates things that do not exist yet. Nothing
-- here drops a table, alters a column or deletes a row, so the blast
-- radius on 157 members and the results behind the ladder is nil.
--
-- Delete this file once both parts are applied — the repo's rule is that
-- supabase-*.sql files describe what IS deployed, and a migration script
-- left lying about is the thing that makes them stop being true.

-- ═══════════════════════════════════════════════════════════════
-- PART ONE — sideout_past gains a per-caller `place`
-- ═══════════════════════════════════════════════════════════════
-- Safe to run now: the client already handles the column being absent, and
-- handles it being present. Nothing changes for anyone until this runs, and
-- nothing breaks when it does.
--
-- What it adds: where *you* finished on each night, worked out with the
-- same arithmetic sideout_player already uses for `pos`, so the two cannot
-- disagree. Null for anon and for a night you were not on.
--
-- After running, the played cards on Today and on Sessions > Completed say
-- "you came 3rd", and a night with no cover photo shows the place in the
-- badge instead of a generic court glyph.

drop function if exists public.sideout_past(text);

create function public.sideout_past(p_club text)
returns table(code text, title text, played_at timestamptz,
              players integer, games integer, cover text, owing integer,
              place integer, won integer, mine_games integer)
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
         end,
         -- Where the caller finished that night, or null for a night they
         -- did not play. The same arithmetic sideout_player uses for `pos`,
         -- deliberately: two answers to "where did I come" that were worked
         -- out separately would eventually disagree, and the one on the card
         -- is the one people would screenshot. Ties share a place, so two
         -- people level on wins and difference are both second.
         -- The null guard is load-bearing. Without it a night the caller did
         -- not play has mine.wins null, every comparison below is null, the
         -- count is nought and the place comes back as first — the app would
         -- award anonymous visitors a win on every night in the club.
         case when mine.wins is null then null else
           (select count(*) + 1
              from public.results o
             where o.club = r.club and o.code = r.code and o.removed_at is null
               and (o.wins > mine.wins
                    or (o.wins = mine.wins
                        and (o.pf - o.pa) > (mine.pf - mine.pa))))
         end,
         -- and how the caller's own night went, for "4 of 6 won". Same
         -- lateral, so it costs nothing extra and cannot disagree with the
         -- place beside it.
         mine.wins,
         mine.games
    from public.results r
    -- the caller's own row on this night, if they were on it
    left join lateral (
      select r2.wins, r2.pf, r2.pa, r2.games
        from public.results r2
        join public.members me
          on me.club = r2.club and me.user_id = auth.uid()
       where r2.club = r.club and r2.code = r.code
         and r2.removed_at is null and r2.member = me.id
       limit 1) mine on true
    left join public.session_covers cv
      on cv.code = r.code and cv.club = r.club
    left join public.sessions s
      on s.code = r.code and s.club = r.club
   where r.club = coalesce(p_club, 'sideout')
     -- a night that was reset is put aside, not deleted; it must not show
     and r.removed_at is null
   group by r.code, r.club, mine.wins, mine.pf, mine.pa, mine.games
   order by 3 desc
   limit 60;
$$;

grant execute on function public.sideout_past(text) to anon, authenticated;


-- ═══════════════════════════════════════════════════════════════
-- PART TWO — the feed: posts, reactions, comments
-- ═══════════════════════════════════════════════════════════════
-- This one is NOT wired to anything yet. Running it creates three tables
-- and seven functions that no screen reads, which is deliberate — it lets
-- the schema be applied and inspected before any client code depends on
-- its shape. Nothing in the app changes when this runs.
--
-- Safe to re-run: every table is `create table if not exists` and every
-- function is dropped before it is created.
--
-- Shape and the reasoning behind it are in supabase-feed.sql, which stays
-- in the repo as the definition. Once this is applied, change that file's
-- header from "NOT DEPLOYED" to "Already live on the project", the way
-- every other file there reads.

-- ── tables ──────────────────────────────────────────────────────

create table if not exists public.posts (
  id          uuid primary key default gen_random_uuid(),
  club        text not null,
  group_id    uuid references public.groups(id) on delete set null,
  -- the night this is about, if any. Text, not a reference: the session row
  -- is the working copy and gets deleted; the post outlives it.
  code        text,
  author      uuid references public.members(id) on delete set null,
  -- 'said'   somebody wrote this
  -- 'night'  the app wrote it when a night was banked
  kind        text not null default 'said',
  body        text,
  photo       text,
  -- The attached card a system post carries: {kind,title,meta,gold,podium,
  -- action,code}. Structured rather than baked into the body, because the
  -- design draws a crown, a finished night with a podium and an open play
  -- with a Join button from the same shape, and a sentence cannot be drawn.
  -- Only ever written by the app; a person's post has none.
  card        jsonb,
  created_at  timestamptz not null default now(),
  edited_at   timestamptz,
  -- put aside, not deleted, the same way results rows are. Everything that
  -- reads this table filters it, and a club can change its mind.
  removed_at  timestamptz
);

create index if not exists posts_club_at on public.posts (club, created_at desc)
  where removed_at is null;
create index if not exists posts_code on public.posts (club, code)
  where removed_at is null;

create table if not exists public.post_reactions (
  post    uuid not null references public.posts(id) on delete cascade,
  member  uuid not null references public.members(id) on delete cascade,
  -- 'like' | 'kudos'. One of each per person per post, which is why the
  -- primary key carries the kind.
  kind    text not null default 'like',
  at      timestamptz not null default now(),
  primary key (post, member, kind)
);

create table if not exists public.post_comments (
  id          uuid primary key default gen_random_uuid(),
  post        uuid not null references public.posts(id) on delete cascade,
  member      uuid references public.members(id) on delete set null,
  body        text not null,
  created_at  timestamptz not null default now(),
  removed_at  timestamptz
);

create index if not exists post_comments_post on public.post_comments (post, created_at)
  where removed_at is null;

-- ── who may do what ─────────────────────────────────────────────
-- The feed is the club talking to itself, so reading it needs a member
-- record in that club — unlike the past feed, which anon can read because a
-- results table is a public record and a conversation is not.

alter table public.posts          enable row level security;
alter table public.post_reactions enable row level security;
alter table public.post_comments  enable row level security;

-- Everything below goes through the RPCs, which are security definer. The
-- tables themselves are closed: no policy is granted to anon or
-- authenticated, so a client cannot select from them directly and the rules
-- live in one place instead of two that can drift.

revoke all on public.posts          from anon, authenticated;
revoke all on public.post_reactions from anon, authenticated;
revoke all on public.post_comments  from anon, authenticated;

-- ── am I in this club ───────────────────────────────────────────
-- One definition, called by everything else. A function rather than a
-- repeated exists() so there is a single answer to "is this person in the
-- club", and changing it changes every caller at once.

drop function if exists public.sideout_member_of(text);

create function public.sideout_member_of(p_club text)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select m.id
    from public.members m
   where m.club = coalesce(p_club, 'sideout')
     and m.user_id = auth.uid()
   limit 1;
$$;

grant execute on function public.sideout_member_of(text) to authenticated;

-- ── reading the feed ────────────────────────────────────────────
-- A page at a time, newest first, keyed on created_at rather than an offset
-- so a post arriving while somebody is scrolling does not shift the page
-- under them and show them the same row twice.

drop function if exists public.sideout_posts(text, uuid, integer, timestamptz);

create function public.sideout_posts(p_club text, p_group uuid,
                                     p_limit integer, p_before timestamptz)
returns table(id uuid, kind text, body text, photo text, card jsonb, code text,
              group_id uuid, created_at timestamptz, edited_at timestamptz,
              author uuid, author_name text, author_photo text,
              likes integer, kudos integer, comments integer,
              i_liked boolean, i_kudosed boolean, mine boolean)
language sql
stable
security definer
set search_path = public
as $$
  with me as (select public.sideout_member_of(p_club) as id)
  select p.id,
         p.kind,
         p.body,
         p.photo,
         p.card,
         p.code,
         p.group_id,
         p.created_at,
         p.edited_at,
         p.author,
         coalesce(a.alias, a.name),
         a.photo,
         (select count(*) from public.post_reactions r
           where r.post = p.id and r.kind = 'like')::int,
         (select count(*) from public.post_reactions r
           where r.post = p.id and r.kind = 'kudos')::int,
         (select count(*) from public.post_comments c
           where c.post = p.id and c.removed_at is null)::int,
         exists (select 1 from public.post_reactions r
                  where r.post = p.id and r.kind = 'like'
                    and r.member = (select me.id from me)),
         exists (select 1 from public.post_reactions r
                  where r.post = p.id and r.kind = 'kudos'
                    and r.member = (select me.id from me)),
         -- only a post somebody typed is theirs to take down; the app's own
         -- write-up of a night is not anybody's to edit
         (p.author is not null and p.author = (select me.id from me)
          and p.kind = 'said')
    from public.posts p
    left join public.members a on a.id = p.author
   where p.club = coalesce(p_club, 'sideout')
     and p.removed_at is null
     and (p_group is null or p.group_id = p_group)
     and (p_before is null or p.created_at < p_before)
     -- the feed is for the club, not the internet
     and (select me.id from me) is not null
   order by p.created_at desc
   limit least(coalesce(p_limit, 30), 100);
$$;

grant execute on function public.sideout_posts(text, uuid, integer, timestamptz)
  to authenticated;

-- ── saying something ────────────────────────────────────────────

drop function if exists public.sideout_post_add(text, uuid, text, text, text);

create function public.sideout_post_add(p_club text, p_group uuid, p_code text,
                                        p_body text, p_photo text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid;
  v_id uuid;
begin
  v_me := public.sideout_member_of(p_club);
  if v_me is null then
    raise exception 'not a member of this club';
  end if;
  if coalesce(btrim(p_body), '') = '' and coalesce(p_photo, '') = '' then
    raise exception 'nothing to post';
  end if;

  insert into public.posts (club, group_id, code, author, kind, body, photo)
  values (coalesce(p_club, 'sideout'), p_group, nullif(p_code, ''), v_me,
          'said', nullif(btrim(p_body), ''), nullif(p_photo, ''))
  -- unqualified on purpose: RETURNING names the target table, and a
  -- three-part name is not valid there. The v_ prefix on the variable
  -- is what keeps this unambiguous, which is the same discipline the
  -- chat functions had to learn.
  returning id into v_id;

  return v_id;
end;
$$;

grant execute on function public.sideout_post_add(text, uuid, text, text, text)
  to authenticated;

-- ── a heart or a star ───────────────────────────────────────────
-- Idempotent on purpose. A double tap, a retried request and two phones
-- signed into the same account all have to end at the same place, and the
-- primary key does that work rather than the client counting.

drop function if exists public.sideout_post_react(text, uuid, text, boolean);

create function public.sideout_post_react(p_club text, p_post uuid,
                                          p_kind text, p_on boolean)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me   uuid;
  v_kind text;
  v_n    integer;
begin
  v_me := public.sideout_member_of(p_club);
  if v_me is null then
    raise exception 'not a member of this club';
  end if;

  v_kind := case when p_kind = 'kudos' then 'kudos' else 'like' end;

  -- The post has to be in the caller's club. Without this check a member of
  -- any club could react to any post in any other, because the id is the
  -- only thing the client sends.
  if not exists (select 1 from public.posts p
                  where p.id = p_post
                    and p.club = coalesce(p_club, 'sideout')
                    and p.removed_at is null) then
    raise exception 'no such post';
  end if;

  if coalesce(p_on, true) then
    insert into public.post_reactions (post, member, kind)
    values (p_post, v_me, v_kind)
    on conflict (post, member, kind) do nothing;
  else
    delete from public.post_reactions r
     where r.post = p_post and r.member = v_me and r.kind = v_kind;
  end if;

  select count(*)::int into v_n
    from public.post_reactions r
   where r.post = p_post and r.kind = v_kind;
  return v_n;
end;
$$;

grant execute on function public.sideout_post_react(text, uuid, text, boolean)
  to authenticated;

-- ── the thread ──────────────────────────────────────────────────

drop function if exists public.sideout_post_comments(text, uuid);

create function public.sideout_post_comments(p_club text, p_post uuid)
returns table(id uuid, body text, created_at timestamptz,
              member uuid, member_name text, member_photo text, mine boolean)
language sql
stable
security definer
set search_path = public
as $$
  with me as (select public.sideout_member_of(p_club) as id)
  select c.id,
         c.body,
         c.created_at,
         c.member,
         coalesce(a.alias, a.name),
         a.photo,
         (c.member is not null and c.member = (select me.id from me))
    from public.post_comments c
    join public.posts p on p.id = c.post
    left join public.members a on a.id = c.member
   where c.post = p_post
     and c.removed_at is null
     and p.club = coalesce(p_club, 'sideout')
     and p.removed_at is null
     and (select me.id from me) is not null
   order by c.created_at;
$$;

grant execute on function public.sideout_post_comments(text, uuid) to authenticated;


drop function if exists public.sideout_comment_add(text, uuid, text);

create function public.sideout_comment_add(p_club text, p_post uuid, p_body text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid;
  v_id uuid;
begin
  v_me := public.sideout_member_of(p_club);
  if v_me is null then
    raise exception 'not a member of this club';
  end if;
  if coalesce(btrim(p_body), '') = '' then
    raise exception 'nothing to say';
  end if;
  if not exists (select 1 from public.posts p
                  where p.id = p_post
                    and p.club = coalesce(p_club, 'sideout')
                    and p.removed_at is null) then
    raise exception 'no such post';
  end if;

  insert into public.post_comments (post, member, body)
  values (p_post, v_me, btrim(p_body))
  returning id into v_id;

  return v_id;
end;
$$;

grant execute on function public.sideout_comment_add(text, uuid, text) to authenticated;

-- ── taking something down ───────────────────────────────────────
-- Your own, or anybody's if you run the club. Stamped, not deleted.

drop function if exists public.sideout_post_remove(text, uuid);

create function public.sideout_post_remove(p_club text, p_post uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me    uuid;
  v_staff boolean;
begin
  v_me := public.sideout_member_of(p_club);
  if v_me is null then
    raise exception 'not a member of this club';
  end if;

  select (m.role in ('owner', 'organizer')) into v_staff
    from public.members m where m.id = v_me;

  update public.posts p
     set removed_at = now()
   where p.id = p_post
     and p.club = coalesce(p_club, 'sideout')
     and p.removed_at is null
     and (coalesce(v_staff, false) or (p.author = v_me and p.kind = 'said'));

  if not found then
    raise exception 'not yours to remove';
  end if;
  return true;
end;
$$;

grant execute on function public.sideout_post_remove(text, uuid) to authenticated;

-- ── the night writes its own ────────────────────────────────────
-- Called once, by whoever banks the night, right after sideout_archive. It
-- refuses to write a second one for the same code, so a phone that retries
-- — or two phones that both think they are hosting — cannot post the same
-- write-up twice. Same shape as sideout_reminder_claim: the insert is the
-- lock, not a check before it.

drop function if exists public.sideout_post_night(text, text, uuid, text, jsonb);

create function public.sideout_post_night(p_club text, p_code text,
                                          p_group uuid, p_body text, p_card jsonb)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if public.sideout_member_of(p_club) is null then
    raise exception 'not a member of this club';
  end if;

  insert into public.posts (club, group_id, code, author, kind, body, card)
  select coalesce(p_club, 'sideout'), p_group, p_code, null, 'night', p_body, p_card
   where not exists (
     select 1 from public.posts p
      where p.club = coalesce(p_club, 'sideout')
        and p.code = p_code
        and p.kind = 'night')
  returning id into v_id;

  -- null means somebody already posted it, which is a success, not a fault
  return v_id;
end;
$$;

grant execute on function public.sideout_post_night(text, text, uuid, text, jsonb)
  to authenticated;
