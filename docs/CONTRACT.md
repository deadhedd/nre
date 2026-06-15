# CONTRACT.md

## Authority

This document is the authoritative contract for the current engine behavior in this
repository.

When this document and implementation disagree, the current behavior of these
engine components is authoritative until the contract is corrected:

* `engine/wrap.sh`
* `engine/log.sh`
* `engine/log-format.sh`
* `engine/log-sink.sh`
* `engine/log-capture.sh`
* `engine/lib/commit.sh`

Current `jobs/helpers/*` behavior is documented here where known. Mismatches in
reporter helper behavior are not silently resolved by this contract; they are
called out as implementation notes or open decisions.

## 1. Engine Model

### 1.1 Components

The engine consists of:

* `engine/wrap.sh`: wrapper, lifecycle owner, stream boundary owner, logging
  bootstrapper, optional reporter invoker, and commit orchestrator.
* `engine/log.sh`: logging facade. It validates wrapper context, derives logger
  context, sources logger children, and initializes the active sink.
* `engine/log-format.sh`: log line formatter, level gate, ASCII sanitizer, and
  local timestamp formatter.
* `engine/log-sink.sh`: per-run log file owner, FD owner, latest symlink owner,
  and retention owner.
* `engine/log-capture.sh`: captured stream reader that forwards lines through
  the formatter into the active sink.
* `engine/lib/commit.sh`: explicit-file Git staging and commit helper.

`jobs/helpers/script-status-report-helper.sh` and
`jobs/helpers/sync-latest-logs-to-vault.sh` are current helper executables used
by the reporting flow. They are not core logging or commit authorities.

### 1.2 Terms

* **Leaf script**: an executable script containing domain logic.
* **Job**: a wrapper-mediated execution of a leaf script.
* **Boundary stdout/stderr**: streams visible to the invoker of the wrapped job.
* **Per-run log**: the authoritative engine log for one job execution.
* **Latest pointer**: `<job>-latest.log`, a symlink to the latest per-run log
  for a job.

### 1.3 Ownership Boundaries

Leaf scripts own domain behavior and generated artifacts.

The wrapper owns:

* single-wrapper execution
* wrapper-provided environment
* boundary stream discipline
* leaf stderr capture or passthrough fallback
* logger bootstrap and degradation policy
* optional status report invocation
* commit orchestration
* wrapper-reserved exit-code overrides

The logger owns:

* per-run log creation
* log line formatting
* level gating
* latest pointer updates
* log retention

The commit helper owns only explicit-file staging and one commit attempt.

Reporter helpers own only presentation/report artifacts and must not modify
authoritative engine logs.

## 2. Stream Contract

### 2.1 Stdout

Boundary `stdout` is reserved for primary data output only.

The wrapper and logger must not write observable bytes to boundary `stdout`.
Leaf scripts may write to `stdout` only when that data is the script's primary
data product. Status messages, progress, diagnostics, logging, and errors must
not be written to `stdout`.

Silence on `stdout` is valid output. Consumers must not infer failure solely
from empty `stdout`; exit status and logs carry success/failure information.

### 2.2 Stderr

Boundary `stderr` is for human diagnostics and operational visibility.

Leaf diagnostics must be single-line and level-prefixed:

```text
DEBUG: message
INFO: message
WARN: message
ERROR: message
```

The optional single space after the colon is permitted. Lines without a valid
prefix are captured as `UNDEF` when centralized capture is healthy.

### 2.3 Internal Stdout Exception

Logger internals may use `stdout` only as a fully captured private data channel,
for example to return a computed string in POSIX `sh`.

This exception does not apply to leaf scripts, the wrapper boundary, `log.sh` as
an observable facade, or the commit helper. Any internal helper stdout must be
captured or redirected so it cannot reach boundary `stdout`.

### 2.4 Failure Output

On failure, scripts must not write partial or misleading primary data to
`stdout`. Diagnostics belong on `stderr`; machine-readable success/failure is
communicated by exit status.

## 3. Execution Contract (`engine/wrap.sh`)

