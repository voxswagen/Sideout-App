# Sideout Society — project notes

**This app does not run nights any more.** Sessions are set up and scored in a
separate manager app, and the two share the **same Supabase project**. This one
is the club's app: the Today feed, chat, accounts, the shop, the club's
sessions and the matchups — who is on which court, and the score as the manager
publishes it. All of it read-only about a night.

That shared database is the whole of why this matters. The dangerous part was
never the screens, it was `Live`: a hosting phone writes `sessions.state` every
few seconds and stamps `joiners` rows `taken`. Left running beside the manager
it would overwrite that app's scores on every beat and eat the join rows before
it ever saw them — silently, because nothing errors.

**`Live.HOSTS` is `false`, and it is the backstop rather than the mechanism.**
Every route into running a night is off (see `GONE_SCREENS`), and the flag is
checked inside `saveAll`, `collect`, `goLive`, `beat`, `finish`, `Club.archive`
and `Club.rate` so that a caller missed somewhere cannot still reach the
database. The cost of missing one is somebody's real night, not a broken
screen. **Do not set it true, and do not add a write to a `sideout_*` function
this app does not already call** — the rule is that this app writes only what
its own user did: joining or leaving a night, a post, a reaction, a comment, a
chat message, a listing, their own profile. Everything else it reads.

Nothing in `supabase-*.sql` changed and nothing should: the manager app depends
on those functions exactly as they are.

What is routed away, by `GONE_SCREENS` in `go()`: `new`, `setup`, `play`,
`run`, `stacks`, `players`, `stats`, `playoff`, `people`. A name lands on the
night if one is loaded and on Sessions if not. `SESSION_SCREENS` is `[]`, which
turns off the Score/Queue/Manage/Stats strip and the clock dock without
`syncDocks()` or `syncNav()` having to learn the feature is gone.
`startOrganizing()` and `openResume()` answer with `movedToManager()` rather
than being chased to a dozen call sites, and `manageSession()` redirects to the
watch view so a stale cache or an old notification still lands somewhere.

**A harness that stubs auth and calls `go()` is not a boot test, and mine
passed while the app was dead.** `.probe/harness.py` walks the screens by
calling `go()` directly with `Auth` stubbed — so it never ran the real boot
path, and reported twenty screens rendering and no errors while an actual cold
load was a blank page. `.probe/boot.py` is the other half: it loads the real
page over HTTP with nothing stubbed and reports the first uncaught error, the
screen that ended up `.on`, and how much text is on it. **Run both.** A blank
`bodyText` with a named screen is the signature of a top-level throw.

**Deleting markup breaks every painter that wrote into it, and one null stops
the whole script.** Nine screens going took `#courts`, `#roster`, `#ladder-preview`,
`#active-count`, `#lb`, `#bracket` and twenty more with them, and the painters
kept being called — from `load()`, from setters, from adopting a night.
Thirty-odd of those writes were unguarded. The ones at the *top level* are the
dangerous kind: `document.getElementById('brand-badge').src = BADGE` threw,
the script block stopped there, and every `const` below it — `Auth`, `Club`,
`Score` — never initialised. Function declarations still worked because they
hoist, which is what made it look like a scoping puzzle rather than a dead
script.

Every painter whose element has gone now returns at the top. Two rules came
out of it: **a painter is guarded on the element it needs, not on its
caller**, and **a function that takes an argument must not be guarded on its
fallback element** — `addPlayer(name)` reads `#new-name` only when no name is
handed in, and guarding it on that field made every programmatic add a silent
no-op, which is the latecomer bug for the fourth time.

**The session brand bar was on screen from the first paint, over everything.**
`<header class="top">` — back button, club badge, the format underneath, the
Live pill, the big-screen button — had **no `hidden` in its markup**, so it was
visible until something thought to take it away. `showOnly()` hid it for every
screen, but anything that landed before that ran, or never called it, left a
navy band saying "Sideout Society / Gauntlet" across the top of the app. All of
it was about running a night, so it is deleted rather than hidden.

**And deleting it took the whole app down, for a reason worth writing down.**
Three unguarded top-level statements —
`document.getElementById('brand-badge').src = BADGE` and two neighbours — ran
at the top level of the script block. `#brand-badge` was in that header, so one
of them threw `Cannot set properties of null`, the script stopped there, and
**every `const` below it never initialised**: `Auth`, `Club`, `Score`, the lot.
The app booted into a page with no app on it and the only clue was one
TypeError. Function declarations still worked, because they hoist, which is
what made it look like a scoping puzzle rather than a dead script.

They go through a guarded `setSrc()` now. Nothing in this file may assume an
element exists at parse time: the harness catches it because it reports a FATAL
when `Auth` is undefined, and that is the symptom to recognise — `typeof Live`
is `object` and `typeof Auth` is `undefined` means a top-level throw between
the two declarations, not a missing file.

**`gateScreens()` had an organizer branch, and it is what made the app look
like it had no front page.** Every launch, an organizer with a night still
loaded on the phone hit `else if(S.active) go('play')` — which now redirects —
so the app opened on a session rather than on Today. Its `inApp` list named
`setup`, `play`, `players`, `stats` and `playoff`, all five of them deleted
screens. There is no organizer branch now: signed out goes to the front door,
and everybody signed in carries on where they were or lands on Today. Checked
five ways, including an organizer with a live night.

**What has been deleted, and what is left.** 119KB came out in three measured
passes, each one verified by a harness that walks all twenty kept screens,
checks the nine redirect, runs the painters, and asserts that no write reaches
the shared project. It lives in `.probe/harness.py`; re-run it before and after
anything structural.

