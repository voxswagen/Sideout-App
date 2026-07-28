-- ═══════════════════════════════════════════════════════════════
-- Session reminders — a day before, and an hour before
-- ═══════════════════════════════════════════════════════════════
-- Already live on the project. This file is the deployed definition.
--
-- Everything else that pushes is triggered by somebody doing something: a
-- join, a withdrawal, a session called off. A reminder fires when nobody
-- does anything, so it needs a schedule and a record of what has already
-- gone out — a cron running every ten minutes must not send six an hour.
--
-- The sending half is the `remind` Edge Function, deployed rather than run
-- as SQL. It has verify_jwt off, because a cron job has no user to be. That
-- is safe here: the function takes no arguments and can only do what the
-- schedule was already going to do. It reads what is due, claims each one,
-- and sends only what it actually claimed, so calling it repeatedly achieves
-- nothing.

create extension if not exists pg_net;

create table if not exists public.push_sent (
  code  text not null,
  kind  text not null,
  at    timestamptz not null default now(),
  primary key (code, kind)
);

alter table public.push_sent enable row level security;

-- ── what is due ──
-- Windows, rather than "less than 24 hours away" — otherwise every session
-- inside a day would qualify for the day-before reminder the moment it was
-- created. A session set up two hours before it starts simply misses the
-- earlier one, which is the right answer: there was never a day in which to
-- give a day's notice.
create or replace function public.sideout_reminders_due(p_club text default 'sideout')
returns table(code text, title text, starts_at timestamptz, kind text)
language sql
stable
security definer
set search_path = public
as $$
  with live as (
    select s.code,
           nullif(s.snapshot->>'title','') as title,
           case when s.snapshot->>'startsAt' ~ '^[0-9]+$'
                then to_timestamp(((s.snapshot->>'startsAt')::bigint)/1000.0) end as starts_at
      from public.sessions s
     where s.club = coalesce(p_club,'sideout')
       and not coalesce((s.snapshot->>'ended')::boolean, false)
       and not coalesce((s.snapshot->>'cancelled')::boolean, false)
  )
  select l.code, l.title, l.starts_at, k.kind
    from live l
    cross join lateral (values
      ('day',  interval '20 hours', interval '28 hours'),
      ('hour', interval '40 minutes', interval '80 minutes')
    ) as k(kind, lo, hi)
   where l.starts_at is not null
     and l.starts_at > now() + k.lo
     and l.starts_at < now() + k.hi
     and not exists (select 1 from public.push_sent p
                      where p.code = l.code and p.kind = k.kind);
$$;

-- ── claiming one ──
-- The row is written first and only the caller that actually wrote it sends
-- anything. Two overlapping runs cannot both win, so a reminder goes out
-- exactly once even if the schedule fires twice or a run is retried.
create or replace function public.sideout_reminder_claim(p_code text, p_kind text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare won boolean;
begin
  insert into public.push_sent (code, kind)
  values (p_code, p_kind)
  on conflict (code, kind) do nothing;
  get diagnostics won = row_count;
  return coalesce(won, false);
end $$;

-- Neither of these is for the client: the sender uses the service role.
revoke all on function public.sideout_reminders_due(text) from public, anon, authenticated;
revoke all on function public.sideout_reminder_claim(text, text) from public, anon, authenticated;

-- ── the schedule ──
-- Every ten minutes. The windows above are hours wide, so this is far more
-- often than strictly needed, which is the point: a missed run, a deploy or a
-- blip and the next one still catches it well inside the window. The claim
-- makes the extra runs free.
select cron.unschedule('sideout-reminders')
 where exists (select 1 from cron.job where jobname = 'sideout-reminders');

select cron.schedule(
  'sideout-reminders',
  '*/10 * * * *',
  $$
    select net.http_post(
      url     := 'https://nldagoxaqslqojbtwmca.functions.supabase.co/remind',
      headers := '{"Content-Type":"application/json"}'::jsonb,
      body    := '{}'::jsonb,
      timeout_milliseconds := 20000
    );
  $$
);
