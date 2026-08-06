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
Currently `sideout-v102`. Forgetting this means testers see last week's app and
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

**A format has to be registered in five places, and missing one half-works.**
`MODES`, `MODE_NAME`, the card on Setup (`id="mode-X"`), the switcher button on
Manage (`id="fmt-X"`), and a branch wherever the mode is dealt — `seed()`,
`nextRound()`, `nextLineups()`, `refreshPlan()` and `applyFormat()`. Court Wars
was added without `MODE_NAME`, so every screen showing the format printed the
word "undefined"; and without the Manage button, so it could be started but
never switched to mid-session. Anything in `SPECIAL_MODES` needs its own
seeding and round handling too.

**Nothing that goes into the snapshot may contain markup.** `courtTag()` is the
example: it is published as a court's tag and rendered as *text* by watchers
and by the big screen, so when the crown in it became an `<svg>` instead of an
emoji, all of them printed the tag literally. The snapshot is data. Icons
belong at the render sites that emit HTML.

**The clock only reaches watchers when something publishes it.** `Clock.start`,
`pause` and `reset` call `push()` for that reason. Do not push on the tick — a
watcher runs the seconds itself from the reading and the moment it was taken.

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

**Reminders are the exception to that**, because nobody does anything to
trigger them. `pg_cron` calls the `remind` Edge Function every ten minutes;
`sideout_reminders_due` returns what falls in the windows (20–28 hours out,
40–80 minutes out) and `sideout_reminder_claim` writes the row *before*
anything is sent — only the caller that won the insert sends, so a retry or
an overlapping run cannot double-send. Both are revoked from `anon` and
`authenticated`: the sender uses the service role.

**Push is sent by the device that did the thing**, not by a database trigger,
so there is no service credential sitting inside Postgres. The `push` Edge
Function checks the database that the join, leave or cancellation actually
happened before it sends anything, so a client cannot use it to send whatever
it likes. Its private signing key lives only in that function's secrets.

**An overloaded `sideout_*` function is a broken one.** PostgREST resolves an
RPC by the argument names it is given, and cannot choose between two functions
when the extra arguments of one default. `sideout_chat_send` gained a
five-argument form for replies and photos *beside* the old three-argument one,
and every client sending three got `300 Could not choose the best candidate
function` @EM@ which on an installed PWA is every phone on a stale cache, so chat
was silently dead for most of the club while working perfectly on a laptop.
`sideout_archive` had three overloads for the same reason. Replace, never add
beside; and if you must add, drop the old one in the same migration.

**A returned column name will shadow a table column inside the function.**
`sideout_chat_messages` returns a column called `member` and its
own body said `where message = m.id and member = v_me`. Postgres could not
tell the table's `member` from the function's OUT parameter and raised
"column reference member is ambiguous" on every call, for every message,
from the day reactions were added. Nothing in the app said so: the
conversation *list* comes from a different function and kept working, so
chats appeared and then opened empty. Qualify every column in a plpgsql
function that `returns table`, including the ones that are not ambiguous yet.

**When a client swallows an error it invents a second bug.** The one above
took months to find because `Chat.pull()` caught and returned, so an
unreadable conversation looked exactly like an unused one. Anything polling
on a timer has to be able to say that it failed.

**The results own a night, not the session.** `sessions` is the working copy
and gets deleted; `results` is the permanent record. Anything a night still
needs to be true of it after the session row is gone belongs on `results` @EM@
which is why `results.group_id` exists, stamped by `sideout_archive`. Both
group reads and `sideout_chat_may` key on it. They used to reach the group
through an INNER join on `sessions`, so deleting a session quietly took a
42-player night out of its club, off its club's table, and locked everyone
who played it out of the conversation about it.

**Equal games is not equal rest.** Every matchmaker ranks on games played,
and on a night bigger than the courts almost everyone is tied on that @EM@ 43
players across 4 courts is 16 seats, so the tie decides everything and it
used to fall to the shuffle. Simulated over 20 rounds that gave 14 players a
four-round sit-out and 34 of 43 a pair of back-to-back games. `P(id).sat`
counts rounds since a player last played and is the tie-break in
`planGauntlet` and `planMix`; the same 20 rounds then give every player a
longest sit of 2 and nobody two in a row, with games unchanged at 7-8. It is
maintained everywhere `streak` is. Court Wars solves the same problem its own
way in `Wars.order()`.

**Two story cards, four callers, one set of parts.** `drawLeaderCard()` (who
won) and `drawSessionCard()` (what the night was) are each fed by
`makeCard()` mid-session and by `Recap.card(kind)` for a night already
played. The ground, masthead, eyebrow, title, stat line and signature are
`cardGround`/`cardMasthead`/`cardEyebrow`/`cardTitle`/`cardStats`/
`cardSignature` and are shared — the two leaderboards drifted apart when they
were separate drawings, and the same night went out looking like two clubs
had run it. Anything added to one card belongs in the renderer or in the
shared parts, never in a caller. The header comes from the session's *group*
— `sideout_recap` returns `group`, `venue` and `meta` for exactly this — and
falls back to the club when a night is filed under none. `Recap.cardMenu()`
is the picker every share button goes through.

**A card may only say what the night recorded.** The session card drops a
tile, a stat or the whole next-session bar rather than print a figure it
had to invent. Two of those are load-bearing: the game log lives on the
*session* row, which a club can delete years after the results are banked,
so `games === 0` means unknown and is left out rather than printed; and a
night is dated from `meta.starts_at`, not from `played_at`, because a
session running past midnight banks on the Thursday and everyone there
calls it Wednesday's.

**A card is always dark; the app is not.** `cardPaint()` reads theme tokens off
the page, which is right for the club's accent and was wrong for gold: `--crown`
is `#E0A93A` on a dark screen and `#9E6C13` on a light one, so a card built in
daylight came out with brown medals on a navy ground. First place is not a
theme colour. It reads `METAL[0]` now. Anything else pulled off a token for the
canvas needs the same question asked of it.

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
