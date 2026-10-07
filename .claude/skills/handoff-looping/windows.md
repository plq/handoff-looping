# Handoff loops on Windows (Git Bash + MSVC)

Distilled from the win-port loop — the Windows test-port loop, run to completion
(all seven items closed green; doc set at `zai/win-port-loop/`). Its driver scripts
are retired from the tree and live on, generalized, as the templates below. Read
this AFTER `SKILL.md` and `templates.md`; everything here is a delta on them.

## Why Windows needs a specialization

1. **The toolchain is not on PATH.** cmake/ctest/ninja/cl/clang-format live inside
   Visual Studio, and `cl` additionally needs the vcvars compile environment
   (INCLUDE/LIB/…), not just PATH. The driver must import that environment once and
   let every `claude -p` child inherit it.
2. **The headless allowlist bites harder.** Several command shapes a pass would
   naturally write are denied on this setup, and a denied call in a headless pass is
   a wasted pass. The fix is *sanctioned scripts* invoked by absolute path: `tool.sh`
   in the (allow-listed) loop directory and the shared `util/wait-for.sh`.
3. **Version and semantics skews** (clang-format 19 vs the repo's 20, POSIX-vs-Win32
   file semantics, `-k 0` passthrough) that silently corrupt work unless the ground
   rules call them out.

A Windows loop therefore carries **four extra files** next to `loop.sh`:

| File | Role |
|---|---|
| `msvc-env.sh` | imports the vcvars64 environment into the driver's bash shell |
| `vcenv.bat` | cmd-side helper: `call vcvars64.bat` then `set` (dump the env) |
| `env-check.sh` | preflight: prints the tool-resolution table, checks INCLUDE/LIB |
| `tool.sh` | sanctioned bridge: run ONE build/test tool inside the imported env |

The sanctioned wait, `wait-for.sh`, is shared: it lives in the sibling `util/`
checkout (SKILL.md, anatomy) and is invoked by absolute path. The templates below
are the win-port loop's scripts with loop-specific strings generalized — create them
in the new loop's directory and adjust.

## The environment import — `msvc-env.sh` + `vcenv.bat`

Mechanism: bash calls `vcenv.bat` through `cmd //c`; the .bat calls `vcvars64.bat`
and dumps `set`; bash parses the dump, re-exporting the compile-environment
variables verbatim and converting PATH wholesale with `cygpath -up` (which keeps
git, claude and coreutils that the shell already had). Two details are load-bearing:

- **The .bat indirection is not optional**: cmd.exe does not reliably parse a
  compound quoted command (`call "..." && set`) passed from bash, and the .bat must
  sit on a **space-free path** (the loop dir qualifies; Program Files does not).
- **Only PATH gets converted.** INCLUDE/LIB and friends are read by Windows
  processes only; msys converts nothing but PATH-like variables, so they pass
  through verbatim.
- **Prepend a real python too.** On a stock Windows PATH, bare `python` resolves to
  the Microsoft Store alias stub in WindowsApps, which prints an install nag instead
  of running — and `command -v python` still finds it, so loop.sh's jq-fallback
  result printer silently breaks (measured 2026-08-14 on an earlier loop). Add the
  machine's real python dir to the PATH-prepend line in msvc-env.sh and to the
  driver/env-check preflights.

`vcenv.bat`:

```bat
@echo off
rem Dumps the environment after vcvars64 — consumed by msvc-env.sh, which
rem cannot pass a compound quoted command through cmd.exe reliably.
call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" >NUL 2>&1
set
```

`msvc-env.sh` (re-verify the three tool-dir locations on a new machine — they are
VS-install-specific; the dated comment in the live copy records where they were
found):

```bash
# Imports the MSVC (vcvars64) environment into the current bash shell so
# plain `cmake` / `ctest` / `ninja` / `cl` / `clang-format` resolve — the
# toolchain lives inside Visual Studio and is NOT on a stock PATH.
# Sourced by loop.sh before the first pass; every `claude -p` child (and
# its Bash tool calls) inherits the result. Safe to source more than
# once. Verify with env-check.sh next to this file.
CMAKE_BIN='/c/Program Files/Microsoft Visual Studio/2022/Community/Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin'
NINJA_BIN='/c/Program Files/Microsoft Visual Studio/2022/Community/Common7/IDE/CommonExtensions/Microsoft/CMake/Ninja'
LLVM_BIN='/c/Program Files/Microsoft Visual Studio/2022/Community/VC/Tools/Llvm/x64/bin'

msvc_env() {
    local here vcenv winpath k v

    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*) ;;
        *) return 0 ;; # not Windows — nothing to import
    esac

    here="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    vcenv="$(cmd //c "$(cygpath -w "$here/vcenv.bat")" | tr -d '\r')" || return 1

    # cl's compile environment: pass through verbatim. Only Windows
    # processes read these, and msys converts nothing but PATH-like
    # variables, so no translation is needed.
    while IFS='=' read -r k v; do
        case "$k" in
            INCLUDE|LIB|LIBPATH|Platform|UCRTVersion|UniversalCRTSdkDir) export "$k=$v" ;;
            VCINSTALLDIR|VCToolsInstallDir|VCToolsVersion|VSINSTALLDIR|DevEnvDir) export "$k=$v" ;;
            WindowsSdkDir|WindowsSDKVersion|WindowsSdkBinPath|WindowsSdkVerBinPath) export "$k=$v" ;;
            VSCMD_ARG_HOST_ARCH|VSCMD_ARG_TGT_ARCH|VSCMD_VER) export "$k=$v" ;;
        esac
    done <<<"$vcenv"

    # vcvars' PATH = its tool dirs prepended to the inherited PATH, so
    # converting it wholesale keeps everything the shell already had
    # (git, claude, coreutils, ...).
    winpath="$(printf '%s\n' "$vcenv" | sed -n 's/^[Pp][Aa][Tt][Hh]=//p' | head -n 1)"
    if [[ -n "$winpath" ]]; then
        PATH="$(cygpath -up "$winpath")"
    fi
    export PATH="$CMAKE_BIN:$NINJA_BIN:$LLVM_BIN:$PATH"

    # The Claude Code CLI installs to ~/.local/bin (claude.exe), which a
    # stock Git Bash does not have on PATH.
    if [[ -d "$HOME/.local/bin" ]]; then
        export PATH="$HOME/.local/bin:$PATH"
    fi
}

msvc_env
```

