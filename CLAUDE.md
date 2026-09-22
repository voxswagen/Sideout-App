# Sideout Society — project notes

Pickleball open-play session manager. Static site (Netlify, see `_redirects`),
Supabase backend. The whole app is one file: `index.html`, ~25,300 lines,
inline `<style>` and two inline `<script>` blocks. No build step, no bundler,
no framework. Edit the file directly.

`admin.html` is a separate billing page against the same Supabase project.

---

## Working against Supabase directly

The project is reachable through the Supabase MCP server, configured in
`.mcp.json` and scoped to this project ref alone. The token lives in a
`SUPABASE_ACCESS_TOKEN` user environment variable, not in the repo. It is not
read-only — DDL against production works — so read `list_tables` before
changing shape, and remember there is real club data behind it: 157 members
and the result rows the whole ladder is derived from.

The `supabase-*.sql` files are copies of what is deployed, not to-dos. Anything
applied to the database should be written back into one, so the repo and the
project do not quietly disagree.

Two exceptions, both marked at the top of the file itself and both waiting on
a project nobody could reach:

* `supabase-feed.sql` is a **proposal**, not a copy — the posts, reactions
  and comments the handoff's Today needs and the front page already
  advertises. The client now reads it, but only if it is there: see the
  feed's own note below.
* `supabase-past.sql` has gained a per-caller `place` on `sideout_past`
  that **has not been applied**. The client wires it defensively — every
  use is conditional and the card is exactly what it was when the column is
  missing — so deploying it turns the feature on and not deploying it costs
  nothing.

`.mcp.json` invoked the server through `cmd /c`, which is Windows and does
not exist on macOS, so the Supabase MCP server failed to start with
`ENOENT: cmd`. Fixed to call `npx` directly. It still needs
`SUPABASE_ACCESS_TOKEN` in the environment the server is spawned from.

---

## Conventions that are easy to get wrong

**Bump `CACHE` in `sw.js` on every deploy touching CSS or markup.** The
activate handler deletes any cache whose name isn't current, so a new name is
the only thing that actually forces installed phones onto the new build.
Currently `sideout-v136`. Forgetting this means testers see last week's app and
report bugs that are already fixed. Read the value out of `sw.js` rather than
trusting this line — it has been wrong by five versions before.

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

**The front page has no media queries and no fixed widths.** `clamp()` for
type, `repeat(auto-fit, minmax(min(100%, N), 1fr))` for every grid, 16px
gutters. A breakpoint is a guess about a screen size; this has none to get
wrong, and it was checked at 500px and 1100px.

**The front page is authored visible.** `LP.reveal()` hides the `[data-rv]`
elements a frame after mount and then reveals them on scroll — the markup
never starts blank, so if that script fails the page still reads its own
words. Same reason nothing there re-renders: `LP` writes straight to the DOM
through three loops, because a repaint would throw away the reveal styles
the observer has just written and flicker the board.

**The hero board runs the real rule.** First to eleven, win by two, then the
court resets and the round ticks — the same arithmetic `Score.legal()` uses.
A page that animated a fake score could drift from what the product does;
this one cannot.

**The old name is gone, including from the identifiers.** `picksilog()`,
`picksilogSrc()` and `picksilogURI()` are `sosMark()`, `sosMarkSrc()` and
`sosMarkURI()`; `manifest.json` said "picksilog" as both `name` and
`short_name`, which is what an installed phone puts under the icon on the
Home Screen. `grep -rn picksilog` across the repo is 0.

It survived that long because each check missed a different set.** Grepping the markup missed the two JS string literals
(`ab-title`'s fallback, `paintBrandBar()`'s subtitle). Then
`grep -c "'picksilog'"` returned 0 while the word was still in `<b>picksilog</b>`
in the app bar's static markup and in the chat recap note, in two
`navigator.share()` texts, in a theme swatch's `aria-label`, on the no-signal
screen, and in the watch page's footer. The check that actually settles it is
a runtime one — walk every screen and test `document.body.innerText` — because
the question is what a person sees, not what the source says. All nine are
Sideout Society now; the name survives only as the `picksilog()` /
`picksilogSrc()` / `picksilogURI()` function names and in comments.

**It used to be printed in two places, both string literals in JS.**
`ab-title`'s fallback for any screen without a `NAV_TITLE`, and
`paintBrandBar()`'s subtitle on Setup — which is to say it was on screen
every time anybody set a night up. Neither is caught by grepping the markup,
which is why this note claimed the surfaces were clean while the word was at
17px across the top of the app. `grep -c "'picksilog'"` is the check that
would have caught both, and it is 0 now.

**`picksilog` is gone from every surface a person can see** — the document
title, the install card, the install sheets, and the mark's own `aria-label`
and `<title>`, which is what a screen reader announces. The name survives
only in code: the `picksilog()` function that draws the old mark, the
`--brand-*` tokens, and comments. The front page, the app bar and the story
card all say Sideout Society. `grep -c picksilog` is the check.

**The card is previewed by the drawing that gets shared, not a copy of it.**
`Recap.card(kind, preview)` stops before `shareCanvas()` and hands
`#card-canvas` to the Share screen, which moves that same canvas into its
frame — a canvas takes a CSS size, so the preview is the real 1080×1920
bitmap at 302px wide. Snapshotting it into an `<img>` would be a second copy
that could disagree with the file going out. The canvas lives `hidden` the
rest of the time and is unhidden only inside the frame.

