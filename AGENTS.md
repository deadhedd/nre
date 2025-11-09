# AGENTS.md

> Guidance for AI coding assistants working in this repository.
> Audience: GitHub Copilot Chat, ChatGPT, Sourcegraph Cody, Continue, et al.

## Purpose

This file tells AI assistants how to propose, implement, and verify changes in **obsidian-note-tools** without breaking automated note workflows.

---

## TL;DR (follow this every time)

1. **Read before you edit:** `generate-daily-note.sh`, `generate-weekly-note.sh`, `utils/`,and cron docs below.
2. **Propose first:** Outline the plan and list files to touch. Prefer minimal, reversible diffs.
3. **Keep it POSIX-sh:** Use portable shell (no Bash-isms unless explicitly stated).
4. **Log everything:** Use `job-wrap.sh` (or compatible logging) and avoid emoji in cron-captured logs.
5. **Don’t leak secrets:** Never print tokens/paths that reveal private info; use env vars.
6. **Ship diffs:** Provide unified diffs (`git apply` compatible) and any new file contents.
7. **Verify:** Include commands to lint, shellcheck, dry-run, and schedule via cron wrapper.

---

## Repo quick facts

* **Primary language:** POSIX `sh` (OpenBSD compatible)
* **Vault default path:** `/home/obsidian/vaults/Main` (override with `VAULT_PATH`)
* **Periodic notes:** `Periodic Notes/Daily Notes/`, `Periodic Notes/Weekly Notes/`, `Periodic Notes/Monthly Notes/`, `Periodic Notes/Quarterly Notes/`, and `Periodic Notes/Yearly Notes/`
* **Logging root:** `/home/obsidian/logs`
* **Cron wrapper:** `utils/job-wrap.sh`
* **Author tag:** `deadhedd`
* **ASCII-only output preference** for OpenBSD TTY logs

---

## Files to read first

> Note: Files in the `legacy/` directory are deprecated and should be ignored unless a task explicitly requires referencing or migrating them.

* `generate-daily-note.sh`
* `generate-weekly-note.sh`
* `utils/job-wrap.sh`
* `utils/commit.sh`
* `utils/` (other helpers)

---

## Environment & invariants

* `PATH="/usr/local/bin:/usr/bin:/bin:${PATH:-}"`
* Respect `VAULT_PATH` if set; default `/home/obsidian/vaults/Main`
* **Never hard-code** paths beyond documented defaults.
* `set -eu` required for strict error handling.
* Use `printf` for logs, not `echo`.
* No color codes/non-ASCII output in cron logs.
* Network calls should be opt-in via env vars and fail soft.

---

## Cron & logs

> Note: Cron jobs are staggered by 2-minute intervals to respect cascading dependencies between note generations. Preserve this order when adding or adjusting jobs. (reference)

```cron
SHELL=/bin/sh
PATH=/usr/local/bin:/usr/bin:/bin
HOME=/home/obsidian
MAILTO=obsidian

10 0 * * * /bin/sh /home/obsidian/obsidian-note-tools/utils/job-wrap.sh daily-note \
  /home/obsidian/obsidian-note-tools/generate-daily-note.sh >>/home/obsidian/logs/cron.log 2>&1

8 0 * * 1 /bin/sh /home/obsidian/obsidian-note-tools/utils/job-wrap.sh weekly-note \
  /home/obsidian/obsidian-note-tools/generate-weekly-note.sh >>/home/obsidian/logs/cron.log 2>&1
```

---

## Coding standards

* POSIX `sh` only. Test with `dash` or OpenBSD `ksh -p`.
* File header example:

  ```sh
  #!/bin/sh
  # utils/<name>.sh — <purpose>
  # Author: deadhedd
  # License: MIT
  set -eu
  ```
* Logging helpers:

  ```sh
  log_info() { printf 'INFO %s\n' "$*"; }
  log_warn() { printf 'WARN %s\n' "$*"; }
  log_err()  { printf 'ERR %s\n'  "$*"; }
  ```
* Quote variables, use `--` before paths, avoid interactive prompts.

---

## Commit & PR style

* Use Conventional Commits: `feat:`, `fix:`, `refactor:`, `docs:`, `chore:`, `test:`
* Keep PRs small and include:

  * Context/problem solved
  * Diff preview
  * Verify commands
  * Roll-back instructions

---

## Definition of Done

| Change type        | Requirements                                                |
| ------------------ | ----------------------------------------------------------- |
| **New script/job** | Header, env vars, INFO/WARN/ERR logs, dry-run, cron example |
| **Edit generator** | Preserve paths/output, add logs, example output diff        |
| **Refactor**       | No behavior change, clearer logic, comments                 |
| **Docs**           | Practical snippets, examples                                |

---

## Agent Ops Protocol

1. Understand the ask → rephrase goal, list files.
2. Plan → bullet the approach, risks, assumptions.
3. Propose diffs → unified `git apply` ready.
4. Run static checks → `shfmt`, `shellcheck`.
5. Dry run → simulate output.
6. Cron → provide wrapper example.
7. Fallbacks → soft-fail logs.
8. Handoff → summary + verify + revert instructions.

---

## Allowed tools & dependencies

* `/bin/sh`, `ksh -p`
* Common utils: `date`, `awk`, `grep`, `cut`, `tr`, `jq`, `curl`
* Use shell unless a task explicitly requires another language.
* For new deps, include install steps for OpenBSD + Ubuntu.

---

## Templates

**Commit message example:**

```
feat(daily): add yard-work suitability line to daily note

- Pulls temp/dew point via API
- Adds summary under "Morning" section
- Soft-fails if API unavailable; logs WARN
```

**PR checklist:**

*

---

## Common playbooks

**Add new utility job**

1. Create `utils/<job>.sh` (POSIX sh, logs, env-driven).
2. Call from note generator.
3. Test locally.
4. Add cron line via wrapper.

---

## Security & privacy

* Never store secrets; use env vars.
* Redact sensitive paths/tokens in logs.
* Only log safe info.

---

## Compatibility notes

* **Copilot Chat / Cody:** Provide diffs + verify commands.
* **ChatGPT:** Single response including plan, diff, verify.
* Avoid interactivity; prefer env toggles.

---

## Changelog

* 2025-11-08: Initial AGENTS.md created; establishes protocol and standards.

---

### Missing info?

If a requirement isn’t in this file, **state your assumption** before proceeding and prefer opt-in behavior via env flags.