## Preflight — `env-check.sh`

Run after toolchain moves/updates and before first use of `loop.sh` on a new
machine. Note the INCLUDE/LIB check: `cl` resolving on PATH is NOT sufficient — it
needs the imported compile environment or every compile fails.

```bash
#!/usr/bin/env bash
# Sanity check for the pass environment: sources msvc-env.sh and reports
# what resolves.
. "$(dirname "${BASH_SOURCE[0]}")/msvc-env.sh"

rc=0
for t in cmake ctest ninja cl clang-format nproc git claude; do
    if command -v "$t" >/dev/null 2>&1; then
        printf 'ok      %-14s %s\n' "$t" "$(command -v "$t")"
    else
        printf 'MISSING %s\n' "$t"
        rc=1
    fi
done

# jq is optional: loop.sh extracts each pass's result with jq when
# present, python otherwise.
command -v jq >/dev/null 2>&1 || echo "note    jq not found (optional; python fallback in use)"

# cl needs the imported compile environment, not just PATH.
if [[ -z "${INCLUDE:-}" || -z "${LIB:-}" ]]; then
    echo "MISSING INCLUDE/LIB (vcvars import failed — cl would not compile)"
    rc=1
fi
exit $rc
```

## The tool bridge — `tool.sh`

A `loop.sh`-run pass inherits the imported environment. A pass started ANY other way
(interactively, or a hand-rerun of the prompt) gets a stock shell where `cmake` does
not resolve at all — and the pass cannot import the environment itself: bash state
does not survive between tool calls, and a `. msvc-env.sh && cmake ...` compound is
not on the permission allowlist. The bridge sources the env itself, so the pass runs
every tool through it:

```bash
#!/usr/bin/env bash
# Runs ONE build/test tool inside the imported MSVC environment.
#
#   bash <abs-repo-path>/<loop-name>/tool.sh cmake --build build/<BD> -j 8
#   bash <abs-repo-path>/<loop-name>/tool.sh ctest --test-dir build/<BD> -N
#
# Deliberately NOT a general `exec "$@"` shim: only tools the permission
# allowlist already grants by name get through, so this stays a PATH fix
# and not a permission hole.
set -euo pipefail

. "$( dirname "${BASH_SOURCE[0]}" )/msvc-env.sh"

case "${1:-}" in
    cmake|ctest|ninja|clang-format) ;;
    *)
        echo "tool.sh: refusing '${1:-}' — allowed: cmake ctest ninja clang-format" >&2
        exit 64
        ;;
esac

exec "$@"
```

Two rules that MUST make it into the loop's ground rules verbatim:

- **Absolute path only.** The allowlist rule is
  `Bash(bash <abs-repo-path>/<loop-name>/*)` (in `.claude/settings.local.json` —
  add it when scaffolding), so the relative form `bash <loop-name>/tool.sh ...` does
  NOT match and is DENIED. That denial, not a missing rule, is what stalled
  win-port-loop's pass 1.
- **Extending the allowed-tool list is a permission decision**: each added tool must
  already be granted by name in the allowlist, or the bridge becomes a hole.

## Sanctioned waiting — `util/wait-for.sh`

The ground rules require a pass to put long builds/suites in the BACKGROUND and
still wait on them and record the result in the SAME pass — a pass that ends its
turn waiting loses the run. But the headless permission mode denies every ad-hoc
blocking shape a pass writes by hand (`until grep -q ...; do sleep 5; done`,
`for i in $(seq ...)`), and CLAUDE.md forbids command substitution. The sanctioned
wait is `wait-for.sh` in the sibling `util/` checkout — its header is the contract;
invoke it by ABSOLUTE path under its per-script allowlist rule (SKILL.md,
scaffolding step 5). Nothing about it is Windows-specific: the denials were merely
measured here first.