`Recap.cardMenu()` is still the picker every share button goes through, but
it opens that screen now instead of posting straight from the tap. The old
three-button sheet is kept as `cardMenuOld()` and has no caller.

**The card draws in the system stack.** It was Outfit for the headings and
Barlow Condensed for the small uppercase labels; `OUTFIT()` and the new
`CARD_LBL()` both resolve to `CARD_FONT` now, and `cardFonts()` no longer
preloads anything because there is nothing to load. The labels keep their
tracking through `track()` — that is what makes 22px uppercase read as a
label rather than as small text.

**The leaderboard card's podium was left alone.** The handoff draws "who won"
as three flat rows; what is there is a composed podium — first place centre
and tallest, second and third flanking lower, with a light of its own. It is
the artefact people actually post, and three rows would be a downgrade. The
type moved; the composition did not.

**A card printed "Games to undefined".** `sideout_recap` returns neither
`target` nor `mins` for a night whose session row has since been deleted, and
`cardTiles()` concatenated the target regardless. The sub-line is dropped
now, the same way the games tile is. This is the rule the notes already state
and it was being broken in a second place — check any figure a card prints
against a night whose session is gone.

**The card signed itself picksilog.** Of everything the rebrand had not
reached, this was the one people post. `cardSignature()` says Sideout
Society.

**A listing is a screen, not a sheet.** `Market.open(id)` puts the row on
`Market.at` and routes to `screen-listing`, which `Market.paintOne()` draws;
the full-size photos are still fetched for that one listing only, and it
repaints when they land. A sheet is the right shape for a decision and the
wrong one for a photograph, a description, a seller and an action. The
owner's "take this down", the seller's edit / mark sold / take down, and the
WhatsApp link all moved across — none of them was dropped.

**The shop says what it is not, in three places, on purpose.** No basket, no
total, no fee; the footnote on every listing states that the club takes no
payment and holds nothing. A grid of prices implies a shop that takes your
money, and this one does not — do not add anything that looks like a
checkout.

**The old shop CSS leaks two properties.** Its `.mk-pic` carries
`aspect-ratio:1/1`, which with the new stated height made the tint 118px
*wide* instead of full width, and `.mk-price` was Bebas Neue. Both are
answered in the new block rather than deleted, the same way the old board's
rules are. Watch for this shape whenever a redesigned screen keeps the old
class names: a rule you are not restating is still in force.

**New open play was built, registered, routed — and unreachable.** Nothing
in the app called `go('new')`. Every way of starting a night —
`startOrganizing()`, `freshSession()`, the two "carry on with what is there"
buttons — ended at `go('setup')`, so the redesigned compose screen existed
and the old panels were what everybody actually saw. All four route to
`'new'` now. The lesson is the one the `SCREENS` note makes from the other
direction: a screen can be correct in every particular and still never be
seen, and neither an error nor a sweep of the screens catches it, because
the screen is fine. What catches it is `grep -c "go('new')"` returning 0.

`screen-setup` is still there and still the editor for a loaded session —
`renderNew()` covers the compose case and titles itself "Edit this night"
when one is live, but Setup holds the roster panel, the online/sharing panel
and the round length, so it cannot be deleted yet.

**`go('new')` needs an early return, for the same reason `go('setup')` is a
trap.** After the organizer gate, `go()` rewrites any name to `'setup'` when
no session is running — and New open play is precisely the screen you want
when there is no session, so that rule would send you to the old editor every
time. It returns before the fall-through. Any future screen that is *for*
the no-session case needs the same.

**The compose screen and the old panels edit the same S.** New open play
writes through `setTitle`, `setDateOn`, `setStartTime`, `setEndTime`,
`setVenueName`, `setCap`, `setApprove`, `setClosed`, `setListed` and
`setMode` — the setters the `sp-*` panels already used — so there is one
definition of what each field means and the two screens cannot disagree.
Date and time are the native pickers on purpose. `setCourts(n)` is new
beside `bumpCourts(d)`: the row of picks needs a direct count, the old
stepper nudged by one.

**Do not repaint a form from `oninput`.** The first version of this screen
called `renderNew()` from the date and places handlers, which rebuilt the box
and took the field the cursor was in out from under it. Only the discrete
controls — courts, format, the toggles — repaint; the places note updates on
its own through `newCapNote()`.

**`S.fee` is new and needs no migration**, because it is on the session's own
state, which travels inside `sessions.state`. It is what lets the Session
screen's DETAILS show a court fee; that row was left out entirely before
rather than print a figure nothing recorded.

**`MODE_HINT` is now the only copy of the format descriptions.** The nine
Setup cards used to carry their own titles and descriptions inline, and the
two had already drifted — Setup said more about Up & Down the River and about
MLP than the map did. The map took the fuller wording and the cards became
`<span class="mode-tx" data-mode="x">`, filled by `paintModeCards()` at boot
from `MODE_NAME` and `MODE_HINT`. A format is described in one place now.