* **The nine screen sections** (615 lines) — cut by line range after printing,
  each span checked to begin on its own `<section id="screen-…">`, end on a
  `</section>` and balance on its own. The gaps between them hold *live*
  screens (comments, share, listing, session), so only the exact spans went.
* **62 top-level functions** (1081 lines), found mechanically rather than by
  eye: a function whose name appears exactly once in the whole file is
  referenced only by its own definition. Four rounds, because each round
  orphans more. `.probe/cut.py`.
* **374 CSS rules** (35KB) by the documented two-check method, parsed into
  rules and removed by span rather than by line. A rule goes only if *every*
  comma-separated part contains at least one dead class — one dead class in a
  part is enough, because `.dead .live` can never match either. Braces went
  3070 → 2696 on both sides.

**`renderAll()` was the casualty, and it is the hole these notes predicted.**
`renderCourts()` writes to `#courts` with no null guard and `#courts` lived in
`screen-play`. Of the nine painters it called, only `renderLive()` still has an
element. It now does that, `syncNav()` and `syncDocks()`, and asks for
`#tv-btn` rather than assuming it. Its sixty call sites were left alone on
purpose: it is called from settings, from a merge and from adopting a night,
and the honest fix is for the function to do only what is still real.

**What could not be deleted, and why.** `Score`, `Stacks`, `Spin`, `Auto`,
`MLP`, `Wars`, `Climb`, `Lineup`, `NewFlow`, `People`, `Tour`, `Draft`,
`Points` and `CourtView` are all inert — nothing routes to them — but none is
*unreachable* by static test: each is still named from live code or from each
other. `renderSession()` uses `Score.pts()` to draw the read-only court cards,
so `Score` is live — the landing's hero board was the other caller of it
(`Score.legal()`) and went with the page. Computing the closure (candidate set, minus anything
referenced outside it, repeat) left exactly one object that could go safely:
`AddGame`. Pulling the rest out means hand-editing live references for a
file-size win on code that already does nothing — worth doing deliberately, not
worth doing in the same pass as the removal.

---

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
Currently `sideout-v169`. Forgetting this means testers see last week's app and
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

**The `go()` fall-through has now caught four screens.** It rewrites any
name to the compose screen or the session overview when no session is
running, and every screen that is useful *before* a night exists has to
return before it: `setup` taught it first, then `new`, then `comments`, and
then **`people`** — which meant an organizer could not put anybody on the
list until they had already started playing, because the roster screen was
being rewritten to the overview. If a screen is reachable with an empty `S`,
it needs an early return. Assume the rule will catch the next one too.

**The compose screen is the editor, and it needed a door.** Retiring Setup
left it with no way in from the night it edits — the Session overview has an
**Edit** button now. It also keyed its own wording on `S.live`, so a session
running on this phone with no link was titled "New open play", which reads
as though everything typed is about to make a second one. Title, button and
footnote all key on there being a night at all (`S.live || S.active ||
S.order.length`), and only the footnote still distinguishes online from
running-here, because that is the one place the difference matters.

**`openSession()` is the one door into a night, and who you are decides
which side of it you get.** Every session card used to do
`location.href = '?s=CODE'`, which reloads the page into the watch view — a
read-only board built for somebody who followed a shared link. An organizer
then had to find "Manage this session" on it, which adopts the night and
lands them somewhere that looks nothing like where they just were. Four
steps and two different screens for the same session, and the person most
likely to tap it is the one running it.

Now: holding that night already means one tap to `screen-session`, nothing
fetched and nothing reloaded. An organizer who is not holding it goes
straight to `manageSession()`. Everybody else gets the watcher, which is
what it is for. Eight call sites went through it — Today's banner and
session posts, the Sessions cards, the feed rows, the attached card's
action and the landing page's list. A new session card wires to
`openSession(code)`, never to `?s=` directly.

**Setup is gone, and `go('setup')` is a redirect.** The old panelled editor
is no longer reachable: `go('setup')` sends you to the compose screen when
nothing is loaded and to the session overview when something is, and the
fall-through that used to rewrite *any* organizer screen to `'setup'` now
picks between those two. That rule is the one that caught `new` and
`comments`; it cannot catch a third thing now, because the screen it aimed
at does not answer.

Two things had to move first, and neither was optional:

* **`startSession()` was only reachable from a button on that screen.**
  Deleting it without moving that would have left a club able to set a night
  up and unable to start it. The Session overview carries it now — "Start the
  session" before, "Run the night" after, and the disabled form still says
  "Add 2 more to start" rather than vanishing.
* **`renderSession()` refused to draw anything unless `S.active || S.live`,**
  which is exactly the state a night is in between being composed and being
  started. It draws for any night with people on the list now.

And the group gate at the top of `startSession()` had to go: it *refused to
start* a night that was not filed under a group, which was defensible while
the compose screen asked and became a wall the moment that row came off,
because there was then no way to answer it.

The markup is still in the file and nothing routes to it. `sp-teams` (MLP's
team builder) is the one panel with no other home, so that is what to rebuild
before the `setup-page` blocks can be deleted.

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

**There is no marketing page. `/` is the front door.** Both designs in the
handoff claimed the same address — Landing v2 said it "replaces the home page"
and Home said it "is the app's front door" — and the landing lost: at a
one-club link nearly everybody arriving already knows what this is, and
putting a page in front of them that they have to click **Sign in** on is a
front door you have to open twice.

