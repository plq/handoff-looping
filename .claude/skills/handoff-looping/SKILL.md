---
name: handoff-looping
description: Set up, retarget, or operate a handoff loop — a backlog worked by repeated fresh headless `claude -p` passes with a committed doc set as the only inter-pass memory. Use for autonomous loops of fresh sessions: scaffolding a hardening/backlog loop (like greet-loop in this repo), retargeting a loop driver at a new subject, or answering a halted loop's owner questions. Read templates.md (next to this file) before scaffolding; windows.md too when the loop runs on Windows.
---

# Handoff looping

A **handoff loop** executes a backlog that is too big for one session as a series of
**fresh `claude -p` passes**. Context resets on every pass by design: nothing survives
except a **doc set committed to the repo**, which each pass reads at startup and updates
before it stops. The doc set is simultaneously the work queue, the protocol, the memory
and the off switch. A driver shell script spawns passes and greps the doc for control
tokens to know when to stop.

Reference implementation: `greet-loop/loop.sh` + `zai/greet-loop/` in this repo
(driver + doc set, armed, against the example library in `example/`). The rules
below cite two earlier loops by name: fifo-hardening-loop (a multi-day hardening
round with a sign-off queue) and win-port-loop (a Windows test port, run to
completion); neither ships here, they are the measurements' provenance.
Read `templates.md` (next to this file) before scaffolding; **on Windows also
`windows.md`** — toolchain import, bridge scripts, measured allowlist traps.

## When to reach for it

- A backlog of separable items that will outgrow any single context window
  (multi-day hardening rounds, migration sweeps, review-backlog burndown).
- "Keep going until it's done" requests where each increment is verifiable on its own.

Not for single-session tasks (just do them), and not for work that needs the user's
input at every step — the loop *parks* owner questions and continues; it only pays off
when most items are actionable without a human.

## Anatomy — two locations, five files

| File | Where | Committed? | Role |
|---|---|---|---|
| `loop.sh` | `<loop-name>/` at repo root | yes | driver: spawns passes, greps tokens, stops |
| `prompt.md` | `<loop-name>/` | yes | thin per-pass bootstrap; points at the index, nothing else |
| `.gitignore` | `<loop-name>/` | yes | ignores `logs/` and `evidence/` (scratch) |
| `index.md` | `zai/<loop-name>/` | yes | map, reading order, NEXT ITEM pointer, parked questions, token shapes, pass log |
| `ground-rules.md` | `zai/<loop-name>/` | yes | the loop contract, read in EVERY pass: arming gate, pass protocol, units, gates, upkeep |
| `items.md` | `zai/<loop-name>/` | yes | working state only; item sections are DELETED as they close |

**Mechanics live in scripts, policy in the docs.** Shared helpers sit in the sibling
`util/` checkout: `pass-report.sh` (driver-side; the owner runs the driver, no
allowlist needed) and `wait-for.sh` (pass-side; ABSOLUTE path, one narrow allowlist
rule — step 5). A script's header is its contract; the ground rules carry the policy
and the one-line invocation, never the plumbing (the doc set is read every pass, a
script is not). Git is not wrapped: a pass runs plain `git` in the repo (point 12).

Plus a **durable facts doc** *outside* the loop directory (a `zai/*-facts.md` or
`*-invariants.md` in the subject repo): the loop directory and doc set are disposable
once the loop completes; anything worth keeping is condensed there as items close.
Most loops also have a **plan of record** the ground rules point at (e.g.
`zai/fifo-hardening-handoff.md`): the analysis, owner context, distilled fixes and the
considered-and-REJECTED list that keeps settled questions closed. It is committed as a
work in progress like the rest of the doc set (step 8).

## The contract — why each piece is shaped the way it is

1. **Fresh context per pass** ⇒ everything a pass needs must be re-derivable from the
   doc set alone. Corollary the docs must state explicitly: every recorded claim, line
   number and census is a **hypothesis — re-measure before acting** (the tree moved
   since it was written).
2. **One entry point.** `prompt.md` names the subject in one breath and points at
   `index.md`; the index gives the reading order; the NEXT ITEM pointer names the item.
   Never bake item names or state into the prompt — it goes stale, the doc set does
   not — and say so in the prompt ("the doc set is the authority").