**The tab bar is five families, and `TAB_OF` is the map.** Each tab covers
a set of screens rather than one page, so the bar answers "where am I"
rather than "what did I last tap" — arriving by a link, the back button or a
redirect after signing in still lights the right one. A screen not in
`TAB_OF` falls through to Today, and `past`/`results` light whichever family
you came from. Adding a screen means adding it to `TAB_SCREENS` (does the bar
show at all) and to `TAB_OF` (which tab lights) as well as the three
registrations a screen already needs.

**Groups lost its tab and is reached from Profile.** The design's five tabs
are Today, Sessions, Standings, Shop and Profile — Groups is not one of
them, and it is still live: group ladders, group pages, and
`sideout_chat_may` keys on `group_id`. So `paintMe()` now always carries a
row to `go('groups')`. It only had one when you were in *no* groups, which
meant somebody already in a club could reach their own clubs and not the
list of the others. Do not take that row out.

**The ladder has no points column.** The handoff's leaderboard draws
`points` over `pts`; `sideout_ladder` returns nights, games, wins, pf and pa
and nothing called points. So the big figure is wins — which is what the
table is actually sorted on — with the points difference beside it. Adding a
"pts" nobody computes would be a number invented to fill a column.

**`sideout_player` has no session number and no "since".** The By session
rows want an S-number that never shifts; there is not one, so the label is
the night's own initials, which the handoff names as the fallback. "Since"
and "best finish" are worked out from the nights the RPC does return, by
`recExtras()`, and come back undefined on an empty list so the card drops
the line rather than printing a zero. The "of N" on Nights played uses
`Feed.past.length` when Today has already been looked at and is dropped
otherwise — a twelve-pip strip against a number nobody has is a picture of
a guess.

**The roster order is the call order, and it lives in `S.order`.** The
Players screen drags rows to rewrite it, and "By rating" and "A-Z" resort
that same list once — they are not a sort mode sitting on top of it, which
is the difference between a drag that sticks and a drag the next repaint
silently undoes. `S.rosterSort` is still the Manage roster's view mode and
is a different thing; do not wire one to the other.

**`renderPlayers()` repaints the new Players screen too.** `setLevel`,
`setSex`, `togglePaid` and `removePlayer` all call it to redraw the Manage
roster, and the same people are on two lists now. Calling `renderPeople()`
from inside `renderPlayers()` is why none of those four had to learn about
the second one — which is exactly how the pay pill ended up on two lists
with only one of them being redrawn.

**There are two Players screens as well.** `screen-people` is the design's
one; `screen-players` is Manage, which also holds the session settings and
the format switcher — one of the five places a format has to be registered —
so it cannot be deleted with the roster it happens to contain.

**Casting is a window handle, not a flag.** The design draws the cast sheet
as a list of devices — a Samsung on the network, an Apple TV, somebody's
iPad — and there is no cast API here, so that list would be things nobody
can tap. `BoardCast` offers the three real routes instead: the board on this
screen (`TV.open()`), the board at its own address in its own window
(`Live.tvUrl`), or that address copied for whoever is standing by the
television. "Casting" is then something that can be checked rather than
believed — `BoardCast.live()` asks the window whether it is `closed`, so the
banner cannot claim a board is up twenty minutes after somebody shut it. A
blocked pop-up is silent, so `away()` notices it failed and copies the link
instead of doing nothing.

**`go()` clears the cast sheet.** Its own Done button is not enough — the
flag is view state on `BoardCast` and it would survive onto the next screen.

**There are two screens for running a night and one of them is legacy.**
`screen-session` is the design's overview — read-only court cards, the
details list, and the two things you do about it. `screen-run` is the Score
screen, where the rallies are tapped. `screen-play` is the old combined one
(interactive `courtCard()`, the score pad, the pools and queue panels) and is
still wired to the Play tab; it has not been retired because `renderCourts()`
is load-bearing well beyond drawing — it also calls `refreshPlan()`,
`renderPools()`, `paintDock()` and `Auto.maybeStart()`, and writes to
`#courts` without a null guard. Retiring it means unpicking those side
effects first.

**Sessions > Upcoming is the club's schedule, and that is where "what's on"
lives now.** It used to filter to `r.mine`, and when Today stopped being a
list of sections there was no plain list of the club's nights anywhere — the
only place they appeared was as posts in the feed. The design settles it: the
date badge is "filled teal when you are going, grey otherwise", and a badge
needs two states only if the list holds nights you are *not* going to. So
Upcoming lists every night that has not ended, the badge lights when you are
in, and the tag says where you stand — Playing now, Going, Invite only, Full,
"6 left", Open, in that order, because being in it beats everything else the
night could say.

Completed stays personal: finishing place and "4 of 6 won" are per-viewer
figures, so that tab is the nights you played. Upcoming is what you could
join, Completed is what you did.

A night with no cap draws no fill bar. It used to draw a full one, and past
75% the bar goes amber to mean "about to close" — so a night with no limit
was wearing the colour for a night that is nearly full. The fill only means
something against a number to fill up to.

Both are personal now. `place` is the only per-viewer thing `sideout_past`
returns and it is non-null exactly when the caller has a results row, so it
doubles as "was I there" — but it is also the column that may not be
deployed, so `Games.knowsPlace` asks whether *any* row carries one. When
none does there is no way to tell, and the tab shows the club's nights under
a sub-line that says so rather than filtering everybody out or claiming
they are yours. Upcoming's empty state now explains what the tab is for and
offers a way to Today, instead of dead-ending.