So `screen-landing` is deleted: 179 lines of markup, 308 of CSS, the `LP`
board driver, `lpDemo()` and `paintLandingFacts()`. `'landing'` is out of
`SCREENS` and out of `syncNav`'s lists. With no accounts configured there is
nothing to sign in to, so that case goes straight to the app rather than to a
page that no longer exists.

**The install card moved to the profile, and is better for it.** Its home was
the front page twice over, and both are gone — but an iPhone cannot be told a
session has gone up unless the app is on the Home Screen, so it needed
somewhere real rather than nowhere. It sits under SETTINGS beside
Notifications, which is the setting it exists to make possible, and it is a
signed-in member who needs it. `Install.paint()` still hides it once
installed, and `#lp-get` is still the id it looks for — the one piece of the
front page that outlived it.

`sos-logo-white.png` is still used, by the front door's header, and is still
in the service worker's `SHELL`.

**The front door is one screen, and the multi-step signup is gone.** The old
auth screen asked for eight things across three steps, which was the right
answer to eight fields. The handoff asks for five — name, gender, birthday,
email, password — and five fit on one screen, so `paintStep`, `go`, `back`,
`stepOk` and `focusStep` went with the wall they were solving. `data-mode` on
`#screen-auth` is the whole of the switch: the markup is static and the two
shapes are CSS, which is what lets the pill slide between the tabs instead of
the card being rebuilt under it. **It always opens on Sign in.**

Four things changed with it, and three are worth arguing about:

* **Birthday is a native date input, and only the month and the day are
  sent.** `members` has `birth_month` and `birth_day` and no year — that is a
  promise this app has made since it started asking, and the schema is shared
  with the manager app so it could not change anyway. The whole date is the
  easiest thing to type; the year is thrown away on submit.
* **Gender is now required to create an account.** It was optional before and
  said so ("Leave it blank if you would rather not say"). The handoff makes it
  required with the reason stated — "Pick a gender. It keeps mixed doubles
  fair" — and mixed doubles genuinely cannot balance without it. **Worth a
  second look: it is the one field here somebody might not want to answer,
  and the old copy existed because of that.**
* **Nickname and mobile are no longer asked at signup.** Neither was required
  and both live on the profile; the roster already falls back to `name` when
  there is no `alias`. Nothing reads a phone number that is never set.
* **"Keep me signed in" is gone.** `Auth.keep` is `true` by default, which is
  what the box was set to, so behaviour is unchanged — the screen just stops
  asking a question almost nobody wants put.

**The front door opened half way down itself, and `focus()` was the cause.**
`AuthUI.open()` focused the email field 80ms after showing the screen, and
focusing a field scrolls it into view. Stacked, the card sat under the whole
pitch — headline, court demo, queue notification — so the browser scrolled the
document 514 of its 1272 pixels and the app loaded with the pitch above the
viewport and nothing on screen saying what it was. Measured, not guessed:
`#screen-auth` reported `top=-514` at 500px wide.

Two things were wrong and they hid each other, which is why the page looked
like a layout bug rather than a focus one:

* `focus({preventScroll:true})` keeps the cursor and the view separate, and
  **narrow screens focus nothing at all** — the first thing a phone did with
  that focus was put a keyboard over a form nobody had read. `open()` also
  scrolls to 0 itself rather than trusting whatever it inherited.
* **Stacked, the card is first and the pitch reads underneath it.** Somebody
  at the door came to open it. This is the one place on the screen with a
  stated width rather than an `auto-fit`, and deliberately so: two rules have
  to agree on the same moment — when the columns stop being columns, and when
  the card stops being the second of them. Inferred separately they disagreed
  by about forty pixels, and on that band the grid had wrapped while the order
  had not.

The lesson generalises past this screen: **anything that calls `focus()` on an
element below the fold has moved the page**, and on a screen that is taller
than the viewport that is indistinguishable from the screen being drawn in the
wrong place.

**The Staff button is gone from the front door.** It signed you in here and
then toasted that running a night is in the manager app, which is a button
whose entire function is to explain that it is not the button you want — and
the manager app's address was never wired in, so it could not have been one.
`staffApp()` went with it, along with `.ah-staff` and the `.sp` spacer that
only existed to push it to the right of the bar. The bar is the wordmark now.
An organizer signs in through the same door as everybody else; what they can
do is decided by their role, which is where it was always decided.

**Apple and Google are drawn and not wired.** Tapping either says it is under
development, which is the honest version of a button that cannot work yet. The
marks are inline SVG rather than the official brand assets.

The old `.au2-*` rules have no reader now and are left in place, the same way
the `.au-*` set before them was: deleting ~140 lines of CSS is its own change
and easier to review on its own.

**The whole of the Landing v2 note has been cut, because the page it described
is deleted.** What survives of it is one asset and one rule:

* `sos-logo-white.png` — the tightly-cropped transparent wordmark (4425×627,
  ~7.06:1) the club finally supplied. It is the front door's header and it is
  in the service worker's `SHELL`, because a phone opening off the cache should
  not wait on the network to see whose app this is. The old untrimmed 5000×5000
  export needed a canvas-cropping window (`height = W × band-height,
  margin-top = -(W × band-start)`); that trick is dead and should not come back.
* **No figure on a page of this product may be invented.** The landing's
  counted facts came from `members`, `sideout_upcoming` and `sideout_groups`,
  and its "longest sit of 2, nobody back-to-back" figures were the output of
  the simulation these notes record. Sample *names* and sample *posts* read as
  flavour and are fine; a number does not.