3. **Control tokens, whole-line anchored.** Two, both grepped by the driver against
   the index: completion — a **loop-specific** `<LOOP-NAME>-LOOP-COMPLETE` alone on
   its line, written only when the last item closes AND the loop's gate ran green;
   halt — `LOOP-HALT` alone on its (possibly `> `-blockquoted) line, written only
   when NO item is actionable, beside standalone `OWNER QUESTION (…):` lines. The
   greps are anchored (`^token[[:space:]]*$`, the class eating a stray CR) because
   the docs *name* the tokens mid-sentence — hence also "never reproduce the shapes
   early". A shared completion token would let one loop's completion stop another.
4. **Three driver exits.** `0` = completion token (done). `2` = halt token (parked on
   the owner: answer in the doc, verdicts verbatim, remove the token, rerun). `1` =
   two consecutive nonzero pass exits or MAX_PASSES exhausted (a human reads the
   newest log). One failed pass is tolerated — passes die for transient reasons.
5. **Arming gate.** A backlog that needs owner sign-off is not armed until every
   queued item carries an owner-filled VERDICT line; an unarmed pass only parks one
   OWNER QUESTION per unverdicted item, writes the halt token, commits, stops — the
   driver header warns against running before arming. Its complement, keeping an
   armed loop autonomous: **standing sign-offs** in the ground rules — blanket
   permissions in the owner's words that a pass relies on WITHOUT parking, boundary
   stated: anything outside their wording still parks. Drafting and dispositioning
   them is scaffolding work (steps 3 and 8), never an afterthought.
6. **The pass protocol lives in `ground-rules.md`**, read first in every pass: reading
   order → arming check → re-measure → units → end-of-pass protocol → STOP at the
   boundary. The *reliable* handoff record is the pass-log line in the index, printed
   by the driver after each pass; the model's closing text is best-effort.
7. **Units sized to finish inside the pass.** A pass is a headless `claude -p`: the
   session dies with the turn, and a still-running background build/suite dies with
   it, unrecorded. Parking on a background task's completion notification is the
   trap — interactively that is how you wait; headless, the notification never comes
   (measured on the flaky loop). So: size chunks to complete inside the pass, block on
   long background runs *within* the turn (`util/wait-for.sh` by absolute path; the
   allowlist denies ad-hoc polling), record the result in the SAME pass, checkpoint
   per unit (doc update + commit), and never carry a half-done unit toward the
   boundary — finish it or revert it.
8. **Three unit shapes; names are per-loop.** MEASURE (measurement only, no committed
   source edits), FIX (one coherent test-first chunk), BRIEF (doc-only); chaining
   after a clean checkpoint, capped (~3). Rename to fit the subject (win-port used
   CENSUS/PORT/BRIEF) — the shapes are the invariant. An **out-of-scope discovery**
   (a flake, an unrelated bug) gets a dated entry in the item and nothing more; it
   goes to the owner or its own loop.
9. **Growth upkeep, every pass**, or startup reading swallows the pass budget: pass
   log capped (~10 newest `> -` entries, ≤3 sentences each), closed item sections
   DELETED from `items.md` after condensing (≤8 lines) into the facts doc, stale
   facts corrected in place — no strikethrough trails.
10. **The NEXT ITEM pointer is the single dispatch point.** Every pass ends by aiming
    the next pass — usually at the SAME item until it closes or parks. A pass blocked
    on the owner does not stop an armed loop: park the question, advance the pointer,
    continue. Halt only when NOTHING is actionable.
11. **Literal commands in the docs.** Passes run headless under an allowlist keyed on
    literal first words: no `$(…)`, no shell variables across tool calls. The ground
    rules inline the LITERAL build dir, ctest patterns and tool paths (from the
    repo's build how-to). Under `dontAsk` an unlisted shape is silently
    denied, not prompted — allowlist coverage is settled at scaffolding (step 5),
    never at runtime. A shell `>` redirect INTO A REPO PATH is denied even when the
    command's first word is allow-listed (measured 2026-09-09: `sed … > <file>` was
    allowed with a scratchpad target, denied with a `zai/` target) — files are written
    with Write/Edit or `tee`; anything assembled in the shell goes to the scratchpad
    and is `cp`'d in. An environment prefix (`VAR=… ctest …`) is denied too — it has
    no first word to key on (measured 2026-09-29, fuuidp2 pass 1). Give it one: a
    wrapper that takes `NAME=VALUE` arguments and execs the ONE command it wraps,
    allow-listed by absolute path, its accepted names restricted so the rule admits
    nothing more (owner direction: the loop "just needs a loop driver script that lets
    it set the environment variable using a command line argument";
    the shape is a dozen lines: a `case` over the accepted names, `export`, then
    `exec ctest "$@"`). Under `dontAsk` a session cannot edit
    `.claude/settings*.json` or the skills: hand the allowlist lines to the owner
    literally, or have them switch the permission mode first.
