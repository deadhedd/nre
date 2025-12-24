<!--
Review checklist (Table of Contents):
- [ ] 1. Execution Contract (job-wrap)
  - [ ] 1.1 Mandatory Re-exec via job-wrap
  - [ ] 1.2 job-wrap as the Sole Lifecycle Authority
  - [ ] 1.3 Single-Process Execution Model
  - [ ] 1.4 Wrapper Transparency
  - [ ] 1.5 Wrapper Availability Guarantee
  - [ ] 1.6 Design Intent Summary
- [ ] 2. Stdout / Stderr Contract
  - [ ] 2.1 Stdout Is Sacred
  - [ ] 2.2 Stderr Is for Humans and Diagnostics
  - [ ] 2.3 Wrapper-Enforced Separation
  - [ ] 2.4 Silence Is Valid Output
  - [ ] 2.5 Error Conditions and Output
  - [ ] 2.6 Logging Helpers Must Respect the Contract
  - [ ] 2.7 Design Intent Summary
- [ ] 3. Logging Contract
  - [ ] 3.1 Single Logging Authority
  - [ ] 3.2 Log Capture Model
  - [ ] 3.3 Log File Structure
  - [ ] 3.4 Log Buckets and Placement
  - [ ] 3.5 Structured Log Content
  - [ ] 3.6 Logging Libraries Are Wrapper-Only
  - [ ] 3.7 Failure Visibility Is Mandatory
  - [ ] 3.8 Design Intent Summary
- [ ] 4. Exit Code Semantics
  - [ ] 4.1 Wrapper Propagation Is Authoritative
  - [ ] 4.2 Meaning of 0
  - [ ] 4.3 Meaning of Non-Zero
  - [ ] 4.4 Reserved Exit Codes
  - [ ] 4.5 Soft Failure vs Hard Failure
  - [ ] 4.6 Caller Responsibilities
  - [ ] 4.7 Wrapper Failures
  - [ ] 4.8 Design Intent Summary
- [ ] 5. Run Cadence & Freshness — includes planned update to fold in
  - [ ] 5.1 Cadence Is a Property of the Job
  - [ ] 5.2 Declaring Expected Run Frequency
  - [ ] 5.3 Freshness Is Evaluated from Logs, Not Schedules
  - [ ] 5.4 Stale vs Missing
  - [ ] 5.5 Latest Pointer Is Not Authoritative
  - [ ] 5.6 Partial or Failed Runs
  - [ ] 5.7 Design Intent Summary
- [ ] 6. Environment & Paths
  - [ ] 6.1 Minimal, Explicit PATH
  - [ ] 6.2 Stable Repo-Relative Resolution
  - [ ] 6.3 job-wrap Discovery
  - [ ] 6.4 Required Environment Variables
  - [ ] 6.5 Working Directory
  - [ ] 6.6 Temporary Files and Directories
  - [ ] 6.7 Portability and Shell Assumptions
  - [ ] 6.8 Design Intent Summary
- [ ] 7. Idempotency & Side Effects
  - [ ] 7.1 Idempotency Is the Default Expectation
  - [ ] 7.2 Side Effects Must Be Intentional and Bounded
  - [ ] 7.3 Safe Overwrite Beats Clever Deltas
  - [ ] 7.4 Atomicity and Partial Failure
  - [ ] 7.5 Git Side Effects Are Centralized
  - [ ] 7.6 Time-Based Scripts and Determinism
  - [ ] 7.7 Reruns Are a First-Class Use Case
  - [ ] 7.8 Design Intent Summary
-->

**Status:** v0.1 — Early Draft
 
This document is a preliminary draft of the script contracts for `obsidian-note-tools`.  
 
- Heavy AI assistance was used in producing this text  
- Content has **not** been fully reviewed or validated  
- Contracts, language, and assumptions are subject to change  
 
Manual review and refinement are required before this document should be considered authoritative.

---

## Table of Contents

1. Execution Contract (job-wrap)
   1. Mandatory Re-exec via job-wrap
   2. job-wrap as the Sole Lifecycle Authority
   3. Single-Process Execution Model
   4. Wrapper Transparency
   5. Wrapper Availability Guarantee
   6. Design Intent Summary