The front door states its own palette (`--a-*` on `#screen-auth.ah`) for the
reason the landing did and the TV board still does: those tokens follow the
club's accent, and this page is the product's, not a club's.

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

**The Queue shows what the format has decided, except in Open play.**
`Stacks.manual()` is the switch. In Open play the stacks are `S.stacks` and
the organizer fills them; in every other format `Stacks.planned()` reads
`nextLineups()` — the one place that knows how each format deals — and shows
court 1's next four, court 2's next four, and so on. Four empty boxes in
Gauntlet asked somebody to do a job the app had already done, and read as a
broken screen rather than as a screen with nothing to say. A format with no
honest preview (River, Court Wars) returns nulls and gets an empty stack,
which is correct: those rebuild from standings nobody has tapped in yet.

**"That court is full" over a stack of three came from counting a different
list from the one on screen.** `Stacks.planned()` filtered out anybody
currently on court, so a court with four names pencilled in drew two of them
and two dashed "Empty" boxes, said 2/4, and then refused the drop as full
because `planMove()` counted the raw `S.next.courts`. Three separate halves of
that, all worth keeping written down:

* **Somebody mid-game is very often in the next round.** That is the whole of
  Gauntlet — the winners move up a court. `planned()` no longer hides them; the
  chip is dashed and says "on" instead of a games count, so 4/4 reads as "four
  down for this, two still out there" rather than as a half-empty court.
* **The count comes off `planned()`**, the list the screen draws, so the two
  cannot disagree again.
* **The screen draws from `nextLineups()` live; a change has to go into
  `S.next`,** which `refreshPlan()` may not have built yet — so a full plan
  could be on screen with nothing behind it and every drop was refused.
  `planMove()` calls `refreshPlan()` first.

**Showable and droppable are two different questions**, and conflating them
drew four Empty boxes over a court nothing could be dropped into.
`PLANLESS_MODES` is now the one list of the formats that keep no `S.next`
(`queue` is manual, and `kotc`, `river`, `wars`, `mlp` rebuild the next round
from results nobody has tapped in) — `refreshPlan()` and the Queue screen both
read it, so what the screen offers as a target and what the app is willing to
store cannot drift. King of the Court has an honest preview it will not honour
an override of, so its stacks show their names, carry no `data-drop` and are
never padded out to four. A column only pads to four if it takes a name.

**An empty seat takes a name, in every format that has one.** `move()` used
to refuse any drop in a planned format and offer the swap instead, which was
the app being inconsistent with itself: a swap already edits `S.next` and
sticks, so refusing the simpler thing — putting somebody into a seat the
planner left empty — said the plan was both editable and not. `Stacks.planMove()`
writes into `S.next.courts` for a drag *and* for a tap, onto the side with
fewer names, and refuses a fifth on a court rather than dropping one of the
four to make room.

It deliberately does **not** touch `S.queue`. In a planned format the plan is
pencil and `waitingIds()` reads the queue, so taking somebody out of it to
pencil them in makes them neither on court nor waiting — the latecomer bug
arrived at from a third direction, and the reachability check is what caught
it again.

River, Court Wars and King of the Court have no plan to edit, or only part of
one: `nextLineups()` returns nulls for a court it cannot honestly preview.
Those say so — a drop that is accepted and changes nothing reads as a name
being lost. `planLevels()` also stopped throwing on a `level` outside the
three bands; one unexpected value from the joiners table used to take the
whole Queue screen down for the night.

**A drag over a name is a drag, not a text selection.** Nothing carried
`user-select:none`, so the browser highlighted every name the finger swept
past and the gesture looked like it had picked up words instead of a player.
The chips, rows and empty slots state it, `body.dragging` covers the sweep
across everything else, and `moveTo()` clears whatever the press had already
selected before the eight-pixel threshold told us it was a drag.

**A name dropped on another name swaps them, in every format.** That is not
a move and does not go through `move()` — `Stacks.swap()` finds both spots
first and writes them together, because taking A out and then putting B in
changes what "out" means in between. Swapping inside the plan is allowed and
*sticks*, because `refreshPlan()` only rebuilds when the round number moves
on — so it survives exactly as long as it should. It therefore must **not**
call `invalidatePlan()`, which would throw away the plan holding the swap
that was just made in it; only a swap involving a court replans.

**The three lists overlap, and that is what made swapping inexact.**
Everybody waiting is in `S.queue`; a stack or a plan is a *selection from*
that pool plus whoever is still on court. So one person can be in three lists
at once, and the old `where()` resolved a name by searching them in a fixed
order with **courts first**. Three separate wrongs came out of that:

* A chip in the queue view for somebody mid-game resolved to their **live
  court seat**, so dragging two names in the queue changed who was playing —
  and then called `invalidatePlan()`, throwing away the swap as well.
* A view seat traded with a pool index put the displaced player into
  `S.queue` **a second time**, because they had never left it.
* In a planned format everybody waiting has a plan seat *and* is in the pool,
  so a roster row dropped onto a plan chip was read as a replacement and put
  that person in the plan twice.

The fix is that the drag says where each end came from. `Stacks.kindOfEl()`
reads `view` / `court` / `pool` off the element — a chip inside `.stk-col`,
a `.stk-row.locked`, anything else — `down()` records it and `up()` passes
both. Then `swap()` asks the questions in the order that matters: a `court`
hint is a substitution and the only case that touches a live game; both
holding a seat is an exact trade of the two seats and nothing else moves;
one holding a seat is the seat changing hands, with the loser left exactly
where they already were; neither is the call order in `S.queue`.

