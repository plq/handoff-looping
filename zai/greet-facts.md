# greet() — facts

Durable facts about the example library in `example/`. The greet-loop
loop condenses each closed item into a record here (≤8 lines) and
deletes its working section from `zai/greet-loop/items.md`. Facts that
stop being true are corrected in place.

## Contract (as of 2026-10-07, before the loop ran)

- `size_t greet(const char *name, char *out, size_t n)` writes
  "Hello, <name>!" into `out`, NUL-terminated when `n > 0`, truncated
  when it does not fit, and returns the length of the FULL greeting (the
  snprintf convention) so callers can detect truncation.
- Pinned by `greet.basic` and `greet.truncation` in
  `example/tests/test_greet.c`.

## Closed items

(none yet)
