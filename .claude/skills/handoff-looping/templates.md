# Handoff-loop file templates

Skeletons for the five files of a handoff loop (see `SKILL.md` for the contract).
`<angle-bracket>` slots are per-loop fill-ins. Keep the load-bearing comments — they
encode the reasons; a future retargeting relies on them.

On Windows, apply `windows.md` (next to this file) on top: the loop directory gains
five environment/bridge scripts, `loop.sh` gains an environment import, and the
ground rules gain a Windows how-to section.

## `<loop-name>/loop.sh` — the driver

```bash
#!/usr/bin/env bash
# Drives the <loop-name> loop: <one-line subject>, one pass per
# iteration. Every iteration is a FRESH `claude -p` invocation: context
# resets each time; the doc set indexed by $DOC below is the only memory
# between passes. The per-pass prompt lives in prompt.md next to this
# script.
#
# ARMING: do not run this before the sign-off queue in the doc set's
# items.md is fully dispositioned — a premature pass parks the round and
# exits 2 (the ground rules' ARMING GATE), which wastes a pass doing it.
# <delete this paragraph if the loop has no sign-off queue>
#
# OWNER-RUN: this driver is launched by the OWNER in their own terminal.
# Assistant sessions scaffold, arm, answer halted questions and read
# logs — they never execute it.
#
# Retargeting this driver at another subject means changing THREE things
# in lockstep: DOC, DONE_TOKEN (each loop's doc carries its OWN
# completion token) and prompt.md. A DONE_TOKEN that does not match the
# doc never fires, so the loop would keep spawning passes past the end
# of the work.
#
# Stop conditions (checked before every pass):
#   - $DONE_TOKEN appears in the doc        -> done, exit 0
#   - LOOP-HALT appears in the doc          -> a pass parked owner
#                                              question(s) and no item was
#                                              actionable; exit 2 — answer in
#                                              the doc, remove the token,
#                                              rerun
#   - two consecutive nonzero pass exits    -> exit 1 (inspect the log)
#   - MAX_PASSES exhausted                  -> exit 1
#
# Knobs (env): MODEL, MAX_PASSES, SLEEP_BETWEEN, PERMISSION_MODE.
# Logs: one file per pass under logs/ next to this script (tail -f to
# watch), plus logs/context.log — one end-of-pass context line per
# pass, the headless stand-in for /context, written by the shared
# util/pass-report.sh after each pass. evidence/ holds archived test
# artifacts the passes save (both dirs are gitignored via this
# directory's .gitignore).

# -u/pipefail but NOT -e: a failed pass must not kill the driver — the
# consecutive-failure counter below decides when to stop.
set -u -o pipefail

MODEL="${MODEL:-opus}"
MAX_PASSES="${MAX_PASSES:-30}"
SLEEP_BETWEEN="${SLEEP_BETWEEN:-15}"
PERMISSION_MODE="${PERMISSION_MODE:-dontAsk}"

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )" # "
REPO="$( cd "$DIR/.." && pwd )"                 # the repo hosting the doc set
PARENT="$( cd "$REPO/.." && pwd )"              # the sibling checkouts
UTIL="$PARENT/util"                             # shared loop helpers (pass-report.sh, wait-for.sh)
DOC="$REPO/zai/<loop-name>/index.md"
LOG_DIR="$DIR/logs"
EVIDENCE_DIR="$DIR/evidence"
PROMPT_FILE="$DIR/prompt.md"

DONE_TOKEN="<LOOP-NAME>-LOOP-COMPLETE"
HALT_TOKEN="LOOP-HALT"

# Scope: ONLY the repos the ground rules put in scope — read-only
# context repos included, build-staging and everything else excluded.
ADD_DIRS=(
    "$PARENT/<sibling-repo>"
)

# Fail fast on a broken environment: a pass without the toolchain cannot
# do anything except burn money diagnosing itself.
for t in claude cmake ctest; do    # <extend with the loop's tools>
    if ! command -v "$t" >/dev/null 2>&1; then
        echo "[loop] '$t' not on PATH — fix the environment before running" >&2
        exit 1
    fi
done

if [[ ! -r "$PROMPT_FILE" ]]; then
    echo "[loop] prompt file missing: $PROMPT_FILE" >&2
    exit 1
fi
if [[ ! -r "$DOC" ]]; then
    echo "[loop] doc missing: $DOC" >&2
    exit 1
fi
if [[ ! -r "$UTIL/pass-report.sh" ]]; then
    echo "[loop] shared helper missing: $UTIL/pass-report.sh (the util checkout beside this repo)" >&2
    exit 1
fi
PROMPT=$(<"$PROMPT_FILE")

mkdir -p "$LOG_DIR" "$EVIDENCE_DIR"

add_dir_flags=()
for d in "${ADD_DIRS[@]}"; do
    add_dir_flags+=(--add-dir "$d")
done

consecutive_failures=0

for ((pass = 1; pass <= MAX_PASSES; pass++)); do
    # Anchored matches only: the doc's own instructions NAME both tokens
    # mid-sentence, so a bare grep would false-positive. Both tokens are
    # LABELS on their own lines: completion = the token alone on its own
    # line; halt = the token alone on its own (possibly blockquoted)
    # line, parked next to standalone "OWNER QUESTION (...):" lines.
    # [[:space:]]* also eats a stray \r if the doc ever lands with CRLF
    # endings.
    if grep -qE "^$DONE_TOKEN[[:space:]]*$" "$DOC"; then
        echo "[loop] $DONE_TOKEN found in the doc — the work is done."
        exit 0
    fi
    if grep -qE "^(> *)?$HALT_TOKEN[[:space:]]*$" "$DOC"; then
        echo "[loop] $HALT_TOKEN found in the doc — no item was actionable; question(s) for the owner:"
        grep -nE "^(> *)?OWNER QUESTION" "$DOC" || true
        echo "[loop] answer in the doc (record sign-offs verbatim), remove the token, rerun."
        exit 2
    fi

    echo "[loop] ---- pass $pass/$MAX_PASSES $(date -Is) ----"
    grep -m1 "NEXT ITEM:" "$DOC" || true

    log="$LOG_DIR/pass-$(date +%Y%m%d-%H%M%S).jsonl"
    echo "[loop] running claude (model=$MODEL, permission-mode=$PERMISSION_MODE); log: $log"

    # stream-json gives a full machine-readable transcript per pass
    # (every message and tool call, one JSON object per line); stderr
    # goes to .err.
    if (cd "$REPO" && claude -p "$PROMPT" \
        --model "$MODEL" \
        --permission-mode "$PERMISSION_MODE" \
        --verbose --output-format stream-json \
        "${add_dir_flags[@]}") >"$log" 2>"${log%.jsonl}.err"; then
        echo "[loop] pass $pass finished."
        # Result text, the newest pass-log line (the RELIABLE handoff
        # record — the result is only as good as the pass's closing
        # text) and the context report, appended to logs/context.log:
        # the shared driver-side helper; its header says what each line
        # means and how to read the context trend.
        bash "$UTIL/pass-report.sh" "$log" "$DOC" "$pass" "$LOG_DIR/context.log" || true
        consecutive_failures=0
    else
        rc=$?
        consecutive_failures=$((consecutive_failures + 1))
        echo "[loop] pass $pass exited rc=$rc ($consecutive_failures consecutive failure(s))."
        if ((consecutive_failures >= 2)); then
            echo "[loop] two consecutive failures — stopping for a human. See $LOG_DIR."
            exit 1
        fi
    fi

    echo

    sleep "$SLEEP_BETWEEN"

    # Branch regime (ground rules): <which repos commit on which branch>.
    # Commits stay LOCAL — the owner pushes.
done

echo "[loop] MAX_PASSES=$MAX_PASSES reached without $DONE_TOKEN — stopping for a human."
exit 1
```