2. Stdout / Stderr Contract
   1. Stdout Is Sacred
   2. Stderr Is for Humans and Diagnostics
   3. Wrapper-Enforced Separation
   4. Silence Is Valid Output
   5. Error Conditions and Output
   6. Logging Helpers Must Respect the Contract
   7. Design Intent Summary
3. Logging Contract
   1. Single Logging Authority
   2. Log Capture Model
   3. Log File Structure
   4. Log Buckets and Placement
   5. Structured Log Content
   6. Logging Libraries Are Wrapper-Only
   7. Failure Visibility Is Mandatory
   8. Design Intent Summary
4. Exit Code Semantics
   1. Wrapper Propagation Is Authoritative
   2. Meaning of 0
   3. Meaning of Non-Zero
   4. Reserved Exit Codes
   5. Soft Failure vs Hard Failure
   6. Caller Responsibilities
   7. Wrapper Failures
   8. Design Intent Summary
5. Run Cadence & Freshness
   1. Cadence Is a Property of the Job
   2. Declaring Expected Run Frequency
   3. Freshness Is Evaluated from Logs, Not Schedules
   4. Stale vs Missing
   5. Latest Pointer Is Not Authoritative
   6. Partial or Failed Runs
   7. Design Intent Summary
6. Environment & Paths
   1. Minimal, Explicit PATH
   2. Stable Repo-Relative Resolution
   3. job-wrap Discovery
   4. Required Environment Variables
   5. Working Directory
   6. Temporary Files and Directories
   7. Portability and Shell Assumptions
   8. Design Intent Summary
7. Idempotency & Side Effects
   1. Idempotency Is the Default Expectation
   2. Side Effects Must Be Intentional and Bounded
   3. Safe Overwrite Beats Clever Deltas
   4. Atomicity and Partial Failure
   5. Git Side Effects Are Centralized
   6. Time-Based Scripts and Determinism
   7. Reruns Are a First-Class Use Case
   8. Design Intent Summary

---

## 1. Execution Contract (job-wrap)

All scripts in `obsidian-note-tools` execute under a **single, mandatory wrapper**:
`utils/core/job-wrap.sh`.

This wrapper defines the canonical execution environment for all jobs and is the *only* component permitted to manage logging, lifecycle metadata, and optional auto-commit behavior.

### 1.1 Mandatory Re-exec via job-wrap

All leaf scripts **MUST** execute under `job-wrap.sh`.

A script that is invoked directly (e.g. from cron, manually, or by another script) **MUST** re-exec itself through `job-wrap.sh` unless execution is already active.

This is detected via the environment variable:

```sh
JOB_WRAP_ACTIVE=1
```

**Contractual behavior:**

* If `JOB_WRAP_ACTIVE` is **not set to `1`** and `job-wrap.sh` is available and executable:

  * The script **MUST** `exec` itself via `job-wrap.sh`
  * The original shell process is replaced
* If `JOB_WRAP_ACTIVE=1`:

  * The script **MUST NOT** attempt to re-wrap itself

This guarantees:

* Exactly one wrapper instance per job run
* No nested wrappers
* Predictable logging and exit handling

---

### 1.2 job-wrap as the Sole Lifecycle Authority

`job-wrap.sh` is the **exclusive authority** for:

* Execution lifecycle boundaries
* Log file creation and rotation
* Capturing and annotating stderr
* Recording start/end metadata
* Exit code propagation
* Optional commit behavior

Leaf scripts **MUST NOT**:

* Create or manage log files
* Rotate logs
* Commit files to Git
* Implement their own lifecycle wrappers
* Source shared logging libraries directly

Any such behavior is a contract violation.

---

### 1.3 Single-Process Execution Model

The execution model is intentionally **single-process, single-shell**:

* `job-wrap.sh` executes the leaf script in the **same shell process**
* No subshells or background execution are introduced by default
* All environment variables are inherited and remain visible

This enables:

* Reliable exit code propagation
* Deterministic cleanup
* Correct handling of `set -e`
* Centralized shutdown handling (signals, FIFOs, traps)

