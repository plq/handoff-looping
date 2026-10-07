# Notes for Claude

- **Important**: keep bash commands statically checkable so they don't trip a
  permission prompt (a prompt is the last resort!!!): no command substitution
  (`$(...)`), no `cd` to a parent, absolute paths inside the allowed roots, one
  command per working directory rather than one spanning several. The allowed
  roots are in `.claude/settings*.json`.

- you MUST use cmake to drive builds and ctest to drive tests. don't try to run
  binaries directly, ctest knows how run binaries.

  cmake --build knows how to parallelize, ctest doesn't. pass -j`nproc` to ctest
  when applicable

- you MUST record durable facts, findings and lessons learnt in repo documents
  (e.g. `zai/greet-facts.md` — the facts document for the example library),
  not in assistant-local memory

- Always commit to whatever branch the current repo is, even when it's master.
  Trust that the owner must have set up the right branch to work on.

- NEVER amend or otherwise rewrite a commit that exists on the remote. The
  owner may push at any time between your commits, so check the upstream state
  (`git status -sb`) immediately before EVERY `commit --amend` / `reset` /
  squash -- not once per task. If the commit is on origin, add a follow-up
  commit instead; if local history has already diverged from a pushed commit,
  rebuild as origin/HEAD plus new commits (append-only), never by force.

- In a long running task, proceed by committing any meaningful chunk of work,
  together with its tests if applicable, as you progress through it. Commits
  must not span multiple concerns