`viewOf(id)` is asked separately from `spotOf(id, kind)` for exactly that
third question. Checked across five formats and all five gestures: no
duplicate in any list, nobody unreachable, and the live courts unchanged by
anything that was not a substitution.

**The queue drags with a finger, on pointer events.** HTML5 drag-and-drop
is a mouse API and never fires from touch, so `Stacks.down/moveTo/up` is the
same gesture rebuilt: press, move past eight pixels, and a copy of the chip
follows the finger while `elementFromPoint` asks what is underneath and
whether it carries `data-drop`. A press that never passes the threshold is
a tap, which is why both gestures can live on one handler.

`touch-action:none` on the chips and rows is what makes it possible at all
— without it the browser claims the gesture for scrolling and the finger
moves the page instead of the name. The ghost is `pointer-events:none`, or
it becomes the thing under the cursor when we ask what is.

**There were two Undos and the second one was a round rollback in disguise.**
The Stats screen's Results panel carried "Undo last", which read as "undo that
last result" and was not: `undoLast()` restored `S.snap`, a JSON copy of the
whole session taken by `nextRound()`. So it worked once, only immediately
after a rotation, and said "Nothing to undo yet" every other time — and it
knew nothing about `S.next`, `S.stacks` or another organizer's writes, which
since co-hosting landed means it could throw away somebody else's rallies.

Gone, with the snapshot that fed it: a full stringify of the session every
round, travelling inside `sessions.state` on every save. `load()` deletes a
`snap` left on an older saved night rather than carrying it around for ever.
Nothing is lost that is not better covered — `Score.undo()` steps back a
rally, `Score.unfinish()` un-records a game, the swap arrow fixes a wrong
winner, and `removeAddedGame()` takes a hand-typed game back off and gives
the four players exactly what it gave them.

**"A round ends" is now the whole of the rule, and there used to be a second
switch quietly overruling it.** `rolling()` was `!S.timed && S.instant`, and
`S.instant` was a separate toggle — "Each court rotates on its own" — sitting
underneath, **defaulting to off on the Manage screen**. So choosing "when the
game's done" and then finding that finishing a court did nothing was the
normal experience of it: two controls for one decision, and the one people
found first was overruled by the one they did not. `rolling()` is
`S.active && !S.timed` now and both toggles are gone.

What each setting means is therefore what it says. **When the game's done**: a
finished court arms `Spin` and refills from the queue on its own, the other
courts carry on untouched and the round does not move. **On the clock**: no
countdown, nothing refills, and `nextRound()`'s `allReported()` gate holds
until every court is in.

**Two buttons on a court card said Undo and the one people tried was the dead
one.** `run-undo` steps back a rally, and `run-fin` reads "Undo" once a game is
recorded — so a recorded card carried a greyed-out Undo beside a live one.
The rally Undo is not drawn at all on a recorded card now, so whatever says
Undo is the one that works. A *playing* card with no rally yet still shows it
greyed, which is right: there is something to take back there, just not yet.

**The court card only carries what there is to do right now.** It used to
carry Type it, Undo and Finish game on every court in every state, and two of
the three were greyed out most of the time, three or four courts deep. A row
of dead controls is what makes a screen look complicated — the eye has to read
each one to find out it is not the one. Now: nothing but a line on a court
that cannot play yet, one quiet Undo on a court already recorded, two *icon*
corrections while a game is on, and Finish game at full width only once
`Score.legal()` is true. There is no disabled Finish, because a game that
cannot be recorded does not need a button saying so.

**And there have always been two scoring models, but the card only drew one.**
`Score.tap()` has always treated a night with `S.scores === false` as "tap
whoever won, tap again to take it back" — no counting, one tap, done. The card
drew the other model straight over the top: two nought-nought scoreboards,
"Tap to score", "First to 11, win by 2", a Finish button and a keypad, none of
which mean anything when nobody is counting. `counting` gates all of it now,
so a no-score night is two names and a line, and `Score.clearWin()` is its
Undo — `unfinish()` restores the rallies, which is right when there were
rallies and wrong when there were none.

**A switch names a feature; it does not say which state you are in.** "Record
the scores" lives on Manage, so the only way to know which of the two scoring
models a night was running was to tap a court and see what happened. The Score
screen states it now, under the round: *Winner only · no score kept* or
*Keeping score · first to 11*. It is a button to Manage, because "why has this
card no numbers on it" and "where do I change that" are the same question
asked twice. The switch's own sub-line says what is happening rather than what
the feature is, and both copies are written by `syncRoundEndUI()`.

**`renderAll()` never called `renderRun()`.** Same shape as `renderCourts()`
missing from `go()`'s tail: change a setting and the Score screen carried on
drawing the model it already had, because nothing told it to repaint.

**The rolling countdown was invisible on the Score screen, and that is what
"my recorded game was lost" actually was.** `Spin` gives a finished court four
seconds and then refills it, and its tick wrote the number into `nc-count-i` —
an element on the *old Play* cards. On the Score screen a game went Recorded
and then, with no warning, became a fresh one; on an eight-player night with
two courts it refills with the same four people re-paired, which looks exactly
like the result being thrown away. Nothing was ever lost — both games bank to
`S.log` — but the screen gave no reason to believe that.

The recorded footer now reads "Saved. This court goes again in 3s" and carries
**Hold** beside Undo. `Spin.hold(i)` cancels the countdown and the court keeps
its result until the round ends, which is what you want when four people are
still reading the score back. The tick writes `run-cd-i` as well, and redraws
when the number runs out because the footer changes shape rather than just its
digits.