---

### 1.4 Wrapper Transparency

From the perspective of the leaf script:

* Invocation arguments are passed through unchanged
* Working directory is preserved
* Standard input is preserved
* Environment variables are preserved (with the addition of wrapper-specific variables)

The wrapper is designed to be **behaviorally transparent**, except where explicitly defined by other contracts (stdout/stderr handling, logging, exit semantics).

---

### 1.5 Wrapper Availability Guarantee

All production execution paths (cron jobs, automation pipelines, manual invocations) **ASSUME** that:

* `job-wrap.sh` exists
* It is executable
* Its path is stable relative to the repository root

If `job-wrap.sh` is missing or non-executable, execution **MUST fail fast** rather than silently degrading behavior.

---

### 1.6 Design Intent Summary

This execution contract exists to enforce the following invariants:

* There is exactly **one execution model**
* There is exactly **one logging authority**
* There is exactly **one place to reason about job behavior**
* Leaf scripts remain simple, testable, and boring

Any script that attempts to bypass or reimplement this contract is considered **incorrect by design**, even if it appears to “work”.

## 2. Stdout / Stderr Contract

Standard output (`stdout`) and standard error (`stderr`) have **strict, non-overlapping roles** across all scripts in `obsidian-note-tools`.

This contract exists to ensure scripts are:

* Composable
* Machine-readable
* Debuggable
* Safe to embed in pipelines and generators

Violations of this contract are considered **bugs**, even if no immediate failure occurs.

---

### 2.1 Stdout Is Sacred

**`stdout` is reserved exclusively for primary data output.**

Any script that emits meaningful data (markdown fragments, computed values, generated content, JSON, etc.) **MUST emit that data to stdout and nothing else**.

Leaf scripts **MUST NOT** write any of the following to stdout:

* Log messages
* Status messages
* Progress indicators
* Debug output
* Human-readable commentary
* Error descriptions

If a consumer script redirects or captures stdout, it must be able to do so **without filtering**.

> If a human can read it and it isn’t the primary data product, it does not belong on stdout.

---

### 2.2 Stderr Is for Humans and Diagnostics

**All non-data output MUST go to `stderr`.**

This includes:

* Informational messages
* Warnings
* Debug output
* Error messages
* Execution metadata
* Captured command output
* Trace or timing information

This applies **even when execution is successful**.

The system assumes that stderr:

* May be logged
* May be ignored
* May be redirected to a file
* May be viewed live during manual runs

…but it is **never** part of the data contract.

---

### 2.3 Wrapper-Enforced Separation

`job-wrap.sh` enforces this contract by design:

* Leaf script `stdout` passes through untouched
* Leaf script `stderr` is intercepted, annotated, and written to log files
* The wrapper itself **never writes to stdout**

This guarantees that:

* Data output remains pristine
* Logs are complete and contextualized
* No script accidentally pollutes downstream consumers

---

### 2.4 Silence Is Valid Output

A script producing **no stdout output** is valid and meaningful.

Examples include:

* Maintenance jobs
* State checks
* Snapshot or sync jobs
* Jobs whose purpose is side effects

Such scripts still:

* Emit diagnostics to stderr
* Produce logs via the wrapper
* Return meaningful exit codes

Consumers **MUST NOT** infer failure solely from empty stdout.

---

### 2.5 Error Conditions and Output

On failure:

* Partial or malformed data **MUST NOT** be written to stdout
* Error descriptions **MUST** go to stderr
* Exit status communicates failure (see Exit Code Semantics)

If a script cannot guarantee the correctness of its data output, it must:

* Emit nothing on stdout
* Fail loudly on stderr
* Exit non-zero

---

### 2.6 Logging Helpers Must Respect the Contract

Shared helpers (e.g. `log.sh`) are designed to:

* Never write to stdout
* Default all output to stderr
* Fail fast if executed incorrectly

Leaf scripts **MUST NOT** implement ad-hoc `echo`-based logging that risks stdout pollution.

---

### 2.7 Design Intent Summary

This contract exists to preserve a hard boundary:

| Stream | Purpose                     |
| ------ | --------------------------- |
| stdout | Structured, consumable data |
| stderr | Human diagnostics and logs  |

This enables:

* Safe composition of scripts
* Redirection without fear
* Debugging without data corruption
* Long-term maintainability

Once stdout is polluted, every downstream consumer becomes fragile.
This contract prevents that class of failure entirely.

## 3. Logging Contract

All logging behavior in `obsidian-note-tools` is **centralized, structured, and enforced** by `job-wrap.sh`.

Logging is not an optional feature, nor a per-script concern. It is a **system-level responsibility** with strict boundaries.

---

### 3.1 Single Logging Authority

`job-wrap.sh` is the **only component permitted to create, write, rotate, or manage log files**.

Leaf scripts **MUST NOT**:

* Create log files
* Decide log paths
* Rotate or prune logs
* Write timestamps or log prefixes
* Manage “latest” pointers
* Commit logs to Git

Any script that writes directly to a log file is in violation of this contract.

---

### 3.2 Log Capture Model

The logging model is intentionally simple and robust:

* Leaf script `stderr` is captured verbatim
* The wrapper annotates and appends this output to a per-run log file
* Each job run produces **exactly one log file**

No filtering, parsing, or suppression is applied at capture time.

This guarantees:

* Complete diagnostic fidelity
* No loss of context
* Postmortem debuggability

---

### 3.3 Log File Structure

Each job execution produces:

* A **per-run log file**, named with a timestamp
  Example:

  ```
  <job>-<UTC timestamp>.log
  ```

* A **stable pointer** to the most recent run:

  ```
  <job>-latest.log
  ```

The `*-latest.log` file is a **symlink**, not a copy.

Consumers must treat it as a *pointer*, not an authoritative record.

---

### 3.4 Log Buckets and Placement

Logs are stored under a shared log root, grouped into **buckets** that reflect job cadence and purpose (e.g. daily, weekly, long-cycle, other).

Bucket placement is a **wrapper concern**, not a leaf concern.

Leaf scripts:

* Do not know where their logs live
* Do not assume log paths
* Do not reference log files directly

This decoupling allows log layout to evolve without touching jobs.

---

### 3.5 Structured Log Content

Logs may contain:

* Wrapper-emitted lifecycle metadata (start, end, exit status, timing)
* Annotated stderr output from the leaf script
* Wrapper-internal diagnostics (opt-in)
* Captured output from child commands

Logs **MAY** be human-readable, but they are not required to be machine-parseable.

Machine interpretation, when needed, must be layered on top by consumer tools (e.g. status reports).

---

### 3.6 Logging Libraries Are Wrapper-Only

Shared logging helpers (e.g. `utils/core/log.sh`) exist to support the wrapper.

They are **library-only** and **MUST be sourced only by job-wrap.sh**.

Leaf scripts:

* MUST NOT source logging helpers
* MUST NOT call logging functions
* MUST NOT depend on logging internals

If a leaf script emits diagnostics, it does so by writing to `stderr` only.

---

### 3.7 Failure Visibility Is Mandatory

Even when a job fails catastrophically:

* A log file **MUST** exist
* Partial logs are acceptable
* Silent failure is not

If logging cannot be initialized, the wrapper must fail fast and loudly rather than executing the job without logs.

---

### 3.8 Design Intent Summary

This logging contract exists to enforce these invariants:

* Logs are **complete**
* Logs are **centralized**
* Logs are **consistent**
* Logs are **boring**

Leaf scripts should never need to think about logging.
If they are thinking about logging, the architecture has already failed.

## 4. Exit Code Semantics

Exit codes are the **primary machine-readable signal** of success or failure across the entire `obsidian-note-tools` ecosystem.

Exit codes must remain simple, predictable, and composable. Any script that exits with an ambiguous or misleading status is considered buggy.

---

### 4.1 Wrapper Propagation Is Authoritative

`job-wrap.sh` MUST propagate the leaf script’s exit status as the wrapper’s own exit status.

* If the leaf exits `0`, the wrapper exits `0`.
* If the leaf exits non-zero, the wrapper exits that same code (unless the wrapper itself fails earlier).

