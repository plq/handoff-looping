# handoff-looping

A Claude Code skill for work that is too big for one session. A **handoff
loop** runs a backlog as a series of fresh, headless `claude -p` passes. Context
resets on every pass by design; the only thing that survives is a small set of
markdown documents committed to the repo, which each pass reads at startup and
updates before it stops. A shell script spawns the passes and reads the
documents to know when to stop.

The skill is described in the blog post
[Arayüzsüz Yapay Zekâ](https://burakarslan.com/blog/arayuzsuz-yapay-zeka/)
(Turkish).

## What is here

| Path | What |
|---|---|
| `.claude/skills/handoff-looping/` | the skill: `SKILL.md` (the contract), `templates.md` (file skeletons), `windows.md` (Git Bash + MSVC deltas) |
| `util/` | the two shared helpers every loop uses: `pass-report.sh` (driver side) and `wait-for.sh` (pass side) |
| `example/` | a tiny C library with CMake and ctest, the subject of the example loop |
| `greet-loop/` | the example loop's driver: `loop.sh`, `prompt.md`, `.gitignore` |
| `zai/greet-loop/` | the example loop's doc set: `index.md`, `ground-rules.md`, `items.md` |
| `zai/greet-facts.md` | the example's durable facts document |
| `CLAUDE.md` | the project rules a pass inherits here; your repo needs equivalents (see below) |
| `.claude/settings.json` | the permission allowlist the example's headless passes run under |

`zai/` is the directory this skill keeps assistant-maintained documents in.
Nothing depends on the name; rename it in your own repo.

## Running the example

Prerequisites: the Claude Code CLI (`claude`), cmake, ctest and a C compiler on
PATH. `jq` is optional (the pass report falls back to python).

```sh
git clone https://github.com/plq/handoff-looping
cd handoff-looping
bash greet-loop/loop.sh
```

`zai/greet-loop/items.md` holds two small items against `example/src/greet.c`
and a sign-off queue of two questions the owner has to answer first. So the
first run is the **sign-off round**: the pass finds the queue open, parks the
two questions in `zai/greet-loop/index.md`, writes the halt token and the
driver exits with code 2, printing the questions. Answer them on the `VERDICT:`
lines in `items.md`, in your own words (one line each is plenty), delete the
`> LOOP-HALT` line from the index, and run the driver again.

From there the loop is armed. Each pass reads the doc set, adds a failing test,
fixes the code, runs the suite, commits locally and aims the next pass. Expect
three or four passes in all, the first being the halted one; the driver stops
by itself when the index carries the completion token. Watch with
`tail -f greet-loop/logs/<newest>.jsonl`; `greet-loop/logs/context.log` has one
context-size line per pass.

When Claude scaffolds a loop for you with this skill, the sign-off round happens
in conversation before the first run and the loop starts armed. The example has
no scaffolding session, so its first pass asks the questions instead. The
blanket permissions the items do not need a question for are already in
`zai/greet-loop/ground-rules.md` as standing sign-offs.

Commits land on the clone's current branch and are never pushed. To rerun from
scratch, reset the clone.

## How the example loop was made

A loop starts as one paragraph handed to the skill. The request that produces
`greet-loop/` and `zai/greet-loop/` from the files in `example/` reads like
this:

```text
/handoff-looping example/ holds a one-function C library, greet(), built
with CMake and tested with ctest. Set up a loop that hardens it: a NULL
or empty name should greet a stranger instead of printing "(null)", and
whitespace around the name should be ignored. Test-first, one commit per
item, no new dependencies, and don't touch anything outside example/ and
the loop's own documents. Ask me whatever needs my sign-off before it
runs.
```

The session walks the code, turns the paragraph into the two items and the
standing sign-offs, writes the driver and the doc set, then opens the
sign-off round with the questions it could not settle itself. This repo's
copy was written out by hand from the skill's templates so that it ships
with the questions still open; the paragraph above is the request it stands
in for.

## Using it in your own repo

1. Copy `.claude/skills/handoff-looping/` into your repo's `.claude/skills/`.
2. Put `util/` where the templates expect it: a checkout **beside** your repo
   (`../util`). The example points its driver at `./util` instead; the comment
   in `greet-loop/loop.sh` marks the line.
3. Make sure your `CLAUDE.md` says what the templates lean on: builds through
   cmake, tests through ctest, no command substitution in shell commands,
   failing test first, durable facts recorded in repo documents, commits per
   concern. This repo's `CLAUDE.md` is a starting point.
4. Ask Claude to scaffold a loop. The skill writes the doc set and the driver,
   ends with a sign-off round, and hands you the run command. Running the
   driver is always yours to do.

The templates assume a CMake/ctest project; other build systems need the build
and test how-to sections rewritten.

## License

See `LICENSE`.
