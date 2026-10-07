#!/usr/bin/env bash
# pass-report.sh — the per-pass report a handoff-loop driver prints after
# each `claude -p` pass (handoff-looping skill, contract points 6 and 14).
# Driver-side only: the OWNER's loop.sh calls it, never a pass, so it
# needs no permission allowlist.
#
#   bash /home/plq/src/arskom/amp/util/pass-report.sh <pass.jsonl> <index.md> [<pass-no>] [<context.log>]
#
# Prints, in order:
#   1. the pass's result text — the `result` field of the transcript's
#      final "type":"result" line (an error pass carries only
#      subtype/errors; those are printed compactly, never the raw line);
#   2. the newest pass-log entry of the index — the `> - ` line plus its
#      `>   ` continuation lines. This is the RELIABLE handoff record;
#      the model's closing text above it is best-effort;
#   3. the context report — the headless stand-in for /context, which a
#      pass cannot run (a REPL command, not a tool). The input side of
#      the LAST assistant message (cache read + created + uncached) is
#      the context the pass ended with, shown against the main model's
#      window (the result line's modelUsage) with the pass's turns,
#      output tokens and cost. The same line is appended to
#      <context.log> (default: context.log next to the transcript), one
#      per pass, so the TREND reads at a glance: a rising end-of-pass
#      figure means startup reading (growth upkeep slipping) or unit
#      size/chaining is outgrowing the window — tighten the doc set or
#      the chaining cap before passes start dying full.
#
# jq when present, python otherwise (python3 first: on a stock Windows
# PATH bare `python` may be the Store stub — see the skill's windows.md).
# Always exits 0: a report failure must never count as a pass failure.
set -uo pipefail

usage="usage: pass-report.sh <pass.jsonl> <index.md> [<pass-no>] [<context.log>]"
log="${1:?$usage}"
doc="${2:?$usage}"
pass="${3:-?}"
ctx_log="${4:-$(dirname "$log")/context.log}"

have_jq=0
if command -v jq >/dev/null 2>&1; then have_jq=1; fi
py=""
for candidate in python3 python; do
    if command -v "$candidate" >/dev/null 2>&1; then py="$candidate"; break; fi
done

# --- 1. result ---------------------------------------------------------
result_line="$(grep '"type":"result"' "$log" | tail -n 1)"
echo "[loop] pass $pass result:"
if [[ -z "$result_line" ]]; then
    echo "  (no result line in the transcript)"
elif ((have_jq)); then
    printf '%s\n' "$result_line" \
        | jq -r '.result // "[\(.subtype // "?")] \((.errors // []) | join("; "))"' || true
elif [[ -n "$py" ]]; then
    printf '%s\n' "$result_line" | PYTHONIOENCODING=utf-8 "$py" -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
print(d.get("result") or "[%s] %s"
      % (d.get("subtype", "?"), "; ".join(d.get("errors", []))))
' || true
else
    printf '%s\n' "$result_line"
fi

# --- 2. newest pass-log line -------------------------------------------
echo "[loop] newest pass-log line:"
awk '/^> - / { if (seen) exit; seen = 1; print; next }
     seen { if (/^>   /) print; else exit }' "$doc" || true

# --- 3. context report -------------------------------------------------
last_asst="$(grep '"type":"assistant"' "$log" | tail -n 1)"
if [[ -z "$last_asst" ]]; then
    ctx_line="no assistant message in the transcript"
elif ((have_jq)); then
    ctx_line="$(printf '%s\n%s\n' "$last_asst" "$result_line" | jq -r -s '
        (.[0].message.usage // {}) as $u
        | (($u.input_tokens // 0) + ($u.cache_creation_input_tokens // 0)
           + ($u.cache_read_input_tokens // 0)) as $ctx
        | ((.[1].modelUsage // {}) | to_entries
           | map(select(.value.contextWindow != null))
           | max_by((.value.cacheReadInputTokens // 0) + (.value.inputTokens // 0))
           // {key: "?", value: {contextWindow: null}}) as $m
        | (if $m.value.contextWindow
           then " = \($ctx * 100 / $m.value.contextWindow | round)% of the \($m.key) window (\($m.value.contextWindow))"
           else "" end) as $pct
        | "\($ctx) tokens in context at the end\($pct); "
          + "cache read \($u.cache_read_input_tokens // 0), created \($u.cache_creation_input_tokens // 0), uncached \($u.input_tokens // 0); "
          + "\(.[1].num_turns // "?") turns, \(.[1].usage.output_tokens // "?") output tokens, $\(.[1].total_cost_usd // 0 | . * 100 | round / 100)"')"
elif [[ -n "$py" ]]; then
    ctx_line="$(printf '%s\n%s\n' "$last_asst" "$result_line" | PYTHONIOENCODING=utf-8 "$py" -c '
import json, sys
lines = sys.stdin.read().splitlines() + ["", ""]
try:
    u = json.loads(lines[0])["message"]["usage"]
    r = json.loads(lines[1]) if lines[1] else {}
except Exception:
    sys.exit(0)
i, c, rd = (u.get(k) or 0 for k in ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"))
ctx = i + c + rd
models = [(k, v) for k, v in (r.get("modelUsage") or {}).items() if v.get("contextWindow")]
pct = ""
if models:
    k, v = max(models, key=lambda kv: (kv[1].get("cacheReadInputTokens") or 0) + (kv[1].get("inputTokens") or 0))
    pct = " = %d%% of the %s window (%d)" % (round(ctx * 100 / v["contextWindow"]), k, v["contextWindow"])
print("%d tokens in context at the end%s; cache read %d, created %d, uncached %d; %s turns, %s output tokens, $%.2f"
      % (ctx, pct, rd, c, i, r.get("num_turns", "?"), (r.get("usage") or {}).get("output_tokens", "?"), r.get("total_cost_usd") or 0))
')"
else
    ctx_line="(install jq or python for the context report)"
fi
echo "[loop] context at end of pass: $ctx_line"
printf '%s\tpass %s\t%s\n' "$(date -Is)" "$pass" "$ctx_line" >>"$ctx_log" || true

exit 0