**Today is the feed, and the order of it is load-bearing.** Banner,
composer, then posts. The handoff is explicit about why, and it is worth
keeping written down because the obvious arrangement is the wrong one: a
tall session card pushes the composer and the first post under the fold,
and the screen that is meant to be a feed reads as a screen with no feed on
it. `hmxPinned()` is therefore compact on purpose — it says one thing is on,
it does not describe the night, because the night has its own screen.

What's on and Already played are no longer sections here. An open play *is*
a post — `Posts.sessionRow()` draws one from `Feed.up` — and the full lists
live on the Sessions tab, which is what that tab is for. Deriving the
session posts client-side rather than waiting for rows means Today is a feed
on a project that has never run the feed migration.

`feedTimeline()` is the merge: real posts and the club's sessions, sorted by
time. A night that has been played only appears once `sideout_post_night`
has written one, because `sideout_past` does not return who won and a podium
cannot be invented.

`hmxNext()`, `hmxComing()`, `hmxPlayed()` and `hmxFigures()` have no caller
now. Left in place: deleting two hundred lines is its own change, and the
`#hm-fig` repaint they feed is null-guarded so it is a no-op rather than an
error. `hmTick()` is still live — the banner kept `id="hm-cd"`.

**Two reactions, two stated colours.** A like is "I saw this" and kudos is
"that was a real result", so they must not read as the same gesture twice.
`#B23D33` and `#8A6712`, written out rather than themed: the club's accent
would make them change colour from one club to the next, and a heart that is
teal in one club and orange in another is not a heart. The counts go in
words above the hairline ("31 liked · 28 gave kudos") and the bar underneath
is what you can do — which is why a post nobody has touched shows no counts
line rather than a row of noughts.

**`go('comments')` was the third screen caught by the `'setup'`
fall-through.** It has an early return with `chats` and `share` now. Any
screen anybody can reach — as opposed to one that only exists inside a
session — needs one, or `go()` rewrites its name to `'setup'` when no
session is running and a comment thread opens the old editor. That rule has
now caught `setup`, `new` and `comments`; assume it will catch the next one.

**Pull to refresh is a spacer, not a spinner.** `PTR` accumulates a distance
and the indicator's *height is that distance*, so the page moves with the
finger rather than something appearing over the top of it. 86px cap, 56px
threshold, arrow rotated `pull * 4`. It listens for wheel as well as touch,
because the same gesture on a trackpad is a wheel event and a feed that only
refreshes on a phone looks stuck on a desk.

**The chat avatar goes at the *end* of a run, the name at the start.** The
gutter is reserved by `.ch-m.noav:not(.me){padding-left:41px}` whenever the
face is not drawn — keyed on the face being absent, not on the message being
a run-on, or the last bubble of a run (the one that now carries the face)
would be the one that did not line up. The handoff flags the version that
removes the element with no reservation as a bug not to reintroduce.

**The feed renders as nothing at all when its schema is missing.** `Posts`
is the one part of the app whose backend may genuinely not exist — the
migration is written and a given project may not have run it — so
`Posts.load()` treats a **404 from PostgREST as "not installed", not as a
fault**: it sets `absent`, `hmxFeed()` returns an empty string, and Today is
byte for byte the screen it was before. Any other failure is a real failure
and says so with a retry, because the rule everywhere else applies here too
— a feed that cannot say it failed looks like a club with nothing to say.

That 404 is load-bearing and easy to break. PostgREST answers 404 for an RPC
it cannot find in its schema cache, which is exactly what a project without
the migration looks like, so `e.status === 404` is the whole test. Anything
that starts swallowing the status, or retries a 404 as though it were
transient, turns a missing feature into a broken screen.

`Posts.react()` is optimistic and then reconciles: the count moves on tap,
and the number `sideout_post_react` returns is the one that sticks, so two
phones tapping at once settle on the truth rather than on whichever repainted
last. It reverts on failure. Reactions repaint `#hm-feed` alone rather than
calling `paintHome()`, or every heart would throw away the page's scroll
position.

**The night posts its own write-up, and the insert is the lock.** `Posts.night()`
runs inside `Club.archive().then()` — after the results are actually banked,
never before — and is wrapped so it cannot cost anybody their ladder if it
throws. `sideout_post_night` refuses a second post for the same code in the
insert itself rather than checking first, the same shape as
`sideout_reminder_claim`, so a retry or two phones both thinking they are
hosting cannot post the night twice.

**The stacks screen overrides the planner; it does not replace it.**
`screen-stacks` is the laptop view of the queue — four stacks of four, a Free
row and the whole roster, all drag. `Stacks.call()` puts the top stack on the
first court that is free or already recorded, sends whoever was standing there
back to `S.queue`, shifts `S.stacks` up and calls `invalidatePlan()`. It does
not rewrite the plan: `nextRound()` still deals every other court. That is on
purpose — anything that quietly re-planned from a manual override would leave
the organizer unable to say which of the two was in charge.