## `<loop-name>/prompt.md` — the per-pass bootstrap

One paragraph, no state. Anything that changes as the loop runs belongs in the doc
set, never here.

```text
Continue the <loop-name> loop (<one-breath subject: what is being
hardened/fixed/worked, per what plan — measure, fix test-first, verify,
record>) — one pass of many. The entry point and ONLY inter-pass memory
is the doc set indexed by zai/<loop-name>/index.md in <repo>. STARTUP
(nothing more): read that INDEX and follow its reading order —
zai/<loop-name>/ground-rules.md is the protocol and its ARMING GATE
comes before everything; read ONLY the subject docs the current item's
"reads" line names, plus the ONE item section in
zai/<loop-name>/items.md the NEXT ITEM pointer names — whatever it
names now; do not trust any item name written into this prompt, the doc
set is the authority. Also read <repo>'s CLAUDE.md. Every recorded
claim, line number and error census is a hypothesis — re-measure before
acting. Execute at least ONE unit — chaining more only per the ground
rules' CHAINING rule — run the end-of-pass protocol from the ground
rules (growth upkeep included), then STOP at the pass boundary and end
on a short closing text summary.
```

Drop the "and its ARMING GATE comes before everything" clause if the
loop has no arming gate (the win-port prompt did).

## `<loop-name>/.gitignore`

