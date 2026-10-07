#!/usr/bin/env bash
# wait-for.sh — blocks until a regex appears in a file, or until a deadline.
#
#   bash /home/plq/src/arskom/amp/util/wait-for.sh <file> <regex> [timeout-seconds]
#
# Prints the matching line and exits 0 on a match, exits 1 on timeout (so
# a caller can tell "finished" from "still running"). Poll interval is
# 10 s; progress is echoed every minute so a long wait does not look hung.
#
# The sanctioned way for a headless handoff-loop pass to wait on a
# background build or gate it tee'd into a file (handoff-looping skill,
# contract point 7): a pass must block INSIDE its turn — ending the turn
# ends the session and kills the run, unrecorded — and the headless
# allowlist denies every ad-hoc polling shape (`until grep …; do sleep …;
# done`, `for i in $(seq …)`). Deliberately does nothing but poll a
# file: a mechanism fix, not a permission hole.
#
# Allowlist (per loop, narrow — never a bash wildcard over util/):
#   Bash(bash /home/plq/src/arskom/amp/util/wait-for.sh *)
# The ABSOLUTE path is the only invocation that matches; the relative
# form is denied (that denial, not a missing rule, stalled win-port-loop's
# pass 1).
set -uo pipefail

file="${1:?usage: wait-for.sh <file> <regex> [timeout-seconds]}"
regex="${2:?usage: wait-for.sh <file> <regex> [timeout-seconds]}"
timeout="${3:-540}"

waited=0
while [ "$waited" -lt "$timeout" ]; do
    if [ -f "$file" ] && grep -E -m 1 "$regex" "$file"; then
        echo "wait-for: matched after ${waited}s"
        exit 0
    fi
    sleep 10
    waited=$((waited + 10))
    if [ $((waited % 60)) -eq 0 ]; then
        echo "wait-for: ${waited}s, no match yet"
    fi
done

echo "wait-for: TIMEOUT after ${timeout}s with no match for '${regex}'" >&2
exit 1