Two halves of that swap are both load-bearing. The four who walk on have to
come *out* of `S.queue` or they are on court and queueing at once; whoever
they displaced has to go *back in* or a court's worth of people vanish from
the night. `Stacks.all()` re-cleans on every read, because a name that has
gone home, gone on court or been removed must not sit in a stack pretending
to be available — the stacks live on `S` so they survive a reload and travel
with the session, which means they can go stale between reads.

The layout is flex, not a grid of equal columns, for a reason worth keeping:
the two halves are not equal. `.stk-main` is `flex:20 1 470px` and
`.stk-side` `flex:1 1 318px`, so the stacks take everything going spare, the
roster settles near its natural width, and when a line can no longer hold
both each one wraps and fills — the phone layout with nothing having to
decide where a laptop stops. `.stk-cols` is `auto-fit` at 158px because the
stack count is not fixed (Add a stack makes a fifth), and 158 is the number
that gives four across on a laptop and a tidy two-by-two on a phone. 180 gave
three and a fourth underneath on a 1280 window, which reads as though the
fourth were a different kind of thing.

**A screen has to be in `SCREENS` or it silently never appears.**
`showOnly()` walks that array and puts `.on` on the one that matches, so a
section can exist, `go()` can route to it and its render function can fill
it, and the screen still never shows — nothing throws and nothing logs. The
Score screen did exactly that. `SESSION_SCREENS` is a second list (it decides
the running-a-session shell) and the session tab bar is a third, so a new
screen inside a session is three registrations, not one.

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

That was still true of the two lists the whole app reads from, in the worse
direction: `Feed.load()` and `Chat.load()` both caught and fell back to an
empty array, so a failed read did not hang — it came back as *good news*.
Home said "Nothing listed yet. Set one up and it will show here for all
clubs" and Sessions said "Nothing coming up that you are in", which on a
night the server is unreachable is the app telling all 157 members there is
no open play. Both now carry a `failed` flag set in the catch and cleared on
success, and `feedFailed()`/`feedRetry()` is the shared part the three call
sites use — Home's What's on, Sessions' Upcoming and Sessions' Completed —
with `Chat.again()` doing the same for Messages. The lists still fall back to
empty so nothing downstream has to cope with null; what changed is that the
screens can tell the two apart.

`feedRetry()` deliberately does not null the lists before refetching.
`load(true)` refetches regardless, and emptying them first would let Games'
own `Feed.up === null` branch start a second read of the same two RPCs; the
button says "Trying…" instead. Checked: one tap, two RPCs.

**Two headers, and one of them said picksilog.** The app bar was hidden only
on the screens that draw their own bar, so Today, Sessions, Record and Shop
got it *above* their own big title — two headers stacked, because that is
what it was. Worse, `ab-title` fell back to the literal string `'picksilog'`
for any screen without a `NAV_TITLE`, which was all four of them, so the old
brand name was printed at 17px across the top of the app. The rebrand note
below claimed that surface was clean; it was not, and `grep -c picksilog`
does not catch it because the word is a fallback in JS, not markup.

`syncNav()` now treats those four (and Messages) as `titled` and hides the
bar. Profile and a group's page keep it — there it is part of the coloured
band, not a strip above one — and so do the screens that use it for a title
and a way back. The bell and the chat were the only things living on that
bar, so they move into Today's own header; they are marked `.js-bell` and
`.js-chat` and the three painters address the class rather than an id,
because there are two of each now and only ever one on screen. `Notices.el()`
picks whichever is visible so the panel hangs off the bell that was tapped.

Anything given its own header from now on goes in that `titled` list, and
anything that keeps the bar wants a `NAV_TITLE` — without one it prints the
fallback, which is how this started.

**A template calls `icon()`; only static markup uses `data-ic`.** The comment
on `paintIcons()` says so and it is easy to miss: that painter runs once at
boot, so a `data-ic` span written by a render function is a permanently empty
box. Today's new bell and chat were drawn as two blank white discs until they
called `icon()` directly.

**`go()` rendered every session screen except `play`.** Its tail called
`renderSession`, `renderPeople`, `renderRun`, `renderStacks`,
`renderPlayers`, `renderStats` and `renderBracket` — and never
`renderCourts()`. So the Play tab showed whatever was last drawn into
`#courts`, which on a cold start is the "Nothing on court yet" empty state:
adopt or resume a live session, tap Play, and it said nothing was on court
while `S.active` was true and two courts had teams. Fixed by adding it to
that list. The worry was the side effects — `renderCourts()` also runs
`refreshPlan()`, `renderPools()`, `paintDock()` and `Auto.maybeStart()` — and
only the last has a life of its own: it returns unless every court is already
reported and it is not already running, which is a state the countdown
belongs in however you got there.

**`screen-play` cannot be retired yet, and the reason is the pools panel.**
`#pools-panel` and `#queue-panel` live inside it and nowhere else, and the
pools panel is the only place Court Wars and Up & Down the River show who is
in which pool. Retiring the screen without rebuilding that drops a feature
for two formats. The `renderCourts()` side effects are the other half of it.

**`go('chats')` used to be a screen name you could not navigate to.**
`Chat.paint()` drew "Reading your messages…" when `list` was null and
started no read; only `open()` and `dm()` load, and every route in the app
goes through one of them, so nothing hit it. The paint starts its own read
now, the way Games and Market do — a screen that is only correct because of
who happens to call it is waiting for the caller that eventually does.