### 3.1 Invocation

`engine/wrap.sh` is invoked as:

```sh
engine/wrap.sh LEAF_PATH [args...]
```

Wrapper misuse exits `120`.

If `JOB_WRAP_ACTIVE=1` is already present at wrapper entry, the wrapper treats
that as recursion and exits `120`.

Leaf scripts are expected to re-exec through `engine/wrap.sh` when not already
wrapped. Once active, they must not re-wrap themselves.

### 3.2 Wrapper Environment

The wrapper sources an optional environment file early:

* path: `${JOB_WRAP_ENV_FILE:-/home/obsidian/obsidian-note-tools/env.sh}`
* only if readable
* must be POSIX `sh` assignments/exports

If sourcing the readable env file fails, wrapper initialization fails with
`121`.

The wrapper exports:

* `JOB_WRAP_ACTIVE=1`
* `REPO_ROOT`: absolute repository root, normally the parent of `engine/`
* `LOG_ROOT`: if unset or empty, parent-of-repo `logs`; if that cannot be
  resolved, `$REPO_ROOT/logs`
* `LOG_LIB_DIR`: default `$REPO_ROOT/engine/lib`
* `ENGINE_LIB_DIR`: default `$REPO_ROOT/engine`
* `COMMIT_LIB_DIR`: default `$LOG_LIB_DIR`
* `VAULT_ROOT`: `${VAULT_ROOT:-${VAULT_PATH:-/home/obsidian/vaults/Main}}`
* `COMMIT_WORK_TREE`: `${COMMIT_WORK_TREE:-$VAULT_ROOT}`

Implementation note: current `engine/wrap.sh` does not normalize `LC_ALL` or
`LANG`. Locale normalization is therefore not a current normative wrapper
requirement.

### 3.3 Leaf Resolution

If `LEAF_PATH` contains `/`, relative paths are anchored to the current physical
working directory.

If `LEAF_PATH` has no `/`, the wrapper searches:

1. `JOB_WRAP_SEARCH_PATH`, defaulting to:
   `$REPO_ROOT/bin:$REPO_ROOT/jobs:$REPO_ROOT/generators:$REPO_ROOT/engine:$REPO_ROOT/utils:$REPO_ROOT/scripts`
2. executable files under `REPO_ROOT`, pruning `.git` and `logs`, sorted and
   taking the first hit
3. readable `.sh` files under `REPO_ROOT`, sorted and taking the first hit
4. `PATH` via `command -v`

If a readable `.sh` file is not executable, the wrapper runs it with `sh`.

If no leaf is found by name, the wrapper exits `127`.

`JOB_NAME` is derived from the leaf basename with its extension removed and must
match `[A-Za-z0-9._-]+`. Invalid derived names exit `120`.

### 3.4 Leaf Execution and Stderr Capture

The wrapper executes the leaf as a child process and passes arguments through
unchanged.

Primary mode:

* leaf `stdout` passes through untouched
* leaf `stderr` is redirected to a wrapper-owned temp file
* after the leaf exits, captured `stderr` is forwarded into `log_capture UNDEF`
  without wrapper rewriting
* the wrapper records `leaf: rc=<n>` as a wrapper diagnostic

Fallback mode:

* if temp capture cannot be created, `CAPTURE_MODE=passthrough`
* leaf `stderr` reaches boundary `stderr` verbatim
* this is a soft logging degradation by itself
* the leaf exit code remains authoritative unless a separate wrapper failure
  occurs

If centralized logging is healthy but `log_capture` fails, the wrapper marks
logging degraded, records evidence in the bootstrap log when possible, and
replays captured leaf `stderr` to boundary `stderr`.

### 3.5 Wrapper Diagnostics

Wrapper diagnostics never write to `stdout`.

Boundary wrapper diagnostics use:

```text
LEVEL: WRAP: message
```

When logging is healthy, wrapper diagnostics are mirrored into the per-run log
through `log_capture`. Boundary emission rules are:

* degraded logging: `DEBUG`, `INFO`, `WARN`, and `ERROR` may be emitted subject
  to `LOG_MIN_LEVEL`
* healthy logging: `WARN` and `ERROR` are emitted; `DEBUG` and `INFO` are emitted
  only when `JOB_WRAP_DEBUG=1` or `LOG_MIN_LEVEL=DEBUG`

Multiline wrapper diagnostics are not emitted raw at the boundary. The boundary
receives a single-line pointer to the run log or bootstrap log.

### 3.6 Logging Bootstrap

The wrapper creates a best-effort bootstrap log under:

```text
${LOG_ROOT}/_bootstrap/
```

Bootstrap logs are wrapper-owned forensic artifacts. They are not per-run logs,
do not participate in latest pointer semantics, and are not managed by logger
retention.

The wrapper captures `log_init` stdout during initialization when temp files are
available. If `log_init` writes stdout, that is treated as a contained contract
violation and soft logging degradation; leaked bytes are recorded in the
bootstrap log when possible and do not reach boundary `stdout`.

`log_init` return handling:

* `0`: centralized logging healthy
* `10`: operational logging failure; wrapper degrades and continues
* `11`: logger misuse; wrapper initialization fails with `121`
* other non-zero: wrapper degrades and continues

### 3.7 Optional Status Report

`WRAP_STATUS_REPORT` defaults to `0`.

When `WRAP_STATUS_REPORT=1`, and the current job is not
`script-status-report`, the wrapper invokes:

```text
$REPO_ROOT/jobs/helpers/script-status-report-helper.sh
```

The helper's failure is logged as a wrapper warning and does not override the
leaf exit code.

Implementation note: older contract text described a `report.sh` facade. Current
engine behavior does not use such a facade; it directly calls the helper above.

### 3.8 Commit Orchestration

`COMMIT_MODE` defaults to `required`.

Recognized wrapper behavior:

* `off`: no commit list is created and no commit helper is invoked
* `required`: commit helper failures are fatal when the helper is invoked and
  returns a failure code
* any other value, including `best-effort`: commit orchestration is enabled but
  helper failures are warnings, not wrapper exit overrides

If commit mode is not `off`, the wrapper attempts to create and export
`COMMIT_LIST_FILE` before running the leaf. Leaf scripts register artifacts by
appending one path per line after the artifact has been finalized.

The wrapper filters blank lines and comment lines from `COMMIT_LIST_FILE`.

If the leaf exits non-zero, commit orchestration is skipped.

If the leaf exits `0`, commit mode is not `off`, and the filtered commit list is
non-empty, the wrapper invokes:

```sh
sh "$COMMIT_LIB_DIR/commit.sh" "$COMMIT_WORK_TREE" "$COMMIT_MESSAGE" <files...>
```

`COMMIT_MESSAGE` defaults to `job: ${JOB_NAME}` when unset or empty.

Commit helper return handling:

* `0`: success
* `3`: no changes; non-failure
* other: fatal only when `COMMIT_MODE=required`; wrapper exits `123`

If commit mode is enabled but no usable commit list exists, the wrapper warns
and continues.

### 3.9 Wrapper Exit Codes

The wrapper exits with the leaf exit code when wrapper execution completes
without a fatal wrapper override.

Wrapper-reserved exits:

| Code | Meaning |
| ---- | ------- |
| 120 | wrapper invocation or usage error |
| 121 | wrapper initialization failure |
| 123 | commit helper failure when commit mode is `required` |

Standard shell exit `127` may surface for leaf-not-found paths.

## 4. Logging Contract

### 4.1 Facade (`engine/log.sh`)

`engine/log.sh` is library-only. Executing it directly emits an error to
`stderr` and exits `2`.

`log.sh` must be sourced by wrapper-managed code with `JOB_WRAP_ACTIVE=1`.
`log_init <JOB_NAME> [MIN_LEVEL]` validates:

* wrapper context
* non-empty `JOB_NAME`
* `LOG_MIN_LEVEL` in `DEBUG|INFO|WARN|ERROR`
* `LOG_BUCKET` if provided
* logger child paths