**A score can be typed as well as tapped.** Tapping a rally at a time is
right at the net; it is wrong when somebody walks over and says "we won
11-7", which is one fact and eighteen taps. `Score.type()` writes the same
`c.pts`, so the tint, Game point, Finish game and the big screen read it
without knowing how it arrived — and it clears `c.lastPt`, because Undo is
one rally back and a typed score has no last rally to step back to.

**Manage opened on a wall of controls with no subject.** The first words on
it were "Session settings", with nothing saying whose settings — which on a
phone that has been in a pocket for twenty minutes is the first question. It
has a head now, the same shape the profile and a group's page use: a name, a
line of context (round, code, format) and a hairline-divided strip. A night is
introduced the way a person or a club is.

Three things it was getting wrong underneath:

* **"Courts in play" printed the number in the markup.** `live-courts-val` was
  only ever written by `renderCourts()`, so arriving at Manage without having
  drawn the courts showed the static `3` from the HTML. `renderPlayers()`
  writes it too.
* **The level and side chips did nothing to that list.** `playingRows()`
  called `sortedRoster(live)` and never `rosterShown()`, so the search worked
  — that lives in `sortedRoster` — and tapping "Adv" simply redrew all thirty
  names. It took folding the filters away to notice, which is the argument for
  folding them.
* **Four controls stood between the organizer and the list**: search, level
  chips, Everyone/Men/Women, and four sort buttons, above ten rows. The search
  stays out; the rest is behind a Filter button that carries a count, and it
  opens itself whenever something is narrowing — a hidden filter that is doing
  something is worse than a visible one that is not.

`noHits()` no longer blames a search nobody typed when a chip is what emptied
the list. And the "Your account" panel is hidden for anybody signed in: it is
a second place to sign in, under the roster of a night, on a screen only an
organizer reaches.

**Manage and Stats were the last screens in the old skin.** Navy brand bar,
Barlow Condensed in caps, bordered tiles, an amber box for a thing that is
not a fault. They are mapped onto `--sos-*` by a block scoped to the two
ids rather than rewritten — the same move the shop's old rules got. Two
things to know if you touch it: the standings rows are `.lb-row`, not
`.st-row` (`renderStats()` draws the same leaderboard part the old Play
screen used), and the amber note is `.conn.warn`, not `.warn-box`.

**HTML5 drag-and-drop does not exist on touch, and two screens were built
on it.** `dragstart` never fires from a finger, on any mobile browser, and
no markup changes that. The queue was a laptop screen and that was fine
while it was one; making it a tab in the session strip put it in front of
every phone running a night, where its only way of moving a name did
nothing at all. The Players screen had the same hole for reordering.

Tapping is the primary gesture on both now and dragging is the shortcut for
whoever has a mouse:

* **The queue** — tap somebody not in a stack and they join the first one
  with room; tap somebody in a stack and they come out. Which stack is
  stated rather than chosen, because "pick a stack, now pick a name" is a
  worse answer to a problem the order already solves.
* **Players** — the grip is a `<button>`. Tapping it sends that person to
  the top of `S.order`, which is the move somebody is nearly always making
  when they reach for a handle: *this one next*. Anything finer still needs
  a mouse, and saying so beats a handle that does nothing.

`cursor:grab` went with it. A grabbing hand promises a gesture a phone does
not have.

**Play and Score were the same tab twice.** Play was the old combined
screen — interactive court cards, a score pad, the pools and the queue — and
Score replaced everything on it except those last two. Two tabs showing the
same game is a choice nobody can make correctly. The session strip is
**Score / Queue / Manage / Stats** now; `go('play')` redirects to `'run'`,
and The queue — the half Score never took over — is a tab rather than a
button hidden on the run bar.

**`queue` ("Open play") is the mode where the organizer *is* the
matchmaker.** It deals nothing: `seed()` leaves the courts empty and puts
everybody in the queue in arrival order, `nextRound()` empties the courts
again rather than filling them, and `refreshPlan()` and `nextLineups()` both
decline — a "Next" row the app intends to deal and then does not is worse
than none. Registered in all five places, plus `applyFormat()`, which on a
switch mid-night leaves whoever is mid-game alone and hands the rest back to
the queue.

Its `nextRound()` has to push the players coming off court **back onto the
queue**. Emptying the courts without that leaves them on the roster and in
no list at all — not on court, not waiting — which is the latecomer bug
arrived at from the other direction, and the reachability check is what
catches it: every active id must be in `onCourtIds()` or `waitingIds()`.

**`stabs` is static markup, not a template literal.** A `${/* … */''}`
comment there renders as text across the top of the app, which is exactly
what it did. Use an HTML comment in anything outside a template string.

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
`MODES`, `MODE_NAME`, `MODE_HINT` (the compose screen's format list reads it;
the old Setup cards are gone), the switcher button on Manage
(`id="fmt-X"`), and a branch wherever the mode is dealt — `seed()`,
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

**The duplicates the app already made are in `members`, not in a session.**
Fixing `collect()` stops new ones; it does nothing about the rows already
banked. A night played with "Kuya Kevs" and "Kuya Kevs 2" on it archives
both, and `results` rows become member records — so the club roster carries
the duplicate for ever, with the games split across the two.

`clubSheet()` flagged duplicates by exact name, which is the one comparison
that could never find these: the suffix is what the app itself appended, so a
**trailing number is a signature, not a coincidence**. `dupeKey()` strips it
(and normalises case and spacing), the roster tags those rows "duplicate?",
and there is a "N possible duplicates — show me" filter that narrows to just
them. `memberSheet()` matches twins on the same key, so tapping one offers
the merge rather than making somebody find the other half by eye.