**The results own a night, not the session.** `sessions` is the working copy
and gets deleted; `results` is the permanent record. Anything a night still
needs to be true of it after the session row is gone belongs on `results` @EM@
which is why `results.group_id` exists, stamped by `sideout_archive`. Both
group reads and `sideout_chat_may` key on it. They used to reach the group
through an INNER join on `sessions`, so deleting a session quietly took a
42-player night out of its club, off its club's table, and locked everyone
who played it out of the conversation about it.

**A latecomer has to be put on the queue, and `addPlayer()` is the only
place that should do it.** Five callers used to do it for themselves and
three of them forgot — including both add buttons on the Players screen — so
somebody added mid-session went onto `S.order` and nowhere else. In every
format but the two pool ones `waitingIds()` reads `S.queue`, so a name
missing from it is a person who is on the list all night: never shown as
waiting, never dealt onto a court, and gone from every count the session
draws. Simulated across the seven formats, **every late joiner was lost in
five of them** — gauntlet, mix, levels, kotc, mixed. River and Court Wars
were fine only because `poolsSync()` places people into tiers, and
`waitingIds()` reads the tiers there rather than the queue.

The insert lives in `addPlayer()` now, beside the `poolsSync()` call, guarded
so the pool formats still place their own. To the front, because a latecomer
has catching up to do, which is what the courtside add always did. One of the
three call sites that did it by hand had no `includes` guard, so leaving them
in place would have queued the same person twice.

Anything that adds a person to a running night goes through `addPlayer()`.
If a sixth way in ever appears, it inherits this rather than having to
remember it.

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

**The big screen has two callers and one set of parts.** `tvBoard(model)`
draws it; `TV.paint()` builds the model from `S` and `Cast.paint()` builds
the same model from the published snapshot at `?tv=CODE`. Neither writes a
card. They each had their own copy of the markup before and the two boards
drifted — the same mistake the story cards made. A playoff is the one
exception: `paintBracket()` draws its own cards, because a bracket match has
no score, no court tag and no state pill, and feeding the shared renderer a
model full of nulls to get three empty rows is a worse kind of sharing than
none.

**There are now two scores on a court and they are not the same thing.**
`c.pts` is `{a, b}`, the running score, written a rally at a time by
`Score.tap()` from the Score screen. `c.sc` is `{w, l}`, the banked result,
written by `Score.finish()` along with `c.win` — which is the same pair
`pickWinner()` has always written, so everything downstream of a finished
game is untouched. `c.lastPt` is the side that won the last rally and is the
whole of the undo model: one step back, which is why there is no minus
button beside a number.

A new game starts at love, so `c.pts` and `c.lastPt` are cleared in four
places — `Score.clear()` on each of the four whole-round rotations (the
shared planner, MLP, `climbRound`, `warsRound`) and inline in the rolling
single-court refill. The single-court one must NOT call `Score.clear()`: it
would wipe the live score off the three courts still playing.

`Score.legal()` is the one definition of a finishable game (first to
`S.target`, win by two) and both the Finish button and the "Game point"
caption are derived from it — the caption asks whether one more rally would
make it legal, rather than comparing against a threshold, because 11-10 is
not game point and 11-4 is already won.

The running score travels: `snapshot()` publishes `courts[].pts` and
`tvBoard()` shows the rallies while a game is on, the banked result once it
is over, and an em-dash only when there is genuinely nothing to show. Before
this the big screen showed two em-dashes through every rally.

**The big screen is a fixed 1920×1080 stage, scaled to fit.** `#tv-stage` is
authored at those exact pixels and `tvFit()` sets `--tvs` to
`min(vw/1920, vh/1080)`; a pixel in that block is a pixel of the design.
Reproducing thirty exact sizes in `vw` would be thirty chances to get one
wrong, and a television is 16:9 anyway. It is centred by `position:absolute`
and `translate(-50%,-50%)`, *not* by grid or flex centring: a box wider than
its container gets "safe" alignment, where centring silently becomes start so
nothing is clipped off the top or left — so the stage sat at x:0 and ran off
the right of every screen. Anything deliberately bigger than the viewport has
to be positioned, not aligned.

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

**The app bar carried the top safe-area inset for everything under it.**
Hiding it on the screens that title themselves took that away with it, and
Today, Sessions, Record, Shop, Messages, the profile and a group's page all
slid under the notch and the clock. Each of those now carries
`calc(6px + env(safe-area-inset-top,0px))` itself. Three of them —
`#screen-board.on`, `#screen-games.on`, `#screen-market.on` — restate their
padding further down the stylesheet and silently won it back, so the inset
had to go on those rules rather than only on the shared one. A new
self-titled screen needs adding in `syncNav`'s `titled` list **and** here.

**Birthdays are a feed post, derived, never stored.** `Birthday.soon(7)`
walks forward from this morning rather than filtering on the calendar month,
because a birthday on the 2nd of October is invisible from the 28th of
September to a month filter and the week before somebody's birthday crosses
a month boundary about a third of the time. `feedTimeline()` turns the result
into at most two entries — whoever it is today, and whoever it is inside the
week — so there is nothing to post, nothing to post twice and nothing to go
stale. Neither carries an actions bar: a heart on something the app worked
out this morning would have nowhere to be kept.