`log.sh` sources:

* `$LOG_LIB_DIR/datetime.sh`
* `$ENGINE_LIB_DIR/log-format.sh`
* `$ENGINE_LIB_DIR/log-sink.sh`
* `$ENGINE_LIB_DIR/log-capture.sh`

`LOG_BUCKET` is facade-owned. If caller provides a non-empty value, it must
match `[A-Za-z0-9._-]+`. Otherwise `log.sh` derives:

| `JOB_NAME` | `LOG_BUCKET` |
| ---------- | ------------ |
| `generate-daily-note`, `daily-note-snapshot` | `daily-notes` |
| `generate-weekly-note` | `weekly-notes` |
| `generate-monthly-note`, `generate-quarterly-note`, `generate-yearly-note` | `long-cycle` |
| anything else | `other` |

`log.sh` never writes to observable `stdout`. If sink initialization fails,
`log.sh` degrades to stderr-only logging and returns the sink return code to the
wrapper.

### 4.2 Formatter (`engine/log-format.sh`)

`log-format.sh` is library-only. Direct execution exits `2`.

`log_format_build_line OUT_VAR MIN_LEVEL LEVEL MESSAGE` returns:

* `0`: formatted line stored in `OUT_VAR`
* `4`: suppressed by level policy, non-failure
* `10`: operational failure, including invalid message level
* `11`: misuse, including invalid minimum level

Valid message levels are `DEBUG`, `INFO`, `WARN`, `ERROR`, and `UNDEF`.
`UNDEF` always passes level gating.

Formatted log lines use:

```text
YYYY-MM-DD HH:MM:SS [local] LEVEL message
```

The formatter strips carriage returns and replaces non-ASCII bytes with `?`.
Messages passed to the formatter must be single-line.

### 4.3 Sink (`engine/log-sink.sh`)

`log-sink.sh` is library-only. Direct execution exits `2`.

The sink requires `LOG_FACADE_ACTIVE=1`, a valid `JOB_NAME`, and a non-empty
`LOG_BUCKET`.

Valid `JOB_NAME` is `[A-Za-z0-9._-]+`, excluding `.` and `..`.

The sink generates and exports `LOG_FILE`:

```text
${LOG_ROOT}/${LOG_BUCKET}/${JOB_NAME}-YYYY-MM-DD-HHMMSS.log
```

The timestamp is local time, fixed-width, and lexicographically sortable.

The sink opens FD `3` for appending to `LOG_FILE` and updates:

```text
${LOG_ROOT}/${LOG_BUCKET}/${JOB_NAME}-latest.log
```

as a symlink to `LOG_FILE`.

`LOG_ROOT` defaults to `./logs` in the sink if not already supplied by the
wrapper.

### 4.4 Retention

`LOG_KEEP_COUNT` controls per-job, directory-local retention.

Current sink behavior:

* unset or empty: pruning disabled
* `0`: pruning disabled
* positive integer `N`: keep the `N` most recent per-run logs matching
  `${JOB_NAME}-????-??-??-??????.log` in the current log directory
* negative or non-integer: misuse, return `11`

Retention is non-recursive for deletion candidates. `*-latest.log` is not a
retention candidate.

Implementation note: `engine/wrap.sh` currently exports
`LOG_KEEP_COUNT=${LOG_KEEP_COUNT:-10}` before logger initialization, so normal
wrapped runs default to keeping ten per-run logs. The sink's own unset/empty
behavior is still pruning disabled when used without that wrapper default.

### 4.5 Capture (`engine/log-capture.sh`)

`log-capture.sh` is library-only. Direct execution exits `2`.

`log_capture_stream LEVEL` reads stdin line by line. For each line:

* if the line begins with `DEBUG:`, `INFO:`, `WARN:`, or `ERROR:`, that prefix
  determines the effective level
* otherwise the caller-provided `LEVEL` is used
* the wrapper passes `UNDEF` for leaf stderr capture, so missing/invalid leaf
  prefixes are visible as `UNDEF`

