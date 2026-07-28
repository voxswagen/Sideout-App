# Sideout Society — project notes

Pickleball open-play session manager. Static site (Netlify, see `_redirects`),
Supabase backend. The whole app is one file: `index.html`, ~12,500 lines,
inline `<style>` and two inline `<script>` blocks. No build step, no bundler,
no framework. Edit the file directly.

`admin.html` is a separate billing page against the same Supabase project.

---

## Working against Supabase directly

The project is reachable through the Supabase MCP server, configured in
`.mcp.json` and scoped to this project ref alone. The token lives in a
`SUPABASE_ACCESS_TOKEN` user environment variable, not in the repo. It is not
read-only — DDL against production works — so read `list_tables` before
changing shape, and remember there is real club data behind it: 55 members and
the result rows the whole ladder is derived from.

The `supabase-*.sql` files are copies of what is deployed, not to-dos. Anything
applied to the database should be written back into one, so the repo and the
project do not quietly disagree.

---

## Conventions that are easy to get wrong

**Bump `CACHE` in `sw.js` on every deploy touching CSS or markup.** The
activate handler deletes any cache whose name isn't current, so a new name is
the only thing that actually forces installed phones onto the new build.
Currently `sideout-v23`. Forgetting this means testers see last week's app and
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

**`Club.rate()` writes absolute ratings, not deltas** — so a rating cannot be
worked backwards from the number it became. This used to make Reset
unrecoverable. It no longer is: `results.rating_before` holds each player's
pre-session rating, captured by `sideout_archive` because the client calls
`Club.archive()` *before* `Club.rate()`, so at that moment the stored rating
is still the old one. `sideout_unarchive` puts them back.

**`results` rows are put aside, not deleted.** Reset sets `removed_at` and
`sideout_restore` clears it. Everything derived from `results` therefore has
to filter `removed_at is null` — ladder, points, takings, past, recap and
the player record all do. Miss it in something new and a reset night stays
on the ladder while appearing to have been reset, which is worse than the
old hard delete.

**`joiners.kind` is not just join and leave.** There are `claim` rows too,
where somebody attaches an existing record to their account. Anything
reading that table needs an explicit kind filter — treating "not a leave"
as a join announced claims as new players arriving.

**`state.log` is stored newest first.** Each finished game is unshifted onto
the front, so reading it in order runs the night backwards — round 13 down to
round 1. Anything showing the night to a person has to sort it. `sideout_recap`
does this in SQL (round, then court, then as recorded) so the client never has
to think about it. Rounds are also not unique per court: a round can hold two
games on the same court, and one night legitimately has five games in round 1.

**`state` is not safe to hand out.** It carries the host `pin`, internal
ratings, the waiting list and the venue notes, and runs to most of a megabyte
once a cover photo is on it. Anything public reads a purpose-built RPC that
assembles only the fields it needs — see `sideout_recap`.

**Push on an iPhone needs the app on the Home Screen.** Apple only allows web
push from an installed PWA — a page open in Safari gets nothing, however the
subscription was made, and no amount of code changes that. So "notifications
do not work on my iPhone" is almost always "it has not been installed". The
toggle says so rather than failing silently. Android has no such rule.

**Push is sent by the device that did the thing**, not by a database trigger,
so there is no service credential sitting inside Postgres. The `push` Edge
Function checks the database that the join, leave or cancellation actually
happened before it sends anything, so a client cannot use it to send whatever
it likes. Its private signing key lives only in that function's secrets.

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
  derived from it on every read (`sideout_ladder`), so taking a night off the
  ladder is just stamping `removed_at` on its rows. Nothing is stored twice,
  and nothing is destroyed.

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