**Groups have been taken off every path into them except Club settings.**
The clubs list on the profile, "A group" in the Start something sheet, and
the Group row on New open play are all gone at the club's request — this is
one club, not a platform, and each of those asked "which of several" on a
screen where that is not a question. Nothing about groups was deleted:
`GroupPick.open()` still sets `S.groupId`, `Groups.edit(null)` still makes
one, the group page and its ladder still work, and `results.group_id` is
still stamped by `sideout_archive` when a night has one. **But a night set
up through the four stages now has no group**, so group tables will stop
gaining nights unless a group is set some other way. Worth knowing before
anybody wonders why a group's table stopped moving.

**A draft is `S` on this phone.** There is no drafts table and every setter
on the compose screen writes through immediately, so "Save draft" is really
"stop here". It says where to pick it up from, because the way back is the
`+` button and that is not obvious from a screen you have just left;
`startOrganizing()` finds the half-filled `S` and offers to carry on with it
or start fresh, and `NewFlow.start()` puts you on stage one with everything
still in the fields.

**The profile is five cards and nothing else.** Head, a four-up stat strip,
RATING, ACTIVITY, SETTINGS — plus ORGANIZING for the people who have those
tools, and Sign out. Everything that used to sit between them is either one
row or is reached from the row that names it: the rank card folded into the
rating card's bar and its one line ("23 points to Bronze"), the navy player
ID card became a row and a sheet that draws its QR when it opens, the details
table went behind Account, and the two session lists became "Sessions played"
and "Match history". A page about a person should be readable in one look and
the old one was five screens of scrolling.

The birthday strip and the code field have come off Today for the same
reason — the design has neither, and both were a second and third kind of
thing on a screen that is meant to be one kind. Joining by code is not lost
with the field: it is the third row of the `+` sheet.

**Nothing opens with a coloured band any more, and `.onhero` has nothing
left to do.** The profile and a group's page used to be `.screen.hero` —
full bleed, navy band, with `syncNav()` putting `.onhero` on `#appbar` so the
bar turned navy to match. The handoff removes the band from both, so both are
ordinary screens, the app bar is white everywhere, and `syncNav()` only ever
*removes* that class now. Its rules are still in the stylesheet with no
element carrying them.

Both draw their own head instead — a face or a logo, a name at 26px, a line
of context, then a hairline-divided stat strip (`.pf-strip`, four cells on a
person and three on a club). That sharing is the point and predates the
redesign: a club and a person are introduced the same way, and when the two
were drawn separately they drifted. Both are in the `titled` list now, so the
app bar steps aside for them as it does for every screen that titles itself.

`.pf-who h1` states `font-family:inherit`. `h1` in this file is the condensed
display face, which is right for a session brand bar and wrong for somebody's
name — it rendered "VOX DEQUINA" until it was stated.

**A two- or three-letter class name in this file is probably already taken.**
`.sw` is the club-colour swatch — a 34px white circle — so the day/night
toggle row written as `class="me-item sw"` drew itself as a full-width white
ellipse. `.top` is the session brand bar — a navy gradient with padding and
white type — so a leaderboard rank written as `class="rec-rk top"` drew the
first three places as filled navy boxes. `.sec` is the profile and group section wrapper, which carries a 22px
top margin, so the seconds on Home's countdown sat lower than the hours and
the minutes. Both looked like layout bugs and neither was. Grep the stylesheet
for the name before using it, and prefer a prefixed one (`me-tog`, `ticking`).

---

**What is still on was decided by a flag one phone writes.** `sideout_upcoming`
filtered on `not (snapshot->>'ended')::boolean` and nothing else, and that flag
is published by whichever device is hosting. Bank a night from a phone that
closes before its last beat and it stays false for ever, so a played night sat
at the top of What’s on with its own results under Already played a few
centimetres below. It now also refuses anything with rows in `results`, and
anything due to have started more than 36 hours ago. Same rule as everywhere
else: the results own a night, not the session.

**Deleting a session did not stick, and the door was `beat()`, not `resume()`.**
`sideout_save` ended in an upsert, so the next beat from any phone still
holding the night re-inserted the row — and re-inserted its `session_keys` row
from the PIN that phone was carrying, so even the key check passed.
`session_tombs` records a deleted code for 30 days and `sideout_save` raises
`session deleted` against it. Server-side on purpose: the phone doing the
resurrecting is usually one that will not see a new build for days.

---

## Known cruft

**24KB of dead CSS has been removed** — 197 rules that no longer had any
reader: the drawer (`.drawer`, `.dr-*`, `.burger`, `.scrim`, `.nav`), the old
auth screen, the old profile and group headers, the `.tier-head` group, Home's
two orphaned sets, the old landing page's `.lp-*`, the old TV board, and the
`.sx-*`/`.rq-*`/`.mu-*`/`.vw-*` blocks. The method matters more than the list:
each rule was kept only if **both** checks failed — no class attribute,
`classList` call or selector string anywhere outside the stylesheet mentions
it, *and* the bare name appears nowhere in the rest of the file at all. Then
the cut was made by character offset rather than by line, because rules share
lines (`.burger` and `.burger:hover` both sit on line 166) and deleting whole
lines would have taken half a rule with them. Every removed span was checked
brace-balanced on its own first, and the file went 2996 → 2798 braces on both
sides. The removed text is worth keeping out of git but was written to a file
before anything was deleted.

