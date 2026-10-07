# Greet-loop loop — INDEX

The loop that hardens `greet()`, the example library in `example/`: two
items, G1 (NULL or empty name) and G2 (surrounding whitespace), each a
failing-test-first fix. There is no separate plan of record — the items
in `items.md` carry the whole analysis. Driver: `greet-loop/loop.sh`
(this repo) — a fresh `claude -p` per pass; THIS doc set is the only
inter-pass memory.

## Reading order (STARTUP, nothing more)

1. `ground-rules.md` (next to this file) — the protocol, every pass.
   Its ARMING GATE comes before everything.
2. The ONE item section in `items.md` that the NEXT ITEM pointer below
   names — whatever it names now.
3. The subject files that item's "reads" line names — nothing else.
4. This repo's `CLAUDE.md`.

## Status

NEXT ITEM: (NOT ARMED — sign-off round pending: S1, S2 in items.md)

Created 2026-10-07. Not armed: two questions wait for the owner in the
sign-off queue of `items.md`; the standing sign-offs in
`ground-rules.md` cover everything else. The first pass parks them here
and halts; the owner answers in `items.md`, removes the halt token
below, reruns. Baseline gate measured green at creation (2 cases).

## Owner questions (parking area)

(none parked)

## Tokens (the driver greps this file — never reproduce the shapes early)

- Completion: when the LAST item closes AND gate-G has run fully green in
  that pass, the pass writes the completion token — the string
  GREET-LOOP-COMPLETE alone on its own line — at the top of this file.
  The driver matches whole lines only, so the mid-sentence mentions in
  this section never fire.
- Halt: only when NO item is actionable (not armed, all blocked or all
  done), park
  the pending question(s) as standalone "OWNER QUESTION (…):" blockquote
  lines above, then add a blockquote line holding the halt token — the
  string LOOP-HALT alone on that line, optionally after "> " — commit,
  stop. The driver exits 2 on that exact shape.

## Pass log (newest first; `> -` prefixed lines, ≤3 sentences, cap ~10)

> - 2026-10-07 pass 0 (creation): doc set created — ground rules with
>   standing sign-offs 1–4, items G1–G2, sign-off queue S1–S2, driver
>   `greet-loop/loop.sh`. NOT armed; owner verdicts next. Baseline
>   gate-G: greet.basic, greet.truncation, both green.
