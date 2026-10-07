#!/usr/bin/env bash
# Drives the greet-loop loop: hardening the greet() example library in
# example/, one pass per iteration. Every iteration is a FRESH `claude -p`
# invocation: context resets each time; the doc set indexed by $DOC below
# is the only memory between passes. The per-pass prompt lives in
# prompt.md next to this script.
#
# This is the handoff-looping skill's worked example.
#
# ARMING: the doc set ships with an OPEN sign-off queue (S1, S2 in
# zai/greet-loop/items.md). The first run therefore stops at the
# ground rules' ARMING GATE: the pass parks the two questions in the
# index, writes the halt token and exits 2. Answer them on the VERDICT
# lines in items.md, in your own words, delete the halt token line from
# the index, rerun. In a loop you scaffold for real, that round happens
# in conversation before the first run — a premature pass only wastes a
# pass doing it.
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
# pass, the headless stand-in for /context, written by util/pass-report.sh
# after each pass. evidence/ holds archived test artifacts the passes
# save (both dirs are gitignored via this directory's .gitignore).

# -u/pipefail but NOT -e: a failed pass must not kill the driver — the
# consecutive-failure counter below decides when to stop.
set -u -o pipefail

MODEL="${MODEL:-opus}"
MAX_PASSES="${MAX_PASSES:-6}"
SLEEP_BETWEEN="${SLEEP_BETWEEN:-15}"
PERMISSION_MODE="${PERMISSION_MODE:-dontAsk}"

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )" # "
REPO="$( cd "$DIR/.." && pwd )"                 # the repo hosting the doc set
# The skill's template expects the shared helpers in a `util` checkout
# BESIDE the repo ($REPO/../util). This repo ships them itself, so the
# example points at its own copy; keep the template's line in your loop.
UTIL="$REPO/util"
DOC="$REPO/zai/greet-loop/index.md"
LOG_DIR="$DIR/logs"
EVIDENCE_DIR="$DIR/evidence"
PROMPT_FILE="$DIR/prompt.md"

DONE_TOKEN="GREET-LOOP-COMPLETE"
HALT_TOKEN="LOOP-HALT"

# Scope: everything this loop touches lives in this repo, so no
# --add-dir flags. A loop that reads or edits sibling checkouts lists
# them here (ONLY the repos the ground rules put in scope).
ADD_DIRS=()

# Fail fast on a broken environment: a pass without the toolchain cannot
# do anything except burn money diagnosing itself.
for t in claude cmake ctest cc; do
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
    echo "[loop] shared helper missing: $UTIL/pass-report.sh" >&2
    exit 1
fi
PROMPT=$(<"$PROMPT_FILE")

mkdir -p "$LOG_DIR" "$EVIDENCE_DIR"

add_dir_flags=()
for d in ${ADD_DIRS[@]+"${ADD_DIRS[@]}"}; do
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
        ${add_dir_flags[@]+"${add_dir_flags[@]}"}) >"$log" 2>"${log%.jsonl}.err"; then
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

    # Branch regime (ground rules): commits go on whatever branch this
    # clone has checked out. Commits stay LOCAL — the owner pushes.
done

echo "[loop] MAX_PASSES=$MAX_PASSES reached without $DONE_TOKEN — stopping for a human."
exit 1