One false positive by design: a club with genuine "Player 2" and "Player 3"
rows sees them paired. Nothing merges without confirmation and the label
says *possible*, which is the right trade for catching the real ones.

**`sideout_member_merge`, `sideout_member_delete` and `sideout_member_add`
are live but written down nowhere.** No `supabase-*.sql` in this repo
defines them — they predate those files. The convention says those files are
a copy of what is deployed, and for these three it is not true. Worth
dumping them out of the project and writing them back the next time there is
a token.

**"Vox" and "Vox 2" came from one comparison hiding three cases.** A joiner
whose name is already on the list is not proof of a duplicate, and
`collect()` tested `clash && (!r.member || P(clash).mid === r.member)` — so
the one case it did not cover fell through to *add them again with a number
on the end*. That case is the common one: the organizer writes somebody on
at the door, and then that person joins through the link on their phone.
The row on the list has no `mid` yet, the joiner has one, the ids differ,
and the night now has them twice — two rows, two sets of games, and which
one the matchmaker deals is a coin toss.

Three cases, and only the last is a second person: same member id (already
here, skip); **no member id yet (the same human, now with an account behind
them — attach it to the row that is already there)**; a *different* member
id (genuinely two people, number the second). Proved against the previous
commit: written on then joining gave `["Vox Dequina","Vox Dequina 2"]`
before and `["Vox Dequina"]` with the account attached after, while two
genuinely different accounts still get numbered.

**The joiners batch had no order, and applying it backwards loses people.**
`takeJoiners()` selected with no `order`, so PostgREST returned rows however
the planner produced them — but a join and a leave for the same person are a
sequence, not two independent facts. Read backwards, leave-then-rejoin
becomes rejoin-then-leave: the join is skipped as already there and the
leave takes them off. And because `dropFromSession()` *deletes* anybody with
no games rather than marking them out, they are simply gone. Tapping the
wrong button and correcting it inside four seconds was enough.

Ordered by `id` in the query **and** sorted again in `collect()`, because the
order matters too much to depend on a query parameter being honoured and the
local mode never goes through PostgREST. By id rather than a timestamp:
`ackJoiners()` passes these ids to `in.(1,2,3)` unquoted, which only works
for integers, so the id is a serial and ordering by it is ordering by when it
happened — and asking for a column that does not exist would 400 and stop
joiners being collected at all, which is worse than the bug being fixed.

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

**Ending a night is not a court score, and the merge was treating it as one.**
`mergeInto()` replaces `S` wholesale with the server's copy and keeps only the
courts this phone touched more recently — which is right for rallies and wrong
for "this night is over". A host who ended a night in the same few seconds as a
co-host's beat had the end quietly undone and then written back as
`ended: false`: the session stayed on Sessions saying **Playing now**, and the
host had watched it say it was over.

`ended`, `endedAt`, `cancelled` and `cancelNote` are carried across the merge
the way `live`, `liveCode` and `pin` are, and `active:false` with them. Only in
one direction: a night *this* phone has not ended takes theirs, because the
other organizer may have ended it and that is news rather than a conflict.

`Live.finish()` also swallowed its save error — the rule this file keeps
relearning. It returns whether the write landed now, and clearing says so when
it did not, because otherwise the only person who knows the night is still
open is the one who just watched it close.

**Open play arrives with the queue already in the stacks.** The format hands
matchmaking to the organizer, and it used to hand it over as four empty boxes
and a roster — so the first thing anybody did with it was tap sixteen names
into the order they were already standing in. `Stacks.fill()` takes them off
the queue in arrival order, four at a time, and **only fills what is empty**,
which is what lets it run from `seed()`, from `applyFormat()` and from the
"Fill from the queue" button without ever rewriting an arrangement somebody
made. It is a starting point, not a plan: everything in it drags.

`applyFormat('queue')` also used to `return` before `setMode`, `closeSheet`,
the repaint, the save and the toast at the foot of that function — so switching
to Open play left the sheet open over a screen that had not changed.

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

**There were two top-level functions called `shrinkImage`.** The second
replaced the first at parse time, so `shrinkImage(file, 160)` — written for
the avatar cropper, which wanted a square — was calling the one that fits an
image inside a box, and faces came out letterboxed. The square one is
`cropSquare()` now. Both are live and they do different jobs; a file this
size will hide a duplicate declaration indefinitely, and nothing warns.

**A session is not owned by a device, and the app no longer behaves as
though it were.** Any organizer of the club can hold any of its nights —
that always worked — but a hosting phone polled only for **joiners** and
never for state, so it never learned what another organizer had recorded.
That is what made it feel device-bound: two people could both hold the
night, both write to it, and neither could see the other, so the second
one's next beat quietly overwrote the first's scores.

`Live.pullState()` runs on a 3s timer beside the joiners poll and adopts the
server's copy whenever it is strictly newer than `S.pulled`. `Live.dirty` is
the whole of the guard: set the moment anything schedules a beat, cleared
when that beat's save comes back **or fails** — cleared on the failure too,
or one missed save stops that phone ever pulling again. It also declines
while a sheet is open or a field has focus, because redrawing everything
under somebody mid-tap is its own bug.

**And a write that would overwrite somebody is refused and merged.**
`sideout_save` takes `p_seen`, the `updated_at` the caller last saw, and
raises `stale` if the row has moved on — which turns "your co-host's points
vanished" into an answer the client can act on. `Live.rebase()` reads what
they wrote and puts our own courts back on top of it.