The full original line is retained as message content; prefix recognition does
not strip the line before formatting.

Required facade context:

* `LOG_FACADE_ACTIVE=1`
* usable numeric `LOG_SINK_FD`
* non-empty `LOG_MIN_LEVEL`
* non-empty capture `LEVEL`

Missing or invalid context returns `11`.

### 4.6 Logger Return Codes

Logger subsystem return codes:

| Code | Meaning |
| ---- | ------- |
| 0 | success |
| 2 | direct execution of a library-only logger component |
| 4 | suppressed by level policy; non-failure |
| 10 | operational failure |
| 11 | misuse or invalid facade-provided context |

Logger helpers must not decide whether a job fails. `log.sh` and
`engine/wrap.sh` own degradation and escalation policy.

## 5. Commit Helper Contract (`engine/lib/commit.sh`)

### 5.1 Invocation

The commit helper is invoked as:

```sh
commit.sh <work_tree_root> <message> <file> [file...]
```

A leading `--` before arguments is accepted. No options are supported.

The helper requires `JOB_WRAP_ACTIVE=1`; otherwise it fails with exit `10`.

The commit message must be non-empty.

### 5.2 Environment

The helper sources `${JOB_WRAP_ENV_FILE:-/home/obsidian/obsidian-note-tools/env.sh}`
if readable.

It sets:

```sh
PATH="/usr/local/bin:/usr/bin:/bin:${PATH:-}"
```

Overrides:

* `COMMIT_BARE_REPO`, default `/home/git/vaults/Main.git`
* `GIT_BIN`, default `/usr/local/bin/git` when executable, otherwise `git`
* `GIT_USER`, default `git`
* `ENGINE_DEBUG=1` or `LOG_INTERNAL_DEBUG=1` enables extra stderr-only debug

### 5.3 Git and Privilege Boundary

The helper commits to a bare repository using:

```sh
doas -u "$GIT_USER" "$GIT_BIN" --git-dir="$BARE_REPO" --work-tree="$work_root" ...
```

The helper must not run as `GIT_USER`; if it is already executing as that user,
it exits `10`.

Missing `doas`, missing Git, inaccessible bare repo, or invalid `GIT_USER` are
operational failures and exit `10`.

### 5.4 Explicit File Staging

The helper stages only explicit file arguments.

For each file:

* empty file arguments are rejected
* paths must resolve within the work tree
* directories are rejected
* existing files are staged with `git add -- <rel_path>`
* missing tracked files are staged as deletions with `git rm --ignore-unmatch`
* missing untracked files are skipped with a warning

The helper must not use `git add -A`, infer files from directory state, manage
branches, push, resolve conflicts, or retry.

### 5.5 Streams and Exit Codes

The commit helper must not write to `stdout`.

Human diagnostics and Git output may be written to `stderr`.

Exit codes:

| Code | Meaning |
| ---- | ------- |
| 0 | commit created |
| 3 | no changes to commit; non-failure |
| 10 | operational failure, invalid input, repo unavailable, Git/doas failure, or misuse |

## 6. Reporter Contract and Current Implementation Notes

### 6.1 Current Reporter Entry Points

Current reporter flow is implemented by:

* `jobs/script-status-report.sh`: leaf facade that self-wraps through
  `engine/wrap.sh`
* `jobs/helpers/script-status-report-helper.sh`: wrapper-context helper that
  generates the status report
* `jobs/helpers/sync-latest-logs-to-vault.sh`: helper that mirrors latest logs
  into the vault as Markdown presentation artifacts

Current `engine/wrap.sh` directly invokes
`jobs/helpers/script-status-report-helper.sh` when `WRAP_STATUS_REPORT=1`.

Open decision: whether to introduce, restore, or permanently remove a dedicated
`report.sh` facade remains unresolved. This contract does not require a
`report.sh` facade while the current engine lacks one.

### 6.2 Status Report Inputs

The status helper reads `LOG_ROOT`, defaulting to `/home/obsidian/logs` when not
provided.

It scans:

