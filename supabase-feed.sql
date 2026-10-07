-- ═══════════════════════════════════════════════════════════════
-- sideout_posts — the club's feed
-- ═══════════════════════════════════════════════════════════════
-- Already live on the project, applied 7 October 2026. This file is the
-- deployed definition, like every other supabase-*.sql here — it spent a
-- while as the one file in this repo you could not trust, and it is not that
-- any more.
--
-- Verified against the project after applying: `posts`, `post_reactions` and
-- `post_comments` all answer 42501 "permission denied" to anon, which is the
-- shape wanted — present and closed, with every rule in the RPCs rather than
-- split between a policy and a function that could drift. All eight functions
-- resolve. `post_reactions` has no `id` column, which is correct: its key is
-- (post, member, kind).
--
-- One thing worth knowing and not changing by accident. Postgres grants
-- EXECUTE on a new function to PUBLIC, so `anon` can call these whatever the
-- explicit grant says — checked, and anon does get a 200 from
-- `sideout_posts`. It is harmless *because every function checks
-- `sideout_member_of()` itself* and returns nothing or raises when it is
-- null; the grant was never the thing holding the door. A future function
-- here that leans on the grant instead of making that check would be open to
-- the internet.
--
-- It exists because the handoff's Today is a feed people post to, and the
-- front page already advertises it ("results land in a feed the club
-- actually reads, people post, give kudos, and argue about it in the thread
-- until Thursday"). What is built is a feed of *sessions*. This is the gap.
--
-- Shape, and why:
--
--   A post belongs to a club, and optionally to a group and to a night. It
--   carries `code` as plain text rather than a foreign key to `sessions`,
--   for the reason written all over this repo: the results own a night, not
--   the session. A club can delete a session row years later and the post
--   about that night has to survive it, the same way `results.group_id`
--   does.
--
--   `kind` separates what a person wrote from what the app wrote. A banked
--   night posts its own write-up, and that post must not be editable or
--   deletable as though somebody had typed it.
--
--   Likes and kudos are one table with a `kind`, not two tables. They are
--   the same gesture with a different word on it, and a club that decides
--   it wants a third needs a row, not a migration.
--
--   Comments are flat. The design shows a count and a thread, not replies
--   to replies, and `chat_messages` already went through the pain of adding
--   reply threading after the fact — there is no reason to pay for it here
--   before anybody has asked.
--
-- Three traps this file is written around, all of them already paid for
-- once in this project:
--
--   * No overloads. PostgREST resolves an RPC by the argument names it is
--     given and cannot choose between two candidates when one's extras
--     default, so every function here is dropped before it is created and
--     there is exactly one of each. Adding a parameter later means
--     replacing the function, never adding beside it.
--
--   * Every column is qualified inside every plpgsql function that returns
--     a table, including the ones that are not ambiguous yet. A returned
--     column name shadows a table column of the same name, and that is what
--     made every chat open empty for months.
--
--   * Nothing here returns `state` or anything assembled from it. These are
--     purpose-built reads that name their own columns.

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
  -- An array of images, not one. A post about a night is three photographs
  -- and a line underneath, which is how anybody who has used a phone in the
  -- last decade expects to write one — and a single `photo text` would have
  -- meant either one picture or four posts.
  photos      jsonb,
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

-- `create table if not exists` adds no columns to a table that is already
-- there, so a project that ran an earlier version of this file would keep
-- the old shape and every insert naming `photos` or `card` would fail. These
-- are stated separately for that reason, and they are no-ops on a fresh
-- install. `photo` (singular) is left alone where it exists: nothing writes
-- it any more, and dropping a column is not worth the risk of doing it to
-- the wrong project.
alter table public.posts add column if not exists card   jsonb;
alter table public.posts add column if not exists photos jsonb;

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
returns table(id uuid, kind text, body text, photos jsonb, card jsonb, code text,
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
         p.photos,
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

-- Both signatures. An overloaded sideout_* function is a broken one —
-- PostgREST cannot choose between two candidates and answers 300 to every
-- caller — and a project that ran the earlier version of this file has the
-- text form of this function sitting there. Dropping only the shape we are
-- about to create would leave the old one beside it.
drop function if exists public.sideout_post_add(text, uuid, text, text, text);
drop function if exists public.sideout_post_add(text, uuid, text, text, jsonb);

create function public.sideout_post_add(p_club text, p_group uuid, p_code text,
                                        p_body text, p_photos jsonb)
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
  -- A picture on its own is a post, and so is a line on its own. Both empty
  -- is not.
  if coalesce(btrim(p_body), '') = ''
     and coalesce(jsonb_array_length(coalesce(p_photos, '[]'::jsonb)), 0) = 0 then
    raise exception 'nothing to post';
  end if;

  insert into public.posts (club, group_id, code, author, kind, body, photos)
  values (coalesce(p_club, 'sideout'), p_group, nullif(p_code, ''), v_me,
          'said', nullif(btrim(p_body), ''),
          case when coalesce(jsonb_array_length(coalesce(p_photos, '[]'::jsonb)), 0) = 0
               then null else p_photos end)
  -- unqualified on purpose: RETURNING names the target table, and a
  -- three-part name is not valid there. The v_ prefix on the variable
  -- is what keeps this unambiguous, which is the same discipline the
  -- chat functions had to learn.
  returning id into v_id;

  return v_id;
end;
$$;

grant execute on function public.sideout_post_add(text, uuid, text, text, jsonb)
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

drop function if exists public.sideout_post_night(text, text, uuid, text);
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