## Driver deltas (`loop.sh` against the platform-neutral template)

- Header: note the loop runs from **Git Bash**, and that `msvc-env.sh` provides the
  toolchain ("verify the environment with env-check.sh before first use on a new
  machine").
- Source the environment before the preflight: `. "$DIR/msvc-env.sh"` — the
  preflight then genuinely tests what passes will inherit.
- Preflight adds `cl` (and any other MSVC-only tool the loop needs); on failure it
  says "not on PATH **after sourcing msvc-env.sh** — run env-check.sh". The
  fail-fast is not theoretical: win-port-loop's pass 1 spent $3 reporting "no
  cmake" before the preflight existed.

## Ground-rules content for a Windows loop

The per-loop `ground-rules.md` "Build & test how-to" section must carry these (all
measured on win-port-loop; re-verify dated facts when scaffolding a new loop):

- **Bash tool EXCLUSIVELY, never PowerShell** — the driver is bash, the imported
  environment and the allowlist are built for bash command shapes; a PowerShell call
  under the headless permission mode just gets denied and wastes the pass.
- **Every tool through the bridge, by absolute path** (see tool.sh above), for
  passes not started by the driver.
- **Denied shapes to route around** (check the loop's actual allowlist and record
  the loop's own list):
  - redirecting to a file (`cmd > log`) — use `| tee log` instead;
  - `rm`/`mv` have no allowlist rule — delete through the sanctioned build driver:
    `cmake -E rm -f <paths>` via the bridge;
  - `git -C <repo>` and `cd <repo> && git …` chains — as on Linux, git runs plain
    after a standalone `cd` into the repo (SKILL.md, contract point 12).
- **`cmake --build` does not accept ninja's `-k 0`** (keep-going — a census wants it
  to collect EVERY compile error). Written as `cmake --build <BD> -j 8 -k 0` it
  prints its usage text and **exits 0** — indistinguishable from a clean build
  unless you read the output. Pass it through: `... -j 8 -- -k 0`.
- **clang-format is VS's LLVM copy and may be a major version behind the repo's**
  (19.1.5 vs 20 when measured): it rewraps unrelated already-formatted code — after
  running it, `git diff` the file and REVERT every hunk you did not touch. A
  clang-format path the host repo's CLAUDE.md gives for Linux does not exist on
  Windows; the ground rules name the Windows one.
- **Process-kill fallback** for the end-of-pass protocol: TaskStop first, then
  `taskkill //F //IM ctest.exe` from Git Bash (double slashes — msys eats single
  ones).
- **Budget notes that prevent false "it hung" diagnoses**:
  - a full reconfigure can cost minutes when a heavyweight step dominates (v8's
    `gn gen` took 80 s–4 min) — budget for it, it is not hung;
  - ctest schedules longest-first from recorded cost data, so a fresh run can look
    stalled for its first ~10 minutes;
  - a generated per-test `TIMEOUT 3600` beats `ctest --timeout` on the command
    line — the flag neither protects nor threatens a slow case;
  - warm and cold `testwd` runs are DIFFERENT measurements — record which one a
    timing came from.
- **When a full gate outgrows the pass budget, say so honestly.** Win-port-loop's
  full-registry gate grew from ~30 min to hours; the ground rules were rewritten to
  make per-suite gate-A baselines the recorded substitute, with the explicit
  instruction to say "all cases green by per-suite gate-A" and never "gate-W is
  green" when the full gate has not actually run. Any loop whose gate can grow must
  keep its gate section's cost figures current (each closing item updates them) and
  must never let a pass die trying to run a gate that no longer fits.
- **POSIX-vs-Win32 file semantics**: a test that operates on still-open files
  (unlink/rename/replace while a handle is live) is tolerated on POSIX and an error
  on Windows. Decide the loop's disposition rule for these up front (win-port-loop:
  gate the case out with an in-code comment naming the rule, tag the record
  `posix-file-semantics`, fix separately outside the loop) so passes don't
  re-litigate it.

## Scaffolding checklist (Windows deltas only)

1. Create the four scripts from the templates above in `<loop-name>/`; keep
   `loop.sh` + `prompt.md` + `.gitignore` from `templates.md`.
2. Re-verify the tool-dir paths in `msvc-env.sh` and the vcvars64 path in
   `vcenv.bat` against the machine's VS install; date the verification in the
   comment.
3. Add the bridge allowlist rule to `.claude/settings.local.json`:
   `Bash(bash <abs-repo-path>/<loop-name>/*)` — beside the rule for
   `util/wait-for.sh` (SKILL.md, scaffolding step 5), with the util checkout's
   WINDOWS absolute path.
4. Run `bash <loop-name>/env-check.sh` until it prints a full `ok` table.
5. Apply the driver deltas (source msvc-env.sh; `cl` in the preflight).
6. Write the ground-rules "Windows build & test how-to" from the section above,
   with the loop's own measured paths, costs and denial list.