```sh
find "$LOG_ROOT" -name '*-latest.log' ! -name 'script-status-report-latest.log'
```

and sorts the resulting paths.

It evaluates the latest pointer path itself as the log path. Because logger
latest pointers are symlinks, this normally reads the symlink target.

Implementation note: the helper contains a `find_previous_completed_log`
function but does not currently use it for classification.

### 6.3 Status Extraction

The status helper extracts:

* leaf exit code from the last line matching `WRAP: leaf: rc=<n>`
* warning count from timestamped log lines whose level token is `WARN` or
  `WARNING`
* error count from timestamped log lines whose level token is `ERR`, `ERROR`,
  `FATAL`, or `UNDEF`
* cadence from the last token matching `cadence=<value>`
* optional grace from the last token matching `grace=<n><unit>` where unit is
  `s`, `m`, `h`, or `d`
* run timestamp from the first timestamped log line

Recognized cadence values and base allowed ages:

| Cadence | Allowed age |
| ------- | ----------- |
| `hourly` | 3600 seconds |
| `daily` | 86400 seconds |
| `weekly` | 604800 seconds |
| `monthly` | 2592000 seconds |
| `quarterly` | 7776000 seconds |
| `yearly` | 31536000 seconds |
| `ad-hoc` | not freshness-evaluated |

Unknown cadence is indeterminate.

Freshness states currently emitted by helper logic:

* `fresh`
* `late`
* `stale`
* `n/a`
* `indeterminate`

### 6.4 Classification States

Current status labels:

| Label | Current meaning |
| ----- | --------------- |
| `OK` | exit code is `0`, no counted warnings/errors, freshness acceptable |
| `WARN` | exit code is `0`, warnings are present, no counted errors |
| `FAIL` | non-zero extracted leaf exit code |
| `ERR` | counted error lines are present without non-zero extracted exit |
| `unknown` | no extracted leaf exit code before cadence/freshness overrides |
| `NO-CAD` | missing cadence token |
| `STALE` | latest run is older than cadence plus grace |
| `FRESH?` | freshness cannot be determined |

Precedence in the current helper is:

1. extracted exit code establishes `OK`, `FAIL`, or `unknown`
2. error count upgrades non-`FAIL` states to `ERR`
3. warning count upgrades `OK` to `WARN`
4. missing cadence overrides to `NO-CAD`
5. stale freshness overrides to `STALE`
6. late freshness is displayed but does not alter status
7. indeterminate freshness overrides to `FRESH?`

### 6.5 Markdown Report Output

The status helper writes the default report to:

```text
${VAULT_ROOT}/00 - System/Server Logs/Script Status Report.md
```

unless `--output <absolute-path>` is provided.

`--dry-run` emits report Markdown to `stdout` and does not write the report
file.

The report currently includes:

* `# Script Status Report`
* `Generated: <local timestamp>`
* `LOG_ROOT: <path>`
* `## Status Table`
* columns: `Script`, `Status`, `Exit Code`, `Warns`, `Errs`, `Cadence`,
  `Fresh`, `Log`
* `## Summary` when jobs are found
* block ref `^script-status-summary`
* `### Issues`
* marker `<!-- reporter:fail_jobs=<n> -->`

Implementation note: the report currently includes Unicode status icons. This
is permitted for human-facing Markdown artifacts, even though raw engine logs
are ASCII-sanitized.

### 6.6 Reporter Exit Semantics

Current `script-status-report-helper.sh` exits `0` after successfully generating
and writing the report, even when `reporter:fail_jobs` is greater than zero.

It exits non-zero for helper execution failures such as invalid arguments,
missing wrapper context, missing libraries, temp file failures, report generation
failure, or write failure.

Open decision: whether the reporter should return non-zero when classified jobs
are unhealthy is unresolved. Current implementation treats unhealthy job rows as
report content, not reporter process failure.

Open decision: whether `WARN`, `STALE`, `NO-CAD`, `FRESH?`, or `ERR` should map
to reporter process failure remains unresolved. Current helper does not fail the
process for those classifications after the report is produced.

