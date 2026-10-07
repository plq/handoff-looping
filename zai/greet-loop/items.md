# Greet-loop loop items

Working state only — an item's section is DELETED when it closes
(ground rules, growth upkeep); durable output goes to
`zai/greet-facts.md`. These items are the plan of record — every claim
and line number here is a hypothesis; re-measure before acting.

## Order

NOT ARMED — sign-off round pending (S1 and S2 below need a VERDICT).
Intended order after arming: G1, then G2. G2's rule for a blank name
builds on G1's rule for an empty one.

## G1 — NULL or empty name greets a stranger (OPEN, verdict pending: S2)

- reads: `example/src/greet.h` (the contract comment),
  `example/src/greet.c`, `example/tests/test_greet.c`,
  `example/CMakeLists.txt`.
- WHAT: `greet(NULL, out, n)` hands NULL to `%s` — "Hello, (null)!" on
  glibc, undefined behaviour elsewhere; `greet("", out, n)` yields
  "Hello, !". Wanted: both produce "Hello, stranger!" and return its
  length, 16.
- FIX SHAPE: in `greet()`, substitute "stranger" when `name` is NULL or
  `*name == '\0'`, before the snprintf. State the rule in the greet.h
  comment. Where the "stranger" literal lives is S2's call.
- PIN: cases `null` and `empty` in `test_greet.c` (dispatch on argv[1]
  like the existing ones) plus their `add_test` lines `greet.null` /
  `greet.empty`; each asserts the text and the returned length. Run
  them red before the fix.

## G2 — Surrounding whitespace in the name is ignored (OPEN, verdict pending: S1)

- reads: the same four files as G1, plus G1's condensed record in
  `zai/greet-facts.md`.
- WHAT: `greet("  Ada  ", out, n)` yields "Hello,   Ada  !". Wanted:
  "Hello, Ada!" — leading and trailing whitespace is dropped; which
  characters count as whitespace is S1's call. A name that is only
  whitespace counts as empty and falls under G1's rule
  ("Hello, stranger!"); that is why G1 goes first.
- FIX SHAPE: trim by pointer arithmetic over the input (no allocation,
  no mutation of the caller's string) and format with a `%.*s`
  precision. Keep the snprintf return-value contract.
- PIN: cases `whitespace` ("  Ada  " → "Hello, Ada!", length 11) and
  `blank` ("  \t " → "Hello, stranger!", length 16), with `add_test`
  lines `greet.whitespace` / `greet.blank`. Run them red before the fix.

## Sign-off queue (each needs an owner verdict BEFORE the loop is armed)

### S1 — What counts as whitespace for G2 (PROPOSED)

- CONTEXT: G2 trims the name. The item says "spaces and tabs"; the
  owner has not said whether a newline or other C whitespace counts.
  The choice changes the `blank` test and the trim loop.
- OPTIONS: (a) space and tab only — a hand-written check, no header;
  (b) everything `isspace()` accepts (adds \n \r \v \f) — one include,
  `<ctype.h>`; (c) Unicode spaces too — needs a library, out of scope
  for this example.
- VERDICT: (owner fills in: approved / rejected / modified — in the
  owner's words)

### S2 — Where the "stranger" fallback lives (PROPOSED)

- CONTEXT: G1 introduces the literal "Hello, stranger!". Its tests
  must spell the expected text, and standing sign-off 1 parks any
  change to the public header beyond the contract comment.
- OPTIONS: (a) a `GREET_STRANGER` macro in `greet.h`, used by greet.c
  and the tests — a public API addition; (b) a `static const char` in
  `greet.c`, the tests repeat the literal — no API change.
- VERDICT: (owner fills in: approved / rejected / modified — in the
  owner's words)
