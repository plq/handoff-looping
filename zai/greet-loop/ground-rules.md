# Greet-loop ground rules: the loop contract

**Read this file in EVERY pass, before touching anything.** It holds the
pass protocol, the build/test how-to, the fix discipline, the evidence
rules, the gates and the recording rules. The index (`index.md` next to
this file) says which other files your pass needs.

## Subject and outputs

The loop hardens `greet()` in `example/src/greet.c`, the example library
of the handoff-looping skill. The items in `items.md` are the plan of
record — each one states the wanted behaviour, the fix shape and the
test that pins it; re-derive nothing they already settle. An item
closes when its fix is committed WITH its failing-first tests and gate-G
is green. Durable facts go to `zai/greet-facts.md`. Working state lives
in `items.md` and is deleted as items close.

## ARMING GATE (checked FIRST, every pass)

The loop is armed only when the sign-off queue in `items.md` is fully
dispositioned: every queued question carries an owner-filled VERDICT
line (in the owner's words). Until then a pass does exactly this and
NOTHING else: park one standalone "OWNER QUESTION (sign-off round): …"
blockquote line per unverdicted question in the index's parking area
(the question's title and its options, one line each), add the halt
token per the index's token shapes, commit `index.md`, stop.

The first pass to find every VERDICT filled is the arming pass. Before
its first unit it: folds each verdict into the FIX SHAPE of the item it
governs, DELETES the sign-off queue section, clears the parking area,
sets the Order section and the NEXT ITEM pointer to G1, and logs an
"arming update" pass-log line. Then it proceeds as an ordinary pass.

## Owner sign-offs recorded in advance (2026-10-07)

Granted at loop setup; a pass relies on these WITHOUT parking a
question. Anything outside their wording still parks.

1. "Changes to greet()'s observable behaviour are approved exactly as
   the items spell them out: NULL or empty name greets a stranger,
   surrounding whitespace is dropped. Any other behaviour change, and
   any change to the function's signature, parks."
2. "New test cases in tests/test_greet.c and their add_test lines in
   example/CMakeLists.txt land without sign-off."
3. "No new dependencies, no toolchain or compiler-flag changes, no
   build-system changes beyond add_test lines. Anything in that class
   parks."
4. "Edits are confined to example/, zai/greet-loop/ and
   zai/greet-facts.md. Touching anything else in this repo — the skill
   under .claude/, util/, greet-loop/ — parks."

## Running a pass

1. STARTUP (nothing more): read the index and follow its reading order —
   this file, the ONE item section in `items.md` the NEXT ITEM pointer
   names, the subject files that item's "reads" line names, and this
   repo's CLAUDE.md.
2. Check the ARMING GATE above.
3. Re-measure every claim the item relies on — recorded behaviour, line
   numbers and the baseline census are hypotheses.
4. Execute one unit: MEASURE, FIX or BRIEF (below) — then optionally
   chain further units per the chaining rule.
5. End-of-pass protocol: FIX passes run gate-G; update the item's
   section in `items.md`; point the NEXT ITEM pointer in the index at
   the item the next pass should work — usually the SAME item until it
   closes or parks; append ONE pass-log line there (newest first);
   perform the growth upkeep below; commit per the commit discipline.
6. STOP at the pass boundary; end on a short closing text summary.

## Units and the item lifecycle

- MEASURE: measurement only, NO committed source edits — reproduce the
  item's claim (a scratch call to `greet()` is fine), run gate-G, record
  the census in the item (case names, the failing output verbatim, the
  exact commands). Local experiments are allowed but must be reverted
  before the pass ends (`git status` clean except docs).
- FIX: code edits — ONE coherent chunk sized to finish inside the pass,
  ALWAYS failing-test-first (CLAUDE.md): add the test cases the item's
  PIN line names, build, run them red, fix, run them green. Every chunk
  ends with a build plus gate-G proving the delta.
- BRIEF: doc-only — compiles NOTHING, runs NO suite. Write the analysis
  or the owner question into the item; park the question in the index
  per the index's token shapes.
- CHAINING: after a unit completes CLEANLY — its items.md update
  written and its commits landed — the pass MAY take another unit when
  the next one is already identified and sized to finish inside the
  pass. Cap: ~3 units. Checkpoint per unit (update the item, commit) so
  a pass that dies loses at most its current unit; NEVER carry a
  half-done unit toward the pass boundary — finish it or revert it. The
  end-of-pass protocol runs ONCE, after the last unit; its single
  pass-log line covers all units. A MEASURE may chain into the FIX it
  just made obvious — expected here: each item is one MEASURE + one FIX
  in a single pass.
- Lifecycle: OPEN (verdicts in) → FIXING → CLOSED | PARKED.
  - CLOSED: fix + tests committed, gate-G green, condensed record
    (≤8 lines) in `zai/greet-facts.md`, item section DELETED from
    `items.md`.
  - PARKED: blocked on the owner; the question is parked in the index
    and NEXT ITEM advances.
- A pass blocked on the owner does NOT stop the loop: park the
  question, advance NEXT ITEM to the next actionable item, continue.
  The loop halts only when NO item is actionable (the index documents
  the halt shape).

## Build & test how-to (Linux/macOS — re-measure baselines HERE)

A pass runs with the repo root as its working directory; the paths below
are relative to it. (Your own loops should inline ABSOLUTE paths — a
headless pass runs under an allowlist keyed on literal first words: no
`$(...)` substitution, no shell variables across tool calls. This
example cannot know where you cloned it.)

- Configure once per clean tree: `cmake -S example -B example/build`
- Build: `cmake --build example/build`
  (re-runs the configure step by itself when CMakeLists.txt changed, so
  a new add_test line needs nothing more than this).
- List cases: `ctest --test-dir example/build -N`
- One case: `ctest --test-dir example/build --output-on-failure -R '^greet\.null$'`
- Gate-G (all cases): `ctest --test-dir example/build --output-on-failure`

Builds and the whole suite finish in seconds, so everything runs in the
FOREGROUND here; the skill's background-and-wait rules (`util/wait-for.sh`)
are for loops whose gates take minutes. Write files with the Edit/Write
tools, never with a shell redirect into a repo path.

## Fix discipline

- Failing test first, always (CLAUDE.md): write the case against
  current behaviour, watch it fail for the RIGHT reason (its own FAIL
  line, not a compile error or a usage error), then fix. When a red
  might be pre-existing, prove it: `git stash` the work, rebuild, rerun,
  `git stash pop`.
- Test cases follow the existing shape: one `static int test_<name>(void)`
  returning 0 on success, a dispatch line in `main`, one `add_test` line
  named `greet.<name>`.
- `greet()` keeps its signature and its snprintf return-value contract
  (the length of the FULL greeting, truncated or not). No allocation; do
  not mutate the caller's string.
- Comments and messages in English. There is no formatter in this
  project; match the surrounding style by hand.
- An out-of-scope discovery (an unrelated bug, a toolchain quirk) gets a
  dated entry in the item and nothing more — do NOT divert the pass into
  chasing it; it goes to the owner or to its own loop.

## Gates

FIX passes run the gates; MEASURE runs what its census needs; BRIEF
runs nothing.

- Gate-G: `ctest --test-dir example/build --output-on-failure`.
  Baseline at creation (2026-10-07): 2 cases, `greet.basic` and
  `greet.truncation`, both green. Compare case NAMES, never counts.
- Completion: the LAST item closes AND gate-G runs fully green in that
  pass → write the completion token per the index.

## Evidence rules

- Primary evidence for a failing run: the `--output-on-failure` text of
  the ctest run (the test's own `FAIL <what>: got "…"` line) and
  `example/build/Testing/Temporary/LastTest.log`, which every ctest
  invocation OVERWRITES — copy it into `greet-loop/evidence/` first if
  you need it past the next run.
- Excerpt the load-bearing lines into the item's section — the doc is
  the durable record, evidence/ is gitignored scratch.

## Growth upkeep (every pass — the doc set must NOT grow indefinitely)

- The index holds only the map, the NEXT ITEM pointer, parked questions
  and the pass log: one `> -` prefixed line per pass, ≤3 sentences,
  newest first, CAPPED at the ~10 newest — delete older lines once
  their substance is in `items.md` or the facts doc.
- Closing an item: condensed record (≤8 lines — what was fixed, the
  tests that pin it, commits, final ctest numbers) into
  `zai/greet-facts.md`, then DELETE the item's section from `items.md`.
- Facts that stop being true are corrected in place — no strikethrough
  trails.

## Branch & commit discipline

- One repo: this clone. Commit on whatever branch it has checked out
  (CLAUDE.md); never switch branches. The working directory is already
  the repo root, so git runs plain — no `cd`, never `git -C`.
- Ordinary per-concern commits, each carrying its tests: one commit per
  item is the expected shape (fix + tests + the items.md/index.md/facts
  updates that record it). NEVER amend a pushed commit; amending a
  still-local HEAD commit of the same pass is fine. Do NOT push —
  commits stay local; the owner synchronizes.
- Commit shape — don't stage, name the paths on the commit:
  `git commit -F - -- <your paths>` with the message on a quoted
  heredoc (literal text). Given paths, `git commit` takes exactly those
  paths' working-tree content and leaves the rest of the index alone.
  No `git add` before it. The one exception is a NEW file, which git
  cannot commit by path until it has seen it: `git add -N <path>`
  (intent-to-add — registers the path, stages no content), then the
  commit above. Never `git add -A` / `-u`, never a bare `git commit`.
