-- ═══════════════════════════════════════════════════════════════════════
-- GROUPS — who may file a night under which club
-- ═══════════════════════════════════════════════════════════════════════
-- A copy of what is deployed, not a to-do. Applied 5 August 2026.
--
-- The hole this closes: sideout_save took a group id and wrote it without
-- asking whether the caller had anything to do with that group, and
-- sideout_session_group checked only the session's PIN. A session's results
-- land on its group's ladder, so anybody who could start a night could write
-- into any club's table on the platform. With one club that was invisible.
-- With several it is somebody else's record.

-- Owner or organizer *of that group*. A club owner is allowed too, because
-- they own the club the group belongs to and locking them out of their own
-- house helps nobody. A session with no group is nobody's to guard.
create or replace function public.sideout_may_organize_group(p_club text, p_group uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select case
    when p_group is null then true
    else exists (
      select 1
        from public.group_members gm
        join public.members me on me.id = gm.member
       where gm.group_id = p_group
         and me.club = coalesce(p_club, 'sideout')
         and me.user_id = auth.uid()
         and gm.role in ('owner', 'organizer'))
      or exists (
      select 1 from public.members me
       where me.club = coalesce(p_club, 'sideout')
         and me.user_id = auth.uid()
         and me.role = 'owner')
  end;
$$;

grant execute on function public.sideout_may_organize_group(text, uuid) to anon, authenticated;


create or replace function public.sideout_save(
  p_code text, p_pin text, p_state jsonb, p_snapshot jsonb,
  p_club text default null, p_listed boolean default null, p_group uuid default null)
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare existing text; stamp timestamptz := now(); prior uuid;
begin
  if p_code is null or char_length(p_code) < 4 then raise exception 'bad code'; end if;
  if p_pin  is null or char_length(p_pin)  < 4 then raise exception 'bad pin';  end if;

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
$$;


create or replace function public.sideout_session_group(p_code text, p_pin text, p_group uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare existing text; v_club text;
begin
  select pin into existing from public.session_keys where code = p_code;
  if existing is null or existing <> p_pin then raise exception 'PIN does not match'; end if;
  select club into v_club from public.sessions where code = p_code;
  if p_group is not null and not public.sideout_may_organize_group(v_club, p_group) then
    raise exception 'not an organizer of that group';
  end if;
  update public.sessions set group_id = p_group, updated_at = now() where code = p_code;
  return coalesce(p_group::text, 'none');
end
$$;

grant execute on function public.sideout_save(text,text,jsonb,jsonb,text,boolean,uuid) to anon, authenticated;
grant execute on function public.sideout_session_group(text,text,uuid) to anon, authenticated;


-- can_organize rides along so the client can offer only the groups a night
-- may actually be filed under, rather than letting somebody pick one and be
-- refused after they have chosen.
create or replace function public.sideout_groups(p_club text)
returns table(id uuid, name text, blurb text, photo text, home_court text,
              private boolean, theme jsonb, members bigint, sessions bigint,
              mine boolean, can_organize boolean)
language sql
security definer
set search_path = public
as $$
  with me as (select public.sideout_me(p_club) as mid)
  select g.id, g.name, g.blurb, g.photo, g.home_court, g.private, g.theme,
         (select count(*) from public.group_members x where x.group_id = g.id),
         (select count(*) from public.sessions s where s.group_id = g.id),
         exists(select 1 from public.group_members x, me
                 where x.group_id = g.id and me.mid is not null and x.member = me.mid),
         public.sideout_may_organize_group(p_club, g.id)
    from public.groups g
   where g.club = coalesce(p_club,'sideout')
   order by g.name;
$$;

grant execute on function public.sideout_groups(text) to anon, authenticated;


-- ═══════════════════════════════════════════════════════════════════════
-- Making somebody an organizer of a group.
-- ═══════════════════════════════════════════════════════════════════════
-- The check above went in without this, which left the rule enforced and no
-- way to grant it: whoever created a group was its only organizer for ever.
--
-- Only an owner of the group, or an owner of the club, may change roles. The
-- last owner of a group cannot demote themselves — a group nobody owns can
-- never be given an owner again.
create or replace function public.sideout_group_role(
  p_club text, p_group uuid, p_member uuid, p_role text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare v_me uuid; v_myrole text; v_clubrole text; v_owners int;
begin
  v_me := public.sideout_me(p_club);
  if v_me is null then raise exception 'sign in first'; end if;
  if p_role not in ('member','organizer','owner') then raise exception 'unknown role'; end if;

  select role into v_myrole from public.group_members
   where group_id = p_group and member = v_me;
  select role into v_clubrole from public.members where id = v_me;

  if coalesce(v_myrole,'') <> 'owner' and coalesce(v_clubrole,'') <> 'owner' then
    raise exception 'only an owner of this group can change roles';
  end if;

  select count(*) into v_owners from public.group_members
   where group_id = p_group and role = 'owner';
  if p_role <> 'owner' and v_owners = 1
     and exists (select 1 from public.group_members
                  where group_id = p_group and member = p_member and role = 'owner') then
    raise exception 'that is the only owner';
  end if;

  insert into public.group_members(group_id, member, role)
  values (p_group, p_member, p_role)
  on conflict (group_id, member) do update set role = excluded.role;
  return p_role;
end;
$$;

grant execute on function public.sideout_group_role(text,uuid,uuid,text) to authenticated;
