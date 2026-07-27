# Sideout Society — project notes

Pickleball open-play session manager. Static site (Netlify, see `_redirects`),
Supabase backend. The whole app is one file: `index.html`, ~12,500 lines,
inline `<style>` and two inline `<script>` blocks. No build step, no bundler,
no framework. Edit the file directly.

`admin.html` is a separate billing page against the same Supabase project.

---

## Outstanding — do this first

**`sideout_unarchive` may not exist yet in Supabase.** The Reset button on
ended-session cards calls it and will fail until the SQL is run. The full
function is at the bottom of this file under "Pending SQL".

Its organizer guard is a *guess*. Before running it, open
`sideout_session_delete` in the SQL editor and copy that function's guard
verbatim into the marked block, so there is one definition of "may organize"
rather than two that can drift.

---

## Conventions that are easy to get wrong

**Bump `CACHE` in `sw.js` on every deploy touching CSS or markup.** The
activate handler deletes any cache whose name isn't current, so a new name is
the only thing that actually forces installed phones onto the new build.
Currently `sideout-v20`. Forgetting this means testers see last week's app and
report bugs that are already fixed.

**Comment voice.** Comments in this codebase explain *why*, in plain prose,
often several lines, frequently about a product decision rather than the
mechanics. They read as written by a person, not generated. Match it. Do not
add `// increment counter` noise.

**Copy voice.** UI strings are conversational British-ish English, lowercase
where it reads better, em-dashes, no exclamation marks, no "Oops!". Buttons
say what happens ("Take it offline", "Start fresh", "Keep playing"), not
"Confirm" / "Cancel".

---

## Traps found the hard way

**`go('setup')` is not "start a new session".** Setup is the editor for
whatever session is loaded in the global `S`. If a session is loaded,
`go('setup')` shows *that session's* form — it creates nothing. Anything
meaning "new session" must call `startOrganizing()`, which decides whether to
offer a clean sheet. This was wired wrong in two places (the feed's `+ New`
button and the drawer's "Organize an open play"); both now route through
`startOrganizing()`. Check any new entry point.

**`Club.rowsForArchive()` filters to `g > 0`.** The `results` table therefore
only ever holds people who actually got a game. Anyone who joined and never
got on court is not in it. Never treat `results` as the roster — read the
saved session state for that.

**`Club.rate()` writes absolute ratings, not deltas.** Internal ratings moved
by a session cannot be reversed, which is why the session Reset warns that
ratings are not put back. Making it reversible needs a schema change: store
each player's pre-session rating alongside the result row.

**`Live.adopt()` replaces `S` wholesale** via `Object.assign(blank(), state,
{live, liveCode, pin})`. Anything set on `S` before an adopt is lost. Set
after, not before.

**Putting down a hosted session** means stopping `Live.joinT` and clearing
`Live.code`, not just blanking `S`. `leaveSession()` does it properly;
`freshSession()` previously did not and left a poll running against a code no
longer loaded.

---

## Backend shape

Supabase, everything through `sideout_*` RPCs called via `Live.rpc()`. Two
tables matter:

- `sessions` — live state per `code`. Survives a session ending; `state.ended`
  just flips true. This is why an ended session can be reopened with its full
  roster intact.
- `results` — one row per player per session. The all-time club ladder is
  derived from it on every read (`sideout_ladder`), so removing a night from
  the ladder is just deleting its rows. Nothing is stored twice.

Organizer-only RPCs check the role from the JWT and raise on failure; the
client string-matches `/organizer/i` on the error to show the right message.

---

## Known cruft

`fallbackCopy()` and `legacyCopy()` do nearly the same job — the first toasts
on its own, the second returns a boolean. Two callers, one each. Worth
collapsing into one that returns a boolean, when nothing else is in flight.

`Feed.pastCard()` had an `<article>` closed by `</div>`; fixed, but worth a
scan for others.

---

## Requests

Pushback is welcome and wanted. If an approach here is wrong, say so rather
than implementing it. Corrections tend to be short and specific — apply them
narrowly rather than rewriting surrounding code.

---

## Pending SQL

Run once in the Supabase SQL editor. Replace the organizer guard first — see
"Outstanding" above.

```sql
-- ═══════════════════════════════════════════════════════════════
-- sideout_unarchive — take one night back off the club ladder
-- ═══════════════════════════════════════════════════════════════
-- The ladder is derived from `results` every time it is read, so
-- deleting the rows for one session code is the whole job. Nothing
-- else has to be recalculated.

create or replace function public.sideout_unarchive(
  p_club text,
  p_code text
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted integer;
begin
  if p_code is null or length(trim(p_code)) = 0 then
    raise exception 'A session code is required.';
  end if;

  -- ── organizer guard ──────────────────────────────────────────
  -- Replace this block with the same check sideout_session_delete
  -- uses. It is here so the function is never callable by an
  -- ordinary member holding the publishable key.
  if not exists (
    select 1
    from public.members m
    where m.club = p_club
      and m.user_id = auth.uid()
      and m.role in ('owner', 'organizer')
  ) then
    raise exception 'Only an owner or organizer of this club can reset a session.';
  end if;
  -- ─────────────────────────────────────────────────────────────

  delete from public.results r
   where r.club = p_club
     and r.code = p_code;

  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

revoke all on function public.sideout_unarchive(text, text) from public;
grant execute on function public.sideout_unarchive(text, text) to anon, authenticated;
```