This guarantees that cron, calling scripts, and status-report tooling can treat the wrapper as transparent for success/failure.

---

### 4.2 Meaning of `0`

Exit code `0` means:

* The job completed successfully
* The job’s intended outputs (files and/or stdout data) are believed correct
* Any warnings emitted to stderr did not invalidate correctness

“Success with warnings” is still `0` unless the warnings imply invalid output.

---

### 4.3 Meaning of Non-Zero

Any non-zero exit code means:

* The job failed, or
* The job cannot guarantee the correctness of its outputs

On non-zero exit:

* Partial outputs MAY exist (side effects happen), but must be treated as suspect unless explicitly designed otherwise.
* Stdout MUST NOT contain partial/incorrect data (see Stdout/Stderr Contract).

---

### 4.4 Reserved Exit Codes

Some exit codes are reserved for **infrastructure / contract enforcement** rather than job-specific failure.

#### `2` — Contract / Wrapper-Level Misuse

Exit code `2` is reserved for cases like:

* A library-only helper was executed instead of sourced
* A required invariant for safe execution is violated
* Wrapper initialization fails in a way that makes execution unsafe

This is a “you called this wrong / you broke the rules” signal.

> Leaf scripts SHOULD avoid using exit code `2` for their own failure modes.

#### `126` / `127` — Standard Exec Failures

Standard shell semantics apply:

* `126`: found but not executable
* `127`: command not found

Leaf scripts should not attempt to “paper over” these. Let them surface.

---

### 4.5 Soft Failure vs Hard Failure

The system intentionally does **not** define multiple success classes at the exit-code layer.

If a job must communicate nuance (e.g. “ran fine, but didn’t update anything”), it should:

* Exit `0`
* Emit an informational line to stderr (which will be logged)
* Optionally write structured data to stdout *only if that is its purpose*

If nuance must be machine-readable, it belongs in:

* A generated artifact (file output), or
* A future explicit “status output” design (not ad-hoc exit codes)

---

### 4.6 Caller Responsibilities

Any script that calls another script MUST:

* Treat non-zero as failure
* Propagate failure unless explicitly handling it
* Avoid masking exit codes

If a caller intentionally handles a failure (rare), it must:

* Log/emit the reason to stderr
* Still ensure the overall system remains debuggable (logs exist, signals are visible)

---

### 4.7 Wrapper Failures

If `job-wrap.sh` fails before the leaf script runs, the wrapper MUST exit non-zero and treat the failure as authoritative.

Examples:

* Cannot create log directory / file
* Cannot create needed temporary resources (e.g. FIFO) safely
* Required environment is missing in a way that makes execution unsafe

Wrapper failures must be loud on stderr and present in logs when possible.

---

### 4.8 Design Intent Summary

Exit codes are designed to be:

* Boring
* Standard
* Dependable
* Interpretable by cron and automation without special casing

The system rejects “creative exit codes” as a communication channel.
If you need richer semantics, write richer artifacts—not weirder integers.

## 5. Run Cadence & Freshness

Many scripts in `obsidian-note-tools` are expected to run on a **defined cadence** (daily, weekly, hourly, ad-hoc, etc.).
Correctness is therefore not just *“did it run?”* but also *“did it run recently enough?”*.

This section defines how **run expectations** are communicated and how **freshness** is evaluated—without centralizing schedule knowledge in reporting code.

---

### 5.1 Cadence Is a Property of the Job

Each job is the **authoritative source** of truth for how often it is expected to run.

Cadence knowledge **MUST NOT** live in:

* `script-status-report.sh`
* Cron configuration alone
* External documentation
* Hardcoded tables in summary tools

If a job’s cadence changes, the job itself must change.

---

### 5.2 Declaring Expected Run Frequency

Each job **MUST declare** its expected run cadence in a machine-readable form that is emitted into its log on every run.

This declaration must be:

* Stable
* Explicit
* Easy to parse
* Human-readable in logs

The exact mechanism (e.g. a standardized stderr line or wrapper-supported metadata hook) is defined by convention, but the invariant is:

> Every log must contain enough information to determine when the *next* run was expected.