12. **Commit discipline stated per repo.** Which repos may be edited, which branch each
    commits on, read-only context repos (edits there park an owner question first).
    Per-concern commits carrying their tests; commits stay LOCAL — the owner pushes.
    Two shapes, owner policy (2026-09-09):
    - **Git runs IN the repo: `cd` first, never `git -C`.** `cd /abs/path/<repo>` as
      its OWN tool call, the git verbs in the calls that follow (the cwd persists
      between calls), then `cd` back to the host repo — later calls inherit the cwd.
      Measured under the loop allowlist: a standalone `cd` inside the roots needs no
      rule; a `cd … && git …` chain is DENIED; `git -C` has no rule and gets none.
    - **Don't stage — pass the paths to `git commit`.** `git commit -F - -- <paths>`
      with the message on a quoted heredoc: it takes exactly those paths' working-tree
      content and leaves the rest of the index alone. No `git add` before it; a NEW
      file, which git cannot commit by path until it has seen it, gets `git add -N`
      (intent-to-add, no content staged) and nothing more; `git rm`/`git mv` stage by
      nature and are the shapes for a tracked file. Never `git add -A`/`-u`, never a
      bare `git commit`: loops sharing a checkout share its STAGING AREA, and on
      2026-09-02 a bare `git commit` swept four files another loop's pass had staged.
13. **Driver hygiene.** Fail fast if a required tool is missing from PATH (a pass
    without its toolchain only burns money diagnosing itself); one stream-json log
    per pass under `logs/`, `evidence/` for archived test artifacts (both gitignored);
    the per-pass report is `util/pass-report.sh` — no JSON plumbing in `loop.sh`;
    `set -u -o pipefail` but NOT `-e` (the failure counter, not a failed pass, stops
    the driver).
14. **A context report closes every pass** (owner policy, 2026-09-09). `/context` is a
    REPL command no pass can run, so `util/pass-report.sh` prints the headline from
    the transcript (context at end of pass as a share of the window, turns, output
    tokens, cost) and appends it to `logs/context.log`. A rising figure means the
    startup reading is growing or units/chaining outgrow the window: tighten the doc
    set, the chaining cap or the unit sizes before passes start dying full.

## Scaffolding a new loop

1. Pick `<loop-name>` and the completion token `<LOOP-NAME>-LOOP-COMPLETE`. On
   Windows read `windows.md` first (four extra scripts, a Windows how-to section).
2. Write the doc set from `templates.md`: `index.md` (map, reading order, status,
   token shapes, empty pass log), `ground-rules.md` (fill every per-loop slot — subject,
   gates, build how-to with literal paths, branch discipline), `items.md` (one section
   per item: reads / WHAT / FIX SHAPE / PIN; an Order section; sign-off queue if any).