### 6.7 Vault Latest-Log Mirrors

`sync-latest-logs-to-vault.sh` mirrors `*-latest.log` files into Markdown files
under:

```text
${VAULT_ROOT}/00 - System/Server Logs/Latest Logs
```

unless `--vault-log-dir` is provided.

It reads from `${LOG_ROOT:-/home/obsidian/logs}` unless `--log-root` is provided.

By default, its `stdout` is empty. With `--emit-written-list`, it emits one
written destination path per line to `stdout` for its caller to capture and add
to `COMMIT_LIST_FILE`.

These vault mirrors are presentation artifacts only. They are not authoritative
for exit codes, freshness, or health.

Implementation note: this helper does not require wrapper context if
`--vault-log-dir` is supplied or `VAULT_ROOT` is present. It sources engine
libraries directly by repo-relative path and is therefore not a pure
wrapper-only helper in current behavior.

## 7. Environment, Paths, and Portability

### 7.1 PATH

Executable scripts must not rely on an interactive `PATH`.

Current engine behavior:

* `engine/wrap.sh` does not reset `PATH` globally before leaf execution
* `engine/lib/commit.sh` resets `PATH` to
  `/usr/local/bin:/usr/bin:/bin:${PATH:-}`
* `jobs/helpers/sync-latest-logs-to-vault.sh` resets `PATH` to
  `/usr/local/bin:/usr/bin:/bin:${PATH:-}`

Open decision: whether wrapper-level `PATH` normalization should be required is
unresolved. It is not current `engine/wrap.sh` behavior.

### 7.2 Path Resolution

Scripts must not depend on current working directory for locating repository
components. They should resolve paths relative to their own location or use
wrapper-provided `REPO_ROOT` after `JOB_WRAP_ACTIVE=1`.

Wrapper-derived `REPO_ROOT` must be absolute. Invalid `REPO_ROOT` during wrapper
initialization exits `121`.

### 7.3 Temporary Files

The wrapper uses `${TMPDIR:-/tmp}` when creating capture, logger containment,
and commit-list temp files. If temp capture is not available, it may fall back
to stderr passthrough. If commit-list temp files are not available, commit
orchestration is disabled with a warning for that run.

Helpers use `${TMPDIR:-/tmp}` for temp files and clean them up with traps where
implemented.

### 7.4 POSIX Shell

Engine scripts target POSIX `sh`.

Do not introduce bashisms, arrays, `pipefail`, `[[ ... ]]`, or GNU-only flags
into engine contracts or scripts unless a specific component contract is updated
to allow them.

## 8. Side Effects and Determinism

Leaf scripts must keep side effects explicit, bounded, and repeat-safe.

Generated artifacts should be written atomically where practical. Files should
be registered in `COMMIT_LIST_FILE` only after they are finalized.

Leaf scripts must not run Git directly. Git staging and committing are
wrapper-managed through `engine/lib/commit.sh`.

Time-based scripts must make period selection explicit and produce deterministic
output for the same period, except where a script is intentionally snapshotting
external state.

Reporter output and log enumeration must be deterministic where current helper
behavior allows. Current reporter helper sorts discovered latest-log paths.

## 9. Open Decisions

The following points are intentionally unresolved because current helper behavior
and previous contract language do not fully agree:

* Whether a dedicated `report.sh` facade should exist.
* Whether reporter helper invocation should be wrapper-only in every mode.
* Whether reporter process exit should be non-zero when generated report content
  contains unhealthy job classifications.
* Whether stale, missing cadence, indeterminate freshness, warnings, or counted
  errors should affect reporter process exit status.
* Whether wrapper-level `PATH`, `LC_ALL`, and `LANG` normalization should become
  normative.
* Whether `COMMIT_MODE` should remain current-default `required` or change to
  previous-plan/default `best-effort`.
* Whether `sync-latest-logs-to-vault.sh` should continue to be callable outside
  wrapper context.

Until those decisions are made, current implementation behavior described in
this document is authoritative.