The merge is per court, and `Score.touch()` is what makes it possible: every
courtside change stamps `c.touched`, so `mergeInto()` can take the server's
night and keep only the courts this phone touched more recently. Two
organizers scoring **different** courts therefore both keep their work; two
scoring the **same** court resolve to whoever touched it last, which is the
answer they would expect standing next to each other. Players added locally
are carried across as well — adding is additive and cannot conflict, and
losing a latecomer to a merge is the latecomer bug arrived at a third way.

A round that has moved on is not merged: advancing rewrites every court, and
half of round seven beside half of round eight is not a state anybody should
be handed, so the later round wins outright.

It rebases **once**. A second refusal means two phones are saving faster
than a round trip and looping on it would be worse than letting the later
one win.

`p_seen` defaults to null server-side and the client stops sending it after
one 404, so a project that has not run the migration behaves exactly as
before — which is what keeps every phone on a stale cache working the day it
lands. Simulated both ways: with the check, two organizers on different
courts both survive one refusal and one rebase; without it, one probe and
then it never asks again.

A phone still shows one night at a time, because `S` is a single global and
the whole app is one session. That is real and the sheet says so plainly
now; what it used to say was "leave the session you are running", which
implied a lock this app has never had.

**Fixing the architecture did not fix the words, and five strings were still
telling the old story.** The sheet an organizer actually hits said setting
another night up "puts tonight down on **this phone**", which reads as a
teardown — and nothing happens to the night at all. It is on the server, any
organizer can open it, and the phone was only ever the one looking at it. The
sheet is about the *screen* now: "Sideout shows one night at a time, so a new
one takes its place on screen." The others were `manageSession()`'s "You are
running this session **from this device**", the second sheet's "**This device**
is set up on…", and the two PIN captions, one of which said the PIN "moves the
session to another device" — it moves nothing; it lets somebody who is not an
organizer help run the night, which is the only thing it has ever been for.
Both sheets also still pointed at "What's on" and "its card on Home", neither
of which exists since Today became a feed; the nights are on Sessions.

The lesson is worth the space: a change of model leaves its old story lying
around in copy, and copy is the only part of it anybody reads. `grep -n "this
phone\|this device"` is the sweep — most hits are correct (a draft, keep me
signed in, local mode, the theme) because those things genuinely are local.
The test is whether the sentence claims the device holds the *session*.

`sideout_open` is the part that could be done: an owner or organizer is
handed the PIN for any session of their club rather than being asked for it,
so helping run a night no longer means finding whoever started it. It returns
null rather than raising when the caller is not staff, so the client falls
back to the PIN field and nothing depends on the migration having run. "Take
over a session" is "Open a session" now — it was never exclusive, and the
words said it was.

**The composer is pictures first, then the caption.** Tapping the camera
opens the picker; the caption is waiting underneath when it closes. Up to
four images, `multiple` on the input, shrunk harder when there are several
because they travel inside the row as data URLs and four at full size is a
post nobody can load. There is no "Add a photo" button inside the sheet — the
camera on the composer is the way in, and a second one was a button doing the
job of the button you had already pressed. `posts.photos` is `jsonb`, not a
single `photo text`: one picture or four posts was the only other option.

**Birthdays are a feed post, derived, never stored.** `Birthday.soon(7)`
walks forward from this morning rather than filtering on the calendar month,
because a birthday on the 2nd of October is invisible from the 28th of
September to a month filter and the week before somebody's birthday crosses
a month boundary about a third of the time. `feedTimeline()` turns the result
into at most two entries — whoever it is today, and whoever it is inside the
week — so there is nothing to post, nothing to post twice and nothing to go
stale. Neither carries an actions bar: a heart on something the app worked
out this morning would have nowhere to be kept.

**A confirmation whose "yes" branch costs nothing is a modal in the way.**
`startOrganizing()` put a sheet in front of an organizer who had just asked
for a new night, twice over — once when one was running and once when one was
merely open. Neither had anything to warn about: a night that is on the server
keeps its code, its link and everyone on it whatever this phone does next, and
any organizer can open it again from Sessions. Rewriting the copy did not fix
that, because the copy was not the problem. It goes straight through now and
says afterwards where the old one went.

Two sheets are left and both are about something that would really be lost: a
night **running with no link**, which exists nowhere but this phone, and a
half-filled draft, which has not been published anywhere. That is the test for
any sheet added here — name what is destroyed, or do not ask.

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

**A fresh night arrives already filled in.** `NewFlow.defaults()` puts
today's date and the club's usual hours on a session that has had nothing
set on it, because a blank form is four stages of typing before anything can
be published and most of it is the same every week. The guard is `S.dateOn`
being empty — a night somebody has already started is never overwritten, and
neither is a live one.

**Weekly repeats had become unreachable.** `setRepeat()` and
`nextOccurrence()` have always worked — ending a weekly night rolls it to
next week on the same code and PIN — but the only control that called them
was on the Setup screen, so retiring that screen quietly removed the one
feature that means you do not have to set a night up again. It is on the
When stage now, beside the date it repeats from.

**Ending a night clears the list, and that includes the waiting list.**
Clearing is the first thing offered now rather than the second: a night's
roster is who came to *that* night, and carrying it forward means the next
one opens with people on it who have not said they are coming. `S.waiting`
was being left behind entirely — so a night cleared from an empty list still
had people queueing on it, invisible on the roster, counted in "N waiting",
and coming in the moment a place opened on a night they never joined.

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