3. **Draft the advance sign-offs** (point 5) — always, even without per-item
   verdicts: enumerate the decision classes passes will face (production-edit
   policy, gating/excluding tests, toolchain or cache changes, dependency installs,
   edits at the scope's edges, read-only repos) and write each as a PROPOSED standing
   sign-off with its boundary. Every class left unasked returns as a halted loop.
4. Write `loop.sh` and `prompt.md` from the templates: DOC, DONE_TOKEN, ADD_DIRS (only
   the repos in scope), the tool preflight list; UTIL resolves to the sibling `util`
   checkout and the preflight fails fast without `pass-report.sh`. Add the `.gitignore`.
5. **Pre-check the allowlist** (point 11: denials are silent). Walk every command
   shape the ground rules prescribe — build, test, format, process-kill fallback,
   evidence archiving, bridge/wait scripts by ABSOLUTE path (a relative invocation
   of an allow-listed script stalled win-port's pass 1) — against
   `.claude/settings*.json` and add missing rules NARROWLY (literal first word /
   path prefix), never wildcards. `wait-for.sh` needs its own rule in the host
   repo's `.claude/settings.local.json` — `Bash(bash <util>/wait-for.sh *)`, never
   `bash <util>/*` (util holds push scripts; measured 2026-09-09: a pass without the
   rule was denied). Git needs no per-repo rule: the plain verbs are allow-listed
   once in the host repo and a sibling is reached by a standalone `cd` (point 12) —
   no `git -C <sibling> *` rules. Verify the driver statically too: the anchored
   token greps against the real index (0 hits), the NEXT ITEM grep, and
   `util/pass-report.sh` against any existing `logs/*.jsonl`. The live shakedown is
   the OWNER's (step 8): one run with `MAX_PASSES=1`, then read the pass's
   `.err`/`.jsonl` for denials. On a loop with an open sign-off queue that pass
   lands on the arming gate and exits 2 — that IS a successful shakedown, and its
   parked questions open step 8's round.
6. Seed the facts doc (or name an existing one) for durable output.
7. Commit everything, including a "pass 0" pass-log line recording the loop's creation.
8. **End scaffolding with the sign-off round.** Put the drafted standing sign-offs
   (and per-item verdicts where needed) to the owner and record the verdicts
   VERBATIM: a small, uncontentious set goes straight into the ground rules
   (win-port style); a larger or contentious one runs as a sign-off queue in
   `items.md` behind the arming gate (fifo style). Point NEXT ITEM at the first
   item only once the verdicts are in.

   Scaffolding STOPS there: report the loop armed, hand the owner the literal run
   command and a PASS-COUNT ESTIMATE (items × units per item at the chaining cap,
   plus baseline/SCOUT and gate-completion overhead, arithmetic shown) so they can
   size `MAX_PASSES` (×1.5–2 for headroom) and the spend. **Never execute `loop.sh`
   or a raw `claude -p` pass from a scaffolding or operating session**, not even as
   a shakedown (owner direction, 2026-08-16).

   The round need not finish in the session: the doc set is a legitimate **work in
   progress** — commit what is known and WAIT; the arming gate, not scaffolding's
   completeness, decides when looping starts. Adopt each arriving answer and commit
   it as an "arming update" pass-log line.

## Retargeting an existing driver

Change **three things in lockstep**: `DOC`, `DONE_TOKEN`, `prompt.md`. A DONE_TOKEN
that does not match what the new doc set will write **never fires**, and the loop keeps
spawning passes past the end of the work. Re-check ADD_DIRS and the preflight tool list
against the new subject's scope while there.

## Operating a running loop

- Launching is the owner's act, always: sessions scaffold, arm, answer halted
  questions and read logs, never run the driver.
- Watch: `tail -f` the newest file under `<loop-name>/logs/`; context trend in
  `<loop-name>/logs/context.log`, one line per pass (point 14).
- Exit 2 (halt): the driver prints the parked `OWNER QUESTION` lines. Answer them in
  the doc — verdicts VERBATIM — remove the halt token, rerun.
- Exit 1: read the newest `.err`/`.jsonl` pair before restarting; two consecutive
  failures usually mean a broken environment or a doc-set contradiction, not a flake.
- Knobs (env): `MODEL`, `MAX_PASSES`, `SLEEP_BETWEEN`, `PERMISSION_MODE`.
- One loop per build tree: passes treat a foreign running build as wait-don't-kill,
  so concurrent drivers on one tree don't corrupt it — they burn passes waiting.

## Feeding lessons back

A loop that discovers a new failure mode of the *pattern itself* (a denied command
shape, a gate that outgrew the pass, a false-hang diagnosis) records it in its own
ground rules — and the generalizable part is backported HERE (SKILL.md /
templates.md / the platform file), the way win-port's traps became `windows.md`;
otherwise the next scaffold re-learns it at pass-1 prices. When backporting,
DISPLACE words rather than append: state each rule once, in the one file whose
audience needs it, and trim what it supersedes — this skill has growth upkeep too.
