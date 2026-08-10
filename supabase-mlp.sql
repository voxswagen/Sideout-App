-- ===========================================================================
-- MLP team nights: keeping the teams after the session is gone.
--
-- What is deployed, mirrored back here so the repo and the project do not
-- quietly disagree.
--
-- Who won a team night lived on the session: state.teams, state.mlpPts and
-- state.mlpDone. The session row is the working copy and gets deleted, so the
-- moment a night was cleaned up the teams were gone -- while every player's
-- own games and wins carried on in `results` as if they had played a night
-- with no sides at all.
--
-- Same rule as results.group_id: anything a night still needs to be true of it
-- after the session row has gone belongs on the permanent side.
-- ===========================================================================

create table if not exists public.session_teams (
  club     text not null,
  code     text not null,
  team     text not null,
  name     text,
  players  jsonb not null default '[]'::jsonb,
  pts      int  not null default 0,
  wins     int  not null default 0,
  ties     int  not null default 0,
  pos      int,
  primary key (club, code, team)
);
create index if not exists session_teams_code on public.session_teams (club, code);

alter table public.session_teams enable row level security;
drop policy if exists session_teams_read on public.session_teams;
create policy session_teams_read on public.session_teams for select using (true);
grant select on public.session_teams to anon, authenticated;


-- Filled from the session's own state, the way session_facts is, so no client
-- passes anything new and there is no second argument to get wrong.
--
-- The players' names are stored beside their member ids on purpose: a team is
-- remembered by who was in it, and a member can be renamed, merged or removed
-- years after the night. The card should still say who played.
create or replace function public.sideout_teams_bank(p_club text, p_code text)
returns int
language plpgsql
security definer
set search_path to 'public'
as $$
declare c text := coalesce(p_club,'sideout'); n int := 0;
begin
  insert into public.session_teams (club, code, team, name, players, pts, wins, ties, pos)
  select c, p_code, t.id, t.name, t.players, t.pts, t.wins, t.ties,
         row_number() over (order by t.pts desc, t.wins desc, t.name)
    from (
      select tm->>'id' as id,
             tm->>'name' as name,
             (select coalesce(jsonb_agg(jsonb_build_object(
                       'm', pid,
                       'n', coalesce(s.state->'players'->pid->>'name', pid))), '[]'::jsonb)
                from jsonb_array_elements_text(
                       coalesce(tm->'m','[]'::jsonb) || coalesce(tm->'w','[]'::jsonb)) pid
               where pid is not null)                                    as players,
             coalesce((s.state->'mlpPts'->>(tm->>'id'))::int, 0)         as pts,
             (select count(*) from jsonb_array_elements(
                     coalesce(s.state->'mlpDone','[]'::jsonb)) d
               where (d->>'a' = tm->>'id' and (d->'won'->>0)::int > (d->'won'->>1)::int)
                  or (d->>'b' = tm->>'id' and (d->'won'->>1)::int > (d->'won'->>0)::int)) as wins,
             (select count(*) from jsonb_array_elements(
                     coalesce(s.state->'mlpDone','[]'::jsonb)) d
               where d->>'a' = tm->>'id' or d->>'b' = tm->>'id')         as ties
        from public.sessions s,
             lateral jsonb_array_elements(coalesce(s.state->'teams','[]'::jsonb)) tm
       where s.club = c and s.code = p_code
         and s.state->>'mode' = 'mlp'
    ) t
  on conflict (club, code, team) do nothing;
  get diagnostics n = row_count;
  return n;
end $$;

revoke all on function public.sideout_teams_bank(text,text) from anon, authenticated;


-- ---------------------------------------------------------------------------
-- Hooked into sideout_archive, at the end, beside the cover and the chat
-- recap:
--
--   begin perform public.sideout_teams_bank(p_club, p_code);
--   exception when others then null; end;
--
-- Wrapped like those two on purpose: a format that has no teams must never
-- stop a night being banked.
--
-- And sideout_recap gained a `teams` key, read from session_teams rather than
-- from the session's state, so a card shared a year later still names the side
-- that won it. See supabase-recap.sql for the whole function.
-- ---------------------------------------------------------------------------