```text
/logs/
/evidence/
```

## `zai/<loop-name>/index.md` — the map

```markdown
# <Loop-name> loop — INDEX

The loop that <subject, one paragraph: the items, the plan of record
with its doc path>. Driver: `<loop-name>/loop.sh` (<repo>) — a fresh
`claude -p` per pass; THIS doc set is the only inter-pass memory.

## Reading order (STARTUP, nothing more)

1. `ground-rules.md` (next to this file) — the protocol, every pass.
   Its ARMING GATE comes before everything.
2. The ONE item section in `items.md` that the NEXT ITEM pointer below
   names — whatever it names now.
3. The subject docs that item's "reads" line names — nothing else.
4. <repo>'s `CLAUDE.md`.

## Status

NEXT ITEM: <item-id, or "(NOT ARMED — sign-off round pending)">

<created date; arming state; anything the next pass must know that has
no better home. Keep it short — this is a pointer, not a log.>

## Owner questions (parking area)

(none parked)

## Tokens (the driver greps this file — never reproduce the shapes early)

- Completion: when the LAST item closes AND <the loop's gate> has run
  fully green in that pass, the pass writes the completion token — the
  string <LOOP-NAME>-LOOP-COMPLETE alone on its own line — at the top
  of this file. The driver matches whole lines only, so the
  mid-sentence mentions in this section never fire.
- Halt: only when NO item is actionable (not armed, all blocked or all
  done), park the pending question(s) as standalone
  "OWNER QUESTION (…):" blockquote lines above, then add a blockquote
  line holding the halt token — the string LOOP-HALT alone on that
  line, optionally after "> " — commit, stop. The driver exits 2 on
  that exact shape.

## Pass log (newest first; `> -` prefixed lines, ≤3 sentences, cap ~10)

> - <date> pass 0 (creation): doc set created — <plan of record>,
>   ground rules, items <list>, driver. <Armed at item X / NOT armed;
>   owner verdicts next.>
```

The pass-log format is load-bearing: the driver's awk prints the newest `> - ` entry
plus its `>   ` continuation lines as the per-pass summary.

The log starts before the first pass: while the loop sits unarmed waiting on the
owner (SKILL.md, scaffolding step 8), each adopted answer or correction is committed
with its own `> - <date> arming update N: …` line — pre-arming evolution is loop
history like any pass.

## `zai/<loop-name>/ground-rules.md` — the loop contract

Every section below stays (only the arming gate is conditional — its own note says
when to delete it); the `<…>` slots are the per-loop content. Keep the file
self-sufficient — a pass reads nothing else before acting on it.