What the documented list got wrong, and what to watch for next time: several
names on it are live **ids**, not dead classes — `au-welcome`, `au-sub`,
`au-steps`, `hm-next`, `hm-cd`, `hm-fig`, `lp-nums`, `lp-live`, `lp-get` are
all `id="..."` on current markup while their `.class` rules are dead, so a
bare grep says "still used" and a class-aware check says "dead". And `.au-keep`
is a genuinely live class on a different screen. 29 rules were held back for
exactly these reasons and are still there.


`fallbackCopy()` is gone; `legacyCopy()` is the one copy helper and returns
whether it copied. The four callers of the other one now choose their own
words, which is the only thing the two disagreed about — "Link copied" is
wrong for an address and for a code.

`Feed.pastCard()` had an `<article>` closed by `</div>`; fixed, but worth a
scan for others.

The sign-in screen's redesign orphaned the old auth CSS: `.au`, `.au-head`,
`.au-ghost`, `.au-lock`, `.au-h`, `.au-p`, `.au-stats`, `.au-body`,
`.au-welcome`, `.au-sub`, `.au-steps`, `.au-bar`, `.au-keep`, `.au-forgot`,
`.au-swap`, `.au-back` and `.au-backstep` have no reader — the screen is
`.au2-*` now. Left in place deliberately: deleting ~160 lines of CSS is its
own change and easier to review on its own than folded into the redesign.
Note `#screen-auth.on` is still live and still wanted — it pins the screen to
the viewport — and `#screen-auth.au2.on` only overrides its background.

The old profile and group headers left CSS behind: `.ghead`, `.gh-pic`,
`.gh-tx`, `.gh-court`, `.gh-edit`, `.rank-card`, `.rank-big`, `.rank-txt`,
`.idcard`, `.id-n`, `.ms-row`/`.ms-n`/`.ms-w`, and the `.tier-head` group
(`.tier-who`, `.tier-mark`, `.tier-goal`, `.tier-badge`, `.tier-pts`,
`.tier-next`) have no reader now. `.tier-bar`, `.tier-gate` and `.tier-lock`
are still live, so the tier block cannot be deleted wholesale.

Home's rebuild orphaned another set: `.hm-top`, `.hm-me`, `.hm-tx`, `.hm-pair`,
`.hm-cnt`, `.hm-today`, `.hm-sess`, `.hm-shot`, `.hm-stx`, `.hm-when`,
`.hm-rt`, `.feed-new` and `.code-panel`. The functions that fed them
(`homeRatings`, `todayStrip`) are gone; the CSS is not. `.sx` and its children
are still live — `Feed.pastCard()` uses them.

Today's redesign orphaned the second Home set. `Feed.html()`, `Feed.row()`,
`Feed.viewBtn()` and `Feed.setDense()` have no caller — the screen is
`hmx*`/`.sos-*` now and the design picks the row, so the card-or-list toggle
went with them, and `.feed`, `.feed-h`, `.fd-chips` and `.fd-strip` went with
it. So did `.hm-greet`, `.hm-next` and its parts (`.hm-nh`, `.hm-cd`,
`.hm-cu`, `.hm-csep`, `.hm-nwhen`, `.hm-nwho`, `.hm-faces`, `.hm-more`,
`.hm-nct`, `.hm-nacts`, `.hm-nact`, `.hm-quiet`, `.hm-in`, `.hm-lock`),
`.hm-fig`/`.ps`, `.hm-sec`, `.hm-sh`, `.hm-sub`, `.hm-new`, `.hm-view`,
`.hm-code`, `.hm-done` and `.hm-res`.

Careful what looks orphaned here and is not: `Feed.card()` and `.sx2` are
still drawn by the setup preview and by Market; `Feed.rows()` and
`Feed.chips()` are called by the new Today; `.hm-clubs`/`.hm-club` are
`Feed.clubChips()`, which Today still uses; and `.chip` is Games'.

The big screen's redesign orphaned the old board's CSS. `.tv-top` and its
children, `.tv-bot`, `.tv-join svg`, `.tj-t`, `.tv-vs`, `.tv-next` and its
parts, `.tv-court .hd`/`.no`/`.tier`, `.tv-team.win`/`.tv-team i`,
`.tv-court.king` and the `@media (max-height:700px)` block that resized all
of it have no markup to match any more. They are left in place and they are
harmless — every rule the new board cares about is restated later in the
file, and later source order wins even against a media query — but a block
near the end of the TV section answers the handful of properties that are
only set up there (the Bebas font on the title, clock and team names, the
grid's padding, the join row's border). Deleting the dead rules is a change
of its own.

Do not try it with a script that removes text between two anchors. Doing
exactly that took 146KB of live CSS out of `index.html` in one command,
because an opening anchor matched earlier than intended and the closing one
matched much later. It was recoverable only because the whole stylesheet
could be rebuilt from `git show HEAD:index.html` plus the new blocks, which
happened to all sit at the end. Delete CSS by line range, having printed the
lines first.

---

## Requests

Pushback is welcome and wanted. If an approach here is wrong, say so rather
than implementing it. Corrections tend to be short and specific — apply them
narrowly rather than rewriting surrounding code.
