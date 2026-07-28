-- ═══════════════════════════════════════════════════════════════
-- sideout_notices — what has happened on the sessions you are in
-- ═══════════════════════════════════════════════════════════════
-- Already live on the project. This file is the deployed definition.
--
-- In-app only, and worth being honest about the limit: there is no push or
-- email channel yet, so this answers "what changed since I last looked" for
-- somebody who opens the app. It cannot reach anybody who does not. Getting
-- a message to a player who is not holding the app is a separate job.
--
-- Sessions are matched by account or by name, so the bell follows the
-- person rather than the device — the same rule the join list uses.
--
-- `joiners` also carries 'claim' rows, where somebody attaches an existing
-- record to their account. The first version mapped anything that was not a
-- 'leave' to "joined", so a claim was announced as a new player arriving.
-- Hence the explicit kind filter.

create or replace function public.sideout_notices(
  p_club text,
  p_since timestamptz default null
)
returns table(at timestamptz, code text, title text, kind text, who text)
language sql
stable
security definer
set search_path = public
as $$
  with me as (
    select m.id, coalesce(m.alias, m.name) as nm
      from public.members m
     where m.club = coalesce(p_club, 'sideout') and m.user_id = auth.uid()
     limit 1
  ),
  -- the sessions I am on the list for and have not since left
  mine as (
    select distinct j.code
      from public.joiners j cross join me
     where j.kind = 'join'
       and (j.member = me.id or lower(j.name) = lower(me.nm))
       and not exists (
         select 1 from public.joiners w
          where w.code = j.code and w.kind = 'leave'
            and (w.member = me.id or lower(w.name) = lower(me.nm)))
  ),
  since as (select coalesce(p_since, now() - interval '7 days') as t)

  -- other people coming and going, while the session is still on: a join
  -- notice for a night that already finished is noise
  select j.created_at,
         j.code,
         nullif(s.snapshot->>'title', ''),
         case when j.kind = 'leave' then 'left' else 'joined' end,
         j.name
    from public.joiners j
    join mine on mine.code = j.code
    join public.sessions s
      on s.code = j.code and s.club = coalesce(p_club, 'sideout')
    cross join me
    cross join since
   where j.kind in ('join', 'leave')
     and j.created_at > since.t
     and j.member is distinct from me.id
     and lower(j.name) <> lower(me.nm)
     and not coalesce((s.snapshot->>'ended')::boolean, false)

  union all

  -- a session being called off is the one thing worth knowing after it ends
  select s.updated_at,
         s.code,
         nullif(s.snapshot->>'title', ''),
         'cancelled',
         nullif(s.snapshot->>'cancelNote', '')
    from public.sessions s
    join mine on mine.code = s.code
    cross join since
   where coalesce((s.snapshot->>'cancelled')::boolean, false)
     and s.updated_at > since.t

   order by 1 desc
   limit 50;
$$;

grant execute on function public.sideout_notices(text, timestamptz) to anon, authenticated;
