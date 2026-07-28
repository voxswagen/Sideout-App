-- ═══════════════════════════════════════════════════════════════
-- Web push — subscriptions, and who is allowed to register one
-- ═══════════════════════════════════════════════════════════════
-- Already live on the project. This file is the deployed definition.
--
-- The sending half is the `push` Edge Function, which is not in this file
-- because it is deployed rather than run as SQL. It reads VAPID_JWK from
-- its own secrets, verifies against this database that whatever it is being
-- asked to announce actually happened, and only then sends.
--
-- push_subs has row level security on and no policies at all. That is
-- deliberate: an endpoint is a capability, and anybody holding one can push
-- to that phone. Registering goes through the security-definer functions
-- below, and only the sender, using the service role, ever reads it.

create table if not exists public.push_subs (
  id          bigint generated always as identity primary key,
  club        text not null default 'sideout',
  member      uuid not null references public.members(id) on delete cascade,
  endpoint    text not null unique,
  p256dh      text not null,
  auth        text not null,
  created_at  timestamptz not null default now(),
  last_ok     timestamptz,
  fails       integer not null default 0
);

create index if not exists push_subs_member_idx on public.push_subs (club, member);

alter table public.push_subs enable row level security;

-- ── a phone registering itself ──
-- One row per browser per person: the same member on a phone and a laptop is
-- two rows, and both should ring.
create or replace function public.sideout_push_subscribe(
  p_club text, p_endpoint text, p_p256dh text, p_auth text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare c text := coalesce(p_club,'sideout'); me uuid;
begin
  if auth.uid() is null then raise exception 'sign in first'; end if;
  select id into me from public.members where club = c and user_id = auth.uid();
  if me is null then raise exception 'no member record for this account'; end if;
  if coalesce(p_endpoint,'') = '' or coalesce(p_p256dh,'') = '' or coalesce(p_auth,'') = '' then
    raise exception 'incomplete subscription';
  end if;

  -- The same endpoint coming back is the same browser, so it is updated
  -- rather than duplicated. It can change hands if a phone is passed on.
  insert into public.push_subs (club, member, endpoint, p256dh, auth)
  values (c, me, p_endpoint, p_p256dh, p_auth)
  on conflict (endpoint) do update
    set member = excluded.member, club = excluded.club,
        p256dh = excluded.p256dh, auth = excluded.auth,
        fails = 0, created_at = now();
  return true;
end $$;

-- ── and turning it off again ──
create or replace function public.sideout_push_unsubscribe(p_endpoint text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then return false; end if;
  delete from public.push_subs s
   using public.members m
   where s.endpoint = p_endpoint
     and m.id = s.member and m.user_id = auth.uid();
  return true;
end $$;

-- ── does this account have a phone registered? for the toggle's state ──
create or replace function public.sideout_push_state(p_club text)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::int
    from public.push_subs s
    join public.members m on m.id = s.member
   where s.club = coalesce(p_club,'sideout')
     and m.user_id = auth.uid();
$$;

revoke all on function public.sideout_push_subscribe(text, text, text, text) from public;
revoke all on function public.sideout_push_unsubscribe(text) from public;
grant execute on function public.sideout_push_subscribe(text, text, text, text) to authenticated;
grant execute on function public.sideout_push_unsubscribe(text) to authenticated;
grant execute on function public.sideout_push_state(text) to authenticated;