---

### 5.3 Freshness Is Evaluated from Logs, Not Schedules

Freshness checks are based on **observed execution**, not intent.

Status and summary tools determine freshness by:

* Reading the most recent successful (or latest) log
* Extracting the declared cadence
* Comparing log timestamp to “now”

Cron entries may exist, but cron alone is **not evidence of execution**.

A missing or stale log is treated as a failure condition.

---

### 5.4 Stale vs Missing

The system distinguishes between:

* **Missing**: no log exists for a job
* **Stale**: a log exists, but is older than allowed by cadence

Both conditions are failures, but they indicate different classes of problems:

* Missing → job never ran or logging broke
* Stale → scheduler failure, crash, or drift

---

### 5.5 Latest Pointer Is Not Authoritative

The presence of `<job>-latest.log` does **not** imply freshness.

Consumers must:

* Resolve the symlink
* Inspect the timestamp of the underlying log
* Validate it against declared cadence

A stale symlink pointing to an old run is a detectable and reportable failure.

---

### 5.6 Partial or Failed Runs

If a job fails:

* A log still exists
* Cadence declaration still exists
* Freshness is evaluated separately from success

A job may be:

* Fresh but failing
* Successful but stale
* Missing entirely

These are orthogonal dimensions and must not be conflated.

---

### 5.7 Design Intent Summary

This contract exists to enforce the following principles:

* Jobs describe their own expectations
* Observed reality beats configured intent
* Status reporting scales without central knowledge
* Staleness is a first-class failure mode

If a job doesn’t state how often it should run,
the system cannot know whether silence is acceptable—or a fire alarm.

## 6. Environment & Paths

Scripts in `obsidian-note-tools` must execute reliably under cron, interactive shells, and automation contexts.
Therefore, scripts must treat the runtime environment as **hostile by default** and must not depend on implicit shell state.

This section defines what may be assumed and what must be explicitly established.

---

### 6.1 Minimal, Explicit PATH

Scripts MUST NOT assume an interactive PATH.

Each executable script MUST explicitly set a safe baseline `PATH` early, typically:

* `/usr/local/bin:/usr/bin:/bin` (plus any existing PATH appended if desired)

The goal is:

* Deterministic command resolution
* Cron-safe execution
* Avoiding dependence on user dotfiles

---

### 6.2 Stable Repo-Relative Resolution

Scripts MUST locate other repo components by resolving paths relative to the script’s own location, not the current working directory.

Standard pattern:

* Determine `script_dir` via `dirname "$0"` and `pwd -P`
* Determine `repo_root` relative to that
* Reference helpers using absolute paths derived from `repo_root`

Scripts MUST NOT:

* Assume they are invoked from repo root
* Assume `.` contains anything meaningful
* Rely on `CDPATH`
* Rely on symlinked execution paths without resolving `pwd -P`

---

### 6.3 job-wrap Discovery

Leaf scripts MUST locate `job-wrap.sh` in a repo-stable way and re-exec through it as defined in the Execution Contract.

If `job-wrap.sh` cannot be found or is not executable, scripts MUST fail fast rather than silently running “unwrapped”.

---

### 6.4 Required Environment Variables

Scripts may rely on a small set of environment variables **only if explicitly defined as part of the ecosystem contract**.

Examples include (non-exhaustive):

* `JOB_WRAP_ACTIVE` (wrapper recursion guard)
* `VAULT_PATH` (work tree root for vault operations, if used in this repo)
* `TMPDIR` (optional; defaults must exist)

If a script requires an environment variable to behave correctly, it MUST:

* Validate it early
* Fail fast with a clear stderr error if missing/invalid

---

### 6.5 Working Directory

Scripts MUST NOT depend on the working directory.

* The working directory may be anything under cron or manual invocation.
* Scripts must use absolute paths for all filesystem operations, derived from `repo_root` and/or explicitly configured roots.

If a script intentionally changes directories, it must:

* Do so explicitly (`cd ...`)
* Treat failure to `cd` as fatal
* Avoid leaking relative path assumptions

---

### 6.6 Temporary Files and Directories

Temporary resources MUST be created in a safe temp location:

* Prefer `${TMPDIR:-/tmp}`

Temp artifacts MUST:

* Use unique names (include PID and/or timestamps)
* Be cleaned up via traps where appropriate
* Avoid collisions across concurrent runs

---

### 6.7 Portability and Shell Assumptions

All scripts target **POSIX `sh`**.

Scripts MUST NOT assume:

* Bashisms
* Arrays
* `pipefail`
* Non-POSIX `[[ ... ]]`
* GNU-only flags unless explicitly documented and constrained to a host

Where platform behavior differs (BSD vs GNU), scripts must:

* Prefer portable forms
* Or isolate platform specifics behind helpers

---

### 6.8 Design Intent Summary

This contract exists to ensure scripts are:

* Cron-safe
* Location-independent
* Deterministic
* Portable within the intended host constraints

If a script works “only when run from the repo root” or “only in my interactive shell”, that is a bug—not a quirk.

## 7. Idempotency & Side Effects

Scripts in `obsidian-note-tools` operate in an automated, often scheduled environment.
They must therefore be safe to run **repeatedly**, **out of order**, or **after partial failure** without causing corruption, duplication, or unintended drift.

This section defines expectations around idempotency and how side effects are handled.

---

### 7.1 Idempotency Is the Default Expectation

Unless explicitly documented otherwise, scripts are expected to be **idempotent** with respect to their intended outcomes.

Running the same script multiple times with the same inputs should result in:

* The same filesystem state
* The same generated content
* No duplicate entries
* No accumulating noise

Idempotency does **not** mean “no work happens”; it means “no unintended change happens”.

---

### 7.2 Side Effects Must Be Intentional and Bounded

Side effects (file writes, commits, state changes) are allowed, but they must be:

* Explicit
* Predictable
* Scoped to known locations
* Repeat-safe

Scripts MUST NOT:

* Append blindly to files without guards
* Duplicate sections in generated notes
* Accumulate state without bounds
* Modify files outside declared domains

If a script mutates state, that mutation must be the *reason the script exists*—not an accident of implementation.

---

### 7.3 Safe Overwrite Beats Clever Deltas

When generating files or sections, scripts should prefer:

* Full regeneration
* Atomic replace
* Clear section markers

Over:

* Incremental patching
* In-place edits without guards
* Context-dependent diffs

The system favors **clarity and correctness over cleverness**.

If it’s easier to delete and regenerate something deterministically, that is the correct choice.

---

### 7.4 Atomicity and Partial Failure

Where feasible, scripts should aim for atomic outcomes:

* Write to a temporary file
* Validate output
* Move into place only on success

If a script fails mid-run:

* Partial artifacts may exist
* But they should be clearly incomplete or overwritten on the next successful run
* Silent corruption is unacceptable

---

### 7.5 Git Side Effects Are Centralized

Scripts MUST NOT perform Git operations directly.

* Commits, staging, and repository interaction are handled by `job-wrap.sh`
* Scripts may create or modify files, but must not assume commit behavior
* Scripts must tolerate being run with commits disabled

This separation ensures that:

* Idempotency can be reasoned about independently of version control
* Jobs remain testable without Git side effects

---

### 7.6 Time-Based Scripts and Determinism

Scripts that depend on “now” (current date/time) must do so explicitly and carefully.

Expectations:

* Date resolution is intentional (daily, hourly, etc.)
* Output for a given period is deterministic
* Re-running for the same period produces the same result

If a script is inherently non-idempotent (e.g. snapshotting external state), that fact must be documented clearly in the script header and contracts.

---

### 7.7 Reruns Are a First-Class Use Case

The system assumes scripts may be:

* Re-run manually
* Re-run automatically after failure
* Run late
* Run multiple times in quick succession

Scripts must be written with the assumption that **reruns are normal**, not exceptional.

If a script cannot be safely re-run, that is an exceptional constraint and must be called out explicitly.

---

### 7.8 Design Intent Summary

This contract exists to ensure that:

* Automation is safe
* Recovery is easy
* Failure is survivable
* Re-runs are boring

A script that only works “the first time” is not automated—it is fragile.
