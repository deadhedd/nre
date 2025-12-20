# AGENTS.md — obsidian-note-tools

Guidance for AI coding assistants working in this repo. Keep changes **small, POSIX-safe, wrapper-first**, and **easy to revert**.

## Core principles

- **Wrapper-first execution:** all jobs run via `utils/core/job-wrap.sh`. Leaf scripts should assume the wrapper owns logging + lifecycle + commit.
- **POSIX `sh` (OpenBSD-friendly):** no Bash-isms unless explicitly requested.
- **No stdout leaks:** anything “log-like” goes to **stderr**. (Ideally: leaf scripts don’t log at all; wrapper does.)
- **ASCII-only output** in cron-captured logs.
- **No hacks/fallbacks** unless explicitly requested. Prefer correct, explicit behavior.

## Standard leaf script pattern

Every job/utility script should start like this (or match existing repo conventions):

```sh
#!/bin/sh
# <script> — <purpose>
# Author: deadhedd
set -eu
PATH="/usr/local/bin:/usr/bin:/bin:${PATH:-}"

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd -P)
job_wrap="$repo_root/utils/core/job-wrap.sh"
script_path="$script_dir/$(basename -- "$0")"

if [ "${JOB_WRAP_ACTIVE:-0}" != "1" ] && [ -x "$job_wrap" ]; then
  JOB_WRAP_ACTIVE=1 exec /bin/sh "$job_wrap" "$script_path" "$@"
fi
```

**Important:**

* Leaf scripts **MUST NOT** source `log.sh`.
* Leaf scripts **MUST NOT** define `log_info/log_warn/log_err` fallbacks.
* Leaf scripts should not depend on wrapper-only env like `LOG_FILE`/`LOG_LATEST_LINK`.

## Traps and lifecycle

* **Avoid `trap ... EXIT` in leaf scripts.** It can interfere with wrapper lifecycle if anything runs in-process.
* If cleanup is needed, prefer explicit cleanup at the end, or move cleanup responsibility into wrapper/core helpers.

## Paths & environment

* Default vault: `/home/obsidian/vaults/Main` (override with `VAULT_PATH`)
* Logs root: `/home/obsidian/logs`
* Prefer env overrides over hard-coded paths beyond these defaults.
* Use `printf`, not `echo`.

## What to read before editing

* `utils/core/job-wrap.sh`
* `utils/core/log.sh`
* `utils/core/commit.sh`
* The specific script you’re changing + any scripts it calls

## How to propose changes

In every response that modifies code:

1. **Plan:** 3–6 bullets: what changes, where, why.
2. **Diffs:** unified diffs (`git apply` compatible).
3. **Verify commands:** minimal, copy/paste-able.
4. **Rollback:** describe how to revert (or rely on `.bak` if used).

## Verification (minimum)

* `shellcheck` (with POSIX in mind)
* Run the job via wrapper:

  * `/bin/sh utils/core/job-wrap.sh <job> [args...]`
* Confirm:

  * no stdout noise
  * expected file outputs
  * wrapper log contains start + finish + exit code

## Security & privacy

* Never print secrets/tokens.
* Avoid logging sensitive absolute paths unless necessary.
* Prefer env vars for anything user-specific.

## Style notes

* Keep diffs minimal and reversible.
* Prefer clear, boring code over cleverness.
* Match existing naming/layout conventions in the repo.