```markdown
# <Loop-name> ground rules: the loop contract

**Read this file in EVERY pass, before touching anything.** It holds the
arming gate, the pass protocol, the build/test how-to, the fix
discipline, the evidence rules, the gates and the recording rules. The
index (`index.md` next to this file) says which other files your pass
needs.

## Subject and outputs

<What the loop does and the plan of record (doc path) whose analysis
governs — re-derive nothing it already settles. What "an item closes"
means (fix committed WITH its failing-first tests, gates green).
Durable facts go to <facts doc path>. Working state lives in `items.md`
and is deleted as items close.>

## ARMING GATE (checked FIRST, every pass)

<Delete this section if the loop needs no sign-off; then the loop is
born armed.> The loop is armed only when the sign-off queue in
`items.md` is fully dispositioned: every queued item carries an
owner-filled VERDICT line (approved / rejected / modified, in the
owner's words). Until then a pass does exactly this and NOTHING else:
park one standalone "OWNER QUESTION (sign-off round): …" line per
unverdicted item in the index, add the halt token per the index's token
shapes, commit, stop. Approved items get ordered into `items.md`'s
Order section; rejected ones move their distilled record to <the plan
of record>'s rejected section and their item section is DELETED.

## Owner sign-offs recorded in advance (<date>)

<Every loop carries this section — drafting it is a scaffolding step
(SKILL.md), and scaffolding ends with the owner dispositioning it.
Enumerate the decision classes passes will predictably face —
production-edit policy, gating/excluding tests, toolchain or cache
changes, dependency installs, edits at the scope's edges — and record
the verdicts VERBATIM. Every class left unasked resurfaces later as a
parked question and a halted loop.>
Granted at loop setup; a pass relies on these WITHOUT parking a
question. Anything outside their wording still parks.

1. <standing permission, in the owner's words, with its boundary — e.g.
   "platform-additive production edits land without per-item sign-off;
   anything that would alter the <other-platform> build/behavior still
   parks">.
2. <…>

## Running a pass

1. STARTUP (nothing more): read the index and follow its reading order —
   this file, the ONE item section in `items.md` the NEXT ITEM pointer
   names, the subject docs that item's "reads" line names, and
   <repo>'s CLAUDE.md.
2. Check the ARMING GATE above.
3. Re-measure every claim the item relies on — recorded line numbers,
   census results and baselines are hypotheses.
4. Execute one unit: MEASURE, FIX or BRIEF (below) — then optionally
   chain further units per the chaining rule.
5. End-of-pass protocol: stop any still-running builds/suites you
   started (TaskStop; kill-by-exact-name only as fallback, and only
   after verifying every match is your own); clang-format every touched
   source; FIX passes run the gates; update the item's section in
   `items.md`; point the NEXT ITEM pointer in the index at the item the
   next pass should work — usually the SAME item until it closes or
   parks; append ONE pass-log line there (newest first); perform the
   growth upkeep below; commit EVERY touched repo per the branch
   discipline.
6. STOP at the pass boundary; end on a short closing text summary.

## Units and the item lifecycle

<Rename the unit taxonomy to fit the subject — the win-port loop used
CENSUS/PORT/BRIEF. The three SHAPES are the invariant: measurement-only,
code-change, doc-only.>

- MEASURE: measurement only, NO committed source edits — reproduce the
  claim, run the relevant suites, record the census in the item
  (counts, first errors verbatim with file:line, the exact commands).
  Local experiments are allowed but must be reverted before the pass
  ends (`git status` clean except docs).
- FIX: code edits — ONE coherent chunk sized to finish inside the pass,
  ALWAYS failing-test-first (CLAUDE.md): add the test, run it red, fix,
  run it green. Every chunk ends with a build plus the relevant ctest
  run proving the delta.
- BRIEF: doc-only — compiles NOTHING, runs NO suite. Write the analysis
  or the owner question into the item; park the question in the index
  per the index's token shapes.
- CHAINING: after a unit completes CLEANLY — its items.md update
  written and its commits landed — the pass MAY take another unit when
  the next one is already identified and sized to finish inside the
  pass. Rough cap: ~3 units, less if the transcript is getting long.
  Checkpoint per unit (update the item, commit) so a pass that dies
  loses at most its current unit; NEVER carry a half-done unit toward
  the pass boundary — finish it or revert it. The end-of-pass protocol
  runs ONCE, after the last unit; its single pass-log line covers all
  units. A MEASURE may chain into the FIX it just made obvious.
- Lifecycle: PROPOSED → (verdict) → OPEN → FIXING → CLOSED | PARKED.
  - CLOSED: fix + tests committed, gates green (modulo reds recorded as
    pre-existing at baseline), condensed record (≤8 lines) in <facts
    doc>, item section DELETED from `items.md`.
  - PARKED: blocked on the owner; the question is parked in the index
    and NEXT ITEM advances.
- A pass blocked on the owner does NOT stop the loop (post-arming):
  park the question, advance NEXT ITEM to the next actionable item,
  continue. The loop halts only when NO item is actionable (the index
  documents the halt shape).

## Build & test how-to (<platform> — re-measure baselines HERE)

<LITERAL commands only — a pass runs headless under an allowlist keyed
on literal first words: no $(...) substitution, no shell variables
across tool calls. Start from the repo's own build how-to and
inline: the literal build-dir path (and how to re-discover it), the
build command, the ctest patterns for the loop's suites, the
new-test-case build-then-reconfigure order, the literal clang-format
path, the literal absolute path of the sibling `util` checkout
(`<util>` below — the absolute path of `../util` seen from the repo) that holds the
shared helpers, and — when a suite reads env knobs — the env wrapper's
literal invocation (`<wrapper> NAME=VALUE … ctest <args>`; a bare
`VAR=… ctest` prefix is denied, SKILL.md point 11).>

Long builds/runs go in the BACKGROUND (a ~120 s foreground window
bounces them) — but NEVER end the pass's turn waiting on one, and never
park the pass expecting the background task's completion notification
to wake it: a pass is a headless `claude -p`, the session dies WITH the
turn and the run is killed with nothing recorded. Size the chunk to
finish INSIDE the pass, `tee` the run into a file and block on it
within the turn with the sanctioned wait —
`bash <util>/wait-for.sh <file> '<regex>' [timeout-seconds]`, by that
ABSOLUTE path (ad-hoc polling shapes are denied; a relative invocation
is too) — and record the result in the SAME pass.

## Fix discipline

- Failing test first, always (CLAUDE.md): write the test against
  current behavior, watch it fail for the RIGHT reason, then fix. When
  a red might be pre-existing, prove it: `git stash` the work, rebuild,
  rerun, `git stash pop`.
- <Repo hygiene per CLAUDE.md that applies to every touched file — e.g.
  a logging-idiom migration, comments translated to English, the
  formatter run per file. Spell the rules out; a pass reads this, not
  the whole CLAUDE.md history.>
- An out-of-scope discovery (a flake, an unrelated bug) gets a dated
  entry in the item and nothing more — do NOT divert the pass into
  chasing it; it goes to the owner or to its own loop.
- <Loop-specific constraints: wire compatibility, harness locations and
  helpers to extend rather than duplicate, forbidden shortcuts, the
  test-wait rules that apply.>

## Gates

FIX passes run the gates; MEASURE runs what its census needs; BRIEF
runs nothing.

- <gate name>: <the literal ctest invocation covering the suites this
  loop can break>. If UNMEASURED at arming: the first MEASURE unit runs
  it on a clean tree and records the census (green count, every red BY
  NAME with its first error verbatim) in `items.md`. Compare case
  NAMES, never counts.
- Completion: the LAST item closes AND <gate> runs fully green in that
  pass → write the completion token per the index.

## Evidence rules

- Primary evidence for a failing run: <the platform's test log —
  e.g. `<BD>/Testing/Temporary/LastTest.log`, OVERWRITTEN by every
  ctest invocation, archive it FIRST, before any rerun — and the
  per-case run dirs, date-correlated (mtime against your run window)
  before citing them>.
- Archive into `<loop-name>/evidence/` (gitignored scratch), then
  excerpt the load-bearing lines into the item's section — the doc is
  the durable record, evidence/ is scratch.

## Growth upkeep (every pass — the doc set must NOT grow indefinitely)

- The index holds only the map, the NEXT ITEM pointer, parked questions
  and the pass log: one `> -` prefixed line per pass, ≤3 sentences,
  newest first, CAPPED at the ~10 newest — delete older lines once
  their substance is in `items.md` or the facts doc.
- Closing an item: condensed record (≤8 lines — what was fixed, the
  tests that pin it, commits, final ctest numbers) into <facts doc>,
  then DELETE the item's section from `items.md`.
- Facts that stop being true are corrected in place — no strikethrough
  trails.

## Branch & commit discipline

- <Per repo: branch to commit on; verify-the-checkout rules ("if the
  checkout is NOT on <branch>: stop, park an owner question, do not
  guess and do not switch branches"); which repos are READ-only context
  (an edit there parks an owner question first); which dirs are never
  edited.>
- Ordinary per-concern commits, each carrying its tests. NEVER amend a
  pushed commit; amending a still-local HEAD commit of the same pass is
  fine. Do NOT push — commits stay local; the owner synchronizes.
- Git runs IN the repo, plain: `cd /abs/path/<repo>` as its OWN tool
  call, then the git verbs in the calls that follow (the working
  directory persists between calls), then `cd` back to <host repo>
  right after — every later call inherits the cwd. Never `git -C
  <repo>` and never a `cd … && git …` chain — the chain is denied,
  and `git -C` has no allowlist rule and needs none.
- Commit shape in EVERY repo — don't stage, name the paths on the
  commit: `git commit -F - -- <your paths>` with the message on a
  quoted heredoc (literal text). Given paths, `git commit` takes
  exactly those paths' working-tree content and leaves the rest of
  the index alone — this checkout's STAGING AREA may be shared with
  another loop's pass, and a bare `git commit` takes whatever it has
  staged. No `git add` before it. The one exception is a NEW file,
  which git cannot commit by path until it has seen it:
  `git add -N <path>` (intent-to-add — registers the path, stages no
  content), then the commit above. `git rm` / `git mv` stage what
  they do and are the shapes for deleting / renaming a tracked file.
  Never `git add -A` / `-u`, never a bare `git commit`.
```

## `zai/<loop-name>/items.md` — working state

```markdown
# <Loop-name> loop items

Working state only — an item's section is DELETED when it closes
(ground rules, growth upkeep); durable output goes to <facts doc>. The
plan of record is <doc path> — every claim and line number there and
here is a hypothesis; re-measure before acting.

## Order

<Armed: the item order. Not armed: "NOT ARMED — sign-off round
pending" plus the intended order after arming.>

## <ID> — <title> (<OPEN|PROPOSED>, <signed|verdict pending>)

- reads: <the subject docs and sections this item needs — the index's
  reading order step 3 resolves through this line>.
- WHAT: <the problem, with the code locations as recorded — to be
  re-verified by the pass>.
- FIX SHAPE: <the intended fix and its constraints; name precedents>.
- PIN: <the failing-first test that will pin the fix — where it lives,
  what it asserts; or the recorded reason a deterministic test is not
  practical>.

## Sign-off queue (each needs an owner verdict BEFORE the loop is armed)

### <ID> — <title> (PROPOSED)

- CONTEXT: <why this is on the table; owner words quoted verbatim>.
- OPTIONS: <(a)/(b)/(c) with trade-offs>.
- VERDICT: (owner fills in: approved / rejected / modified — in the
  owner's words)
```
