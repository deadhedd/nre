<!--
Review checklist (Table of Contents):
- Status: draft content added; pending review/acceptance
- [ ] 1. Engine Overview
  - [ ] 1.1 What the “Engine” Is
  - [ ] 1.2 Engine Components
  - [ ] 1.3 Design Philosophy
  - [ ] 1.4 Non-Goals
  - [ ] 1.5 Engine Boundaries
  - [ ] 1.6 Stability & Contract Authority
- [ ] 2. Cross-Cutting Contracts
  - [ ] 2.1 Stdout / Stderr Contract
    - [ ] 2.1.1 Stdout Is Sacred
    - [ ] 2.1.2 Stderr Is for Humans and Diagnostics
    - [ ] 2.1.3 Wrapper-Enforced Separation
    - [ ] 2.1.4 Silence Is Valid Output
    - [ ] 2.1.5 Error Conditions and Output
    - [ ] 2.1.6 Logging Helpers Must Respect the Contract
    - [ ] 2.1.7 Design Intent Summary
  - [ ] 2.2 Logging Contract
    - [ ] 2.2.1 Single Logging Authority
    - [ ] 2.2.2 Log Capture Model
    - [ ] 2.2.3 Log File Structure
    - [ ] 2.2.4 Log Buckets and Placement
    - [ ] 2.2.5 Structured Log Content
    - [ ] 2.2.6 Logging Libraries Are Wrapper-Only
    - [ ] 2.2.7 Failure Visibility Is Mandatory
    - [ ] 2.2.8 Design Intent Summary
  - [ ] 2.3 Exit Code Semantics
    - [ ] 2.3.1 Wrapper Propagation Is Authoritative
    - [ ] 2.3.2 Meaning of 0
    - [ ] 2.3.3 Meaning of Non-Zero
    - [ ] 2.3.4 Reserved Exit Codes
    - [ ] 2.3.5 Soft Failure vs Hard Failure
    - [ ] 2.3.6 Caller Responsibilities
    - [ ] 2.3.7 Wrapper Failures
    - [ ] 2.3.8 Design Intent Summary
  - [ ] 2.4 Run Cadence & Freshness — includes planned update to fold in
    - [ ] 2.4.1 Cadence Is a Property of the Job
    - [ ] 2.4.2 Declaring Expected Run Frequency
    - [ ] 2.4.3 Freshness Is Evaluated from Logs, Not Schedules
    - [ ] 2.4.4 Stale vs Missing
    - [ ] 2.4.5 Latest Pointer Is Not Authoritative
    - [ ] 2.4.6 Partial or Failed Runs
    - [ ] 2.4.7 Design Intent Summary
  - [ ] 2.5 Environment & Paths
    - [ ] 2.5.1 Minimal, Explicit PATH
    - [ ] 2.5.2 Stable Repo-Relative Resolution
    - [ ] 2.5.3 job-wrap Discovery
    - [ ] 2.5.4 Environment Variable Usage
    - [ ] 2.5.5 Working Directory
    - [ ] 2.5.6 Temporary Files and Directories
    - [ ] 2.5.7 Portability and Shell Assumptions
    - [ ] 2.5.8 Design Intent Summary
  - [ ] 2.6 Idempotency & Side Effects
    - [ ] 2.6.1 Idempotency Is the Default Expectation
    - [ ] 2.6.2 Side Effects Must Be Intentional and Bounded
    - [ ] 2.6.3 Safe Overwrite Beats Clever Deltas
    - [ ] 2.6.4 Atomicity and Partial Failure
    - [ ] 2.6.5 Git Side Effects Are Centralized
    - [ ] 2.6.6 Time-Based Scripts and Determinism
    - [ ] 2.6.7 Reruns Are a First-Class Use Case
    - [ ] 2.6.8 Design Intent Summary
- [ ] 3. Component Contracts
  - [ ] 3.1 Execution Contract (job-wrap)
    - [ ] 3.1.1 Mandatory Re-exec via job-wrap
    - [ ] 3.1.2 job-wrap as the Sole Lifecycle Authority
    - [ ] 3.1.3 Single-Process Execution Model
    - [ ] 3.1.4 Wrapper Transparency
    - [ ] 3.1.5 Wrapper Availability Guarantee
    - [ ] 3.1.6 Design Intent Summary
  - [ ] 3.2 Logger Contract (log.sh)
    - [ ] 3.2.1 Role & Responsibility
    - [ ] 3.2.2 Library-Only (Sourcing) Contract
    - [ ] 3.2.3 Ownership & Call-Site Contract
    - [ ] 3.2.4 Output Contract (Stdout/Stderr)
    - [ ] 3.2.5 Logging Primitives Contract
    - [ ] 3.2.6 Determinism & Safety
    - [ ] 3.2.7 Internal Debug (Opt-in Only)
    - [ ] 3.2.8 Compatibility Contract
    - [ ] 3.2.9 Exit Code & Return Semantics
    - [ ] 3.2.10 Non-Goals
    - [ ] 3.2.11 Stability Promise
  - [ ] 3.3 Commit Helper Contract (commit.sh)
    - [ ] 3.3.1 Role & Responsibility
    - [ ] 3.3.2 Invocation Contract
    - [ ] 3.3.3 Logging & Output Contract
    - [ ] 3.3.4 Stdout / Stderr Semantics
    - [ ] 3.3.5 Input Contract
    - [ ] 3.3.6 Idempotency & Safety
    - [ ] 3.3.7 Exit Code Semantics
    - [ ] 3.3.8 Non-Goals
    - [ ] 3.3.9 Stability Promise
  - [ ] 3.4 Status Report Contract (script-status-report.sh)
    - [ ] 3.4.1 Role & Responsibility
    - [ ] 3.4.2 Invocation Contract
    - [ ] 3.4.3 Logging & Output Contract
    - [ ] 3.4.4 Inputs & Data Sources
    - [ ] 3.4.5 Freshness Model
    - [ ] 3.4.6 Classification Semantics
    - [ ] 3.4.7 Required Signals
    - [ ] 3.4.8 Output Contract (Markdown Report)
    - [ ] 3.4.9 Side Effects & Idempotency
    - [ ] 3.4.10 Exit Code Semantics
    - [ ] 3.4.11 Non-Goals
    - [ ] 3.4.12 Stability Promise
-->

**Status:** v0.1 — Early Draft
 
This document is a preliminary draft of the script contracts for `obsidian-note-tools`.  
 
- Heavy AI assistance was used in producing this text  
- Content has **not** been fully reviewed or validated  
- Contracts, language, and assumptions are subject to change  
 
Manual review and refinement are required before this document should be considered authoritative.

---

## Table of Contents

1. Engine Overview
2. Cross-Cutting Contracts
   1. Stdout / Stderr Contract
   2. Logging Contract
   3. Exit Code Semantics
   4. Run Cadence & Freshness
   5. Environment & Paths
   6. Idempotency & Side Effects
3. Component Contracts
   1. Execution Contract (job-wrap)
   2. Logger Contract (log.sh)
   3. Commit Helper Contract (commit.sh)
   4. Status Report Contract (script-status-report.sh)

---

## 1. Engine Overview

**Status:** v0.1 — Early Draft
Heavy AI assistance. Requires manual review and validation.

### 1.1 What the “Engine” Is

The engine is the core execution and observability layer of obsidian-note-tools.

It is composed of a small, tightly-scoped set of components that together provide:

* Deterministic job execution
* Strict stdout/stderr discipline
* Centralized, structured logging
* Optional automatic version control commits
* A stable, human-readable system health report

The engine exists to make scripts boring, predictable, and auditable.

---

### 1.2 Engine Components

The engine consists of the following canonical components:

* `job-wrap.sh`
  The execution wrapper and lifecycle owner.
  Responsible for:
  * enforcing execution contracts
  * environment normalization
  * stdout/stderr routing
  * log file creation and rotation
  * optional commit orchestration
* `log.sh`
  The shared logging helper library.
  Provides stable, minimal logging primitives.
  Logging lifecycle ownership remains with `job-wrap.sh`.
* `commit.sh`
  The commit helper.
  A single-purpose component that stages and commits an explicit file list when instructed.
* `script-status-report.sh`
  The status reporter.
  An observational component that summarizes engine health by inspecting engine artifacts.

No other scripts are considered part of the engine unless explicitly declared by contract.

---

### 1.3 Design Philosophy

The engine is intentionally:

* Opinionated
  Contracts are strict. Violations are bugs.
* Composable
  Small components with narrow responsibilities compose into higher-level behavior.
* Wrapper-centric
  All jobs execute under a single wrapper to ensure uniform behavior.
* Observability-first
  Logs, exit codes, and reports are first-class outputs, not side effects.
* Boring by design
  Predictability is valued over cleverness.

---

### 1.4 Non-Goals

The engine explicitly does not aim to:

* Be a general workflow engine
* Replace cron or external schedulers
* Provide a generic logging framework
* Perform automatic recovery or remediation
* Make policy decisions about what should run or when

Those responsibilities belong to higher-level orchestration or human operators.

---

### 1.5 Engine Boundaries

The engine defines execution and observability contracts, not business logic.

Leaf scripts:

* contain domain-specific behavior
* must comply with engine contracts
* may evolve independently of the engine

The engine:

* enforces invariants
* provides visibility
* remains small, stable, and slow-moving

---

### 1.6 Stability & Contract Authority

This document is the authoritative specification for engine behavior.

Changes to:

* engine component responsibilities
* stdout/stderr semantics
* logging ownership
* exit code meanings
* artifact locations or formats

MUST be reflected here before being considered valid.

---

## 2. Cross-Cutting Contracts

### 2.1 Stdout / Stderr Contract

Standard output (`stdout`) and standard error (`stderr`) have **strict, non-overlapping roles** across all scripts in `obsidian-note-tools`.

This contract exists to ensure scripts are:

* Composable
* Machine-readable
* Debuggable
* Safe to embed in pipelines and generators

Violations of this contract are considered **bugs**, even if no immediate failure occurs.

---

#### 2.1.1 Stdout Is Sacred

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

#### 2.1.2 Stderr Is for Humans and Diagnostics

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

#### 2.1.3 Wrapper-Enforced Separation

`job-wrap.sh` enforces this contract by design:

* Leaf script `stdout` passes through untouched
* Leaf script `stderr` is intercepted, annotated, and written to log files
* The wrapper itself **never writes to stdout**

This guarantees that:

* Data output remains pristine
* Logs are complete and contextualized
* No script accidentally pollutes downstream consumers

---

#### 2.1.4 Silence Is Valid Output

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

#### 2.1.5 Error Conditions and Output

On failure:

* Partial or malformed data **MUST NOT** be written to stdout
* Error descriptions **MUST** go to stderr
* Exit status communicates failure (see Exit Code Semantics)

If a script cannot guarantee the correctness of its data output, it must:

* Emit nothing on stdout
* Fail loudly on stderr
* Exit non-zero

---

#### 2.1.6 Logging Helpers Must Respect the Contract

Shared helpers (e.g. `log.sh`) are designed to:

* Never write to stdout
* Default all output to stderr
* Fail fast if executed incorrectly

Leaf scripts **MUST NOT** implement ad-hoc `echo`-based logging that risks stdout pollution.

---

#### 2.1.7 Design Intent Summary

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

### 2.2 Logging Contract

All logging behavior in `obsidian-note-tools` is **centralized, structured, and enforced** by `job-wrap.sh`.

Logging is not an optional feature, nor a per-script concern. It is a **system-level responsibility** with strict boundaries.

---

#### 2.2.1 Single Logging Authority

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

#### 2.2.2 Log Capture Model

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

#### 2.2.3 Log File Structure

Each job execution produces:

* A **per-run log file**, named with a timestamp
  Example:

  ```
  <job>-<local timestamp>.log
  ```

* A **stable pointer** to the most recent run:

  ```
  <job>-latest.log
  ```

The `*-latest.log` file is a **symlink**, not a copy.

Consumers must treat it as a *pointer*, not an authoritative record.

---

#### 2.2.4 Log Buckets and Placement

Logs are stored under a shared log root, grouped into **buckets** that reflect job cadence and purpose (e.g. daily, weekly, long-cycle, other).

Bucket placement is a **wrapper concern**, not a leaf concern.

Leaf scripts:

* Do not know where their logs live
* Do not assume log paths
* Do not reference log files directly

This decoupling allows log layout to evolve without touching jobs.

---

#### 2.2.5 Structured Log Content

Logs may contain:

* Wrapper-emitted lifecycle metadata (start, end, exit status, timing)
* Annotated stderr output from the leaf script
* Wrapper-internal diagnostics (opt-in)
* Captured output from child commands

Logs **MAY** be human-readable, but they are not required to be machine-parseable.

Machine interpretation, when needed, must be layered on top by consumer tools (e.g. status reports).

---

#### 2.2.6 Logging Libraries Are Wrapper-Only

Shared logging helpers (e.g. `utils/core/log.sh`) exist to support the wrapper.

They are **library-only** and **MUST be sourced only by job-wrap.sh**.

Leaf scripts:

* MUST NOT source logging helpers
* MUST NOT call logging functions
* MUST NOT depend on logging internals

If a leaf script emits diagnostics, it does so by writing to `stderr` only.

---

#### 2.2.7 Failure Visibility Is Mandatory

Generated notes and data artifacts are the priority; logging is **best-effort**.

Even when a job fails catastrophically:

* A log file **SHOULD** exist
* Partial logs are acceptable
* Silent failure is not

Logging failure **MUST NOT** fail an otherwise healthy job.
An exception exists only when the logging failure implies the execution environment is unsafe or corrupted (e.g., disk errors, permissions regressions that also threaten artifacts).

---

#### 2.2.8 Design Intent Summary

This logging contract exists to enforce these invariants:

* Logs are **complete**
* Logs are **centralized**
* Logs are **consistent**
* Logs are **boring**

Leaf scripts should never need to think about logging.
If they are thinking about logging, the architecture has already failed.

### 2.3 Exit Code Semantics

Exit codes are the **primary machine-readable signal** of success or failure across the entire `obsidian-note-tools` ecosystem.

Exit codes must remain simple, predictable, and composable. Any script that exits with an ambiguous or misleading status is considered buggy.

---

#### 2.3.1 Wrapper Propagation Is Authoritative (Transparent Unless Wrapper Breaks)

`job-wrap.sh` MUST behave as a transparent execution harness unless the wrapper itself fails.

Exit Status Propagation
    •If the wrapper successfully starts and executes the leaf script to completion, the wrapper MUST exit with the leaf script’s exit status.
    •If the leaf exits 0, the wrapper exits 0.
    •If the leaf exits non-zero, the wrapper exits the same non-zero code.

This ensures that cron, calling scripts, and status-report tooling can treat the wrapper as transparent for leaf success or failure when the wrapper is healthy.

Wrapper Failure Override
    •If the wrapper fails before executing the leaf script, the wrapper MUST exit non-zero with a wrapper-defined failure code.
    •If the wrapper fails after executing the leaf script in a way that prevents reliable observability or publication of the run (e.g., required logs, markers, or vault commit cannot be produced), the wrapper MUST exit non-zero with a wrapper-defined failure code, even if the leaf script exited 0.

In such cases, the wrapper’s failure is considered authoritative, as the run is effectively lost or unverifiable.

Failure Classification

Wrapper failures MUST be classified as either:
    •Hard failures — failures that prevent reliable execution, observability, or publication of results; these override the leaf exit status.
    •Soft failures — ancillary or telemetry-related failures that do not prevent observability; these MUST be logged and reported but MUST NOT affect the wrapper’s exit status.

Exit Code Assignment (Deferred)
    •Specific numeric exit codes for wrapper-defined failures are intentionally not fixed in this section.
    •Wrapper failure codes MUST be:
    •non-zero
    •deterministic
    •documented
    •stable once defined

Assignment and reservation of specific wrapper exit codes will be specified in a future contract revision.

---

### 4.2 Meaning of `0`

Exit code `0` means:

* The job completed successfully
* The job’s intended outputs (files and/or stdout data) are believed correct
* Any warnings emitted to stderr did not invalidate correctness

“Success with warnings” is still `0` unless the warnings imply invalid output.

---

#### 2.3.3 Meaning of Non-Zero

Any non-zero exit code means:

* The job failed, or
* The job cannot guarantee the correctness of its outputs

On non-zero exit:

* Partial outputs MAY exist (side effects happen), but must be treated as suspect unless explicitly designed otherwise.
* Stdout MUST NOT contain partial/incorrect data (see Stdout/Stderr Contract).

---

#### 2.3.4 Reserved Exit Codes

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

#### 2.3.5 Soft Failure vs Hard Failure

The system intentionally does **not** define multiple success classes at the exit-code layer.

If a job must communicate nuance (e.g. “ran fine, but didn’t update anything”), it should:

* Exit `0`
* Emit an informational line to stderr (which will be logged)
* Optionally write structured data to stdout *only if that is its purpose*

If nuance must be machine-readable, it belongs in:

* A generated artifact (file output), or
* A future explicit “status output” design (not ad-hoc exit codes)

---

#### 2.3.6 Caller Responsibilities

Any script that calls another script MUST:

* Treat non-zero as failure
* Propagate failure unless explicitly handling it
* Avoid masking exit codes

If a caller intentionally handles a failure (rare), it must:

* Log/emit the reason to stderr
* Still ensure the overall system remains debuggable (logs exist, signals are visible)

---

#### 2.3.7 Wrapper Failures

If `job-wrap.sh` fails before the leaf script runs, the wrapper MUST exit non-zero and treat the failure as authoritative.

Examples:

* Cannot create log directory / file
* Cannot create needed temporary resources (e.g. FIFO) safely
* Required environment is missing in a way that makes execution unsafe

Wrapper failures must be loud on stderr and present in logs when possible.

---

#### 2.3.8 Design Intent Summary

Exit codes are designed to be:

* Boring
* Standard
* Dependable
* Interpretable by cron and automation without special casing

The system rejects “creative exit codes” as a communication channel.
If you need richer semantics, write richer artifacts—not weirder integers.

### 2.4 Run Cadence & Freshness

Many scripts in `obsidian-note-tools` are expected to run on a **defined cadence** (daily, weekly, hourly, ad-hoc, etc.).
Correctness is therefore not just *“did it run?”* but also *“did it run recently enough?”*.

This section defines how **run expectations** are communicated and how **freshness** is evaluated—without centralizing schedule knowledge in reporting code.

---

#### 2.4.1 Cadence Is a Property of the Job

Each job is the **authoritative source** of truth for how often it is expected to run.

Cadence knowledge **MUST NOT** live in:

* `script-status-report.sh`
* Cron configuration alone
* External documentation
* Hardcoded tables in summary tools

If a job’s cadence changes, the job itself must change.

---

#### 2.4.2 Declaring Expected Run Frequency

Each job **MUST declare** its expected run cadence in a machine-readable form that is emitted into its log on every run.

This declaration must be:

* Stable
* Explicit
* Easy to parse
* Human-readable in logs

The exact mechanism (e.g. a standardized stderr line or wrapper-supported metadata hook) is defined by convention, but the invariant is:

> Every log must contain enough information to determine when the *next* run was expected.

---

#### 2.4.3 Freshness Is Evaluated from Logs, Not Schedules

Freshness checks are based on **observed execution**, not intent.

Status and summary tools determine freshness by:

* Reading the most recent successful (or latest) log
* Extracting the declared cadence
* Comparing log timestamp to “now”

Cron entries may exist, but cron alone is **not evidence of execution**.

A missing or stale log is treated as a failure condition.

---

#### 2.4.4 Stale vs Missing

The system distinguishes between:

* **Missing**: no log exists for a job
* **Stale**: a log exists, but is older than allowed by cadence

Both conditions are failures, but they indicate different classes of problems:

* Missing → job never ran or logging broke
* Stale → scheduler failure, crash, or drift

---

#### 2.4.5 Latest Pointer Is Not Authoritative

The presence of `<job>-latest.log` does **not** imply freshness.

Consumers must:

* Resolve the symlink
* Inspect the timestamp of the underlying log
* Validate it against declared cadence

A stale symlink pointing to an old run is a detectable and reportable failure.

---

#### 2.4.6 Partial or Failed Runs

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

#### 2.4.7 Design Intent Summary

This contract exists to enforce the following principles:

* Jobs describe their own expectations
* Observed reality beats configured intent
* Status reporting scales without central knowledge
* Staleness is a first-class failure mode

If a job doesn’t state how often it should run,
the system cannot know whether silence is acceptable—or a fire alarm.

### 2.5 Environment & Paths

Scripts in `obsidian-note-tools` must execute reliably under cron, interactive shells, and automation contexts.
Therefore, scripts must treat the runtime environment as **hostile by default** and must not depend on implicit shell state.

This section defines what may be assumed and what must be explicitly established.

---

#### 2.5.1 Minimal, Explicit PATH

Scripts MUST NOT assume an interactive PATH.

Each executable script MUST explicitly set a safe baseline `PATH` early, typically:

* `/usr/local/bin:/usr/bin:/bin` (plus any existing PATH appended if desired)

The goal is:

* Deterministic command resolution
* Cron-safe execution
* Avoiding dependence on user dotfiles

---

#### 2.5.2 Stable Repo-Relative Resolution

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

#### 2.5.3 job-wrap Discovery

Leaf scripts MUST locate `job-wrap.sh` in a repo-stable way and re-exec through it as defined in the Execution Contract.

If `job-wrap.sh` cannot be found or is not executable, scripts MUST fail fast rather than silently running “unwrapped”.

---

#### 2.5.4 Environment Variable Usage

Scripts in this ecosystem MUST NOT rely on arbitrary or ambient environment variables for correctness.

Only environment variables explicitly defined as part of the ecosystem contract are permitted to influence control flow, output location, or correctness.

The authoritative list of environment variables currently observed in use — including their classification (required, optional override, or internal guard) — is maintained in Appendix A: Environment Variable Inventory (Informative).

**Requirements**

If a script depends on an environment variable to behave correctly, it MUST:

* Validate the variable early in execution
* Fail fast with a clear, single-line stderr error if the variable is missing or invalid

Scripts MUST:

* Provide explicit defaults for optional overrides
* Remain correct when optional environment variables are unset
* Avoid implicit reliance on user- or host-specific ambient variables

Introduction of any new environment variable that affects correctness, output location, or control flow MUST be accompanied by an update to this contract and the appendix.

---

#### 2.5.5 Working Directory

Scripts MUST NOT depend on the working directory.

* The working directory may be anything under cron or manual invocation.
* Scripts must use absolute paths for all filesystem operations, derived from `repo_root` and/or explicitly configured roots.

If a script intentionally changes directories, it must:

* Do so explicitly (`cd ...`)
* Treat failure to `cd` as fatal
* Avoid leaking relative path assumptions

---

#### 2.5.6 Temporary Files and Directories

Temporary resources MUST be created in a safe temp location:

* Prefer `${TMPDIR:-/tmp}`

Temp artifacts MUST:

* Use unique names (include PID and/or timestamps)
* Be cleaned up via traps where appropriate
* Avoid collisions across concurrent runs

---

#### 2.5.7 Portability and Shell Assumptions

All scripts target **POSIX `sh`**.

Scripts MUST NOT assume:

* Bashisms
* Arrays
* `pipefail`
* Non-POSIX `[[ ... ]]`
* GNU-only flags

For portability across shells and hosts:

* Unformatted data artifacts (e.g., `.log` files) MUST remain ASCII-only
* Formatted documents (e.g., Markdown) MAY use Unicode when it improves clarity and renders safely

Where platform behavior differs (BSD vs GNU), scripts must:

* Prefer portable forms
* Or isolate platform specifics behind helpers

---

#### 2.5.8 Design Intent Summary

This contract exists to ensure scripts are:

* Cron-safe
* Location-independent
* Deterministic
* Portable within the intended host constraints

If a script works “only when run from the repo root” or “only in my interactive shell”, that is a bug—not a quirk.

### 2.6 Idempotency & Side Effects

Scripts in `obsidian-note-tools` operate in an automated, often scheduled environment.
They must therefore be safe to run **repeatedly**, **out of order**, or **after partial failure** without causing corruption, duplication, or unintended drift.

This section defines expectations around idempotency and how side effects are handled.

---

#### 2.6.1 Idempotency Is the Default Expectation

Unless explicitly documented otherwise, scripts are expected to be **idempotent** with respect to their intended outcomes.

Running the same script multiple times with the same inputs should result in:

* The same filesystem state
* The same generated content
* No duplicate entries
* No accumulating noise

Idempotency does **not** mean “no work happens”; it means “no unintended change happens”.

---

#### 2.6.2 Side Effects Must Be Intentional and Bounded

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

#### 2.6.3 Safe Overwrite Beats Clever Deltas

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

#### 2.6.4 Atomicity and Partial Failure

Where feasible, scripts should aim for atomic outcomes:

* Write to a temporary file
* Validate output
* Move into place only on success

If a script fails mid-run:

* Partial artifacts may exist
* But they should be clearly incomplete or overwritten on the next successful run
* Silent corruption is unacceptable

---

#### 2.6.5 Git Side Effects Are Centralized

Scripts MUST NOT perform Git operations directly.

* Commits, staging, and repository interaction are handled by `job-wrap.sh`
* Scripts may create or modify files, but must not assume commit behavior
* Scripts must tolerate being run with commits disabled

This separation ensures that:

* Idempotency can be reasoned about independently of version control
* Jobs remain testable without Git side effects

---

#### 2.6.6 Time-Based Scripts and Determinism

Scripts that depend on “now” (current date/time) must do so explicitly and carefully.

Expectations:

* Date resolution is intentional (daily, hourly, etc.)
* Output for a given period is deterministic
* Re-running for the same period produces the same result

If a script is inherently non-idempotent (e.g. snapshotting external state), that fact must be documented clearly in the script header and contracts.

---

#### 2.6.7 Reruns Are a First-Class Use Case

The system assumes scripts may be:

* Re-run manually
* Re-run automatically after failure
* Run late
* Run multiple times in quick succession

Scripts must be written with the assumption that **reruns are normal**, not exceptional.

If a script cannot be safely re-run, that is an exceptional constraint and must be called out explicitly.

---

#### 2.6.8 Design Intent Summary

This contract exists to ensure that:

* Automation is safe
* Recovery is easy
* Failure is survivable
* Re-runs are boring

A script that only works “the first time” is not automated—it is fragile.

## 3. Component Contracts

### 3.1 Execution Contract (job-wrap)

All scripts in `obsidian-note-tools` execute under a **single, mandatory wrapper**:
`utils/core/job-wrap.sh`.

This wrapper defines the canonical execution environment for all jobs and is the *only* component permitted to manage logging, lifecycle metadata, and optional auto-commit behavior.

#### 3.1.1 Mandatory Re-exec via job-wrap

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

#### 3.1.2 job-wrap as the Sole Lifecycle Authority

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

#### 3.1.3 Single-Process Execution Model

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

#### 3.1.4 Wrapper Transparency

From the perspective of the leaf script:

* Invocation arguments are passed through unchanged
* Working directory is preserved
* Standard input is preserved
* Environment variables are preserved (with the addition of wrapper-specific variables)

The wrapper is designed to be **behaviorally transparent**, except where explicitly defined by other contracts (stdout/stderr handling, logging, exit semantics).

---

#### 3.1.5 Wrapper Availability Guarantee

All production execution paths (cron jobs, automation pipelines, manual invocations) **ASSUME** that:

* `job-wrap.sh` exists
* It is executable
* Its path is stable relative to the repository root

If `job-wrap.sh` is missing or non-executable, execution **MUST fail fast** rather than silently degrading behavior.

---

#### 3.1.6 Design Intent Summary

This execution contract exists to enforce the following invariants:

* There is exactly **one execution model**
* There is exactly **one logging authority**
* There is exactly **one place to reason about job behavior**
* Leaf scripts remain simple, testable, and boring

Any script that attempts to bypass or reimplement this contract is considered **incorrect by design**, even if it appears to “work”.

### 3.2 Logger Contract (log.sh)

**Status:** v0.1 — Early Draft

Heavy AI assistance. Requires manual review and validation.

#### 3.2.1 Role & Responsibility

`log.sh` is the shared logging helper for the engine.

It provides a small, stable set of logging primitives used by engine components, primarily `job-wrap.sh`.

It is intentionally minimal and opinionated to preserve engine invariants.

Violations of this contract are considered bugs.

#### 3.2.2 Library-Only (Sourcing) Contract

`log.sh` **MUST** be sourced, not executed.

If executed directly, `log.sh` **MUST**:

* emit a clear error to stderr
* exit with code 2

Rationale: the logger is a library, not a runnable job.

#### 3.2.3 Ownership & Call-Site Contract

`job-wrap.sh` is the primary owner of logging lifecycle (init, file selection, routing).

Leaf scripts **MUST NOT** source `log.sh` unless explicitly approved by contract.

Engine components other than `job-wrap.sh` **SHOULD NOT** source `log.sh` (default rule: wrapper-only).

If an exception exists (e.g., a diagnostic-only tool), it **MUST** be explicitly documented as a contract override.

#### 3.2.4 Output Contract (Stdout/Stderr)

`log.sh` **MUST NOT** write to stdout, under any circumstance.

All logger output **MUST** go to stderr or to an explicitly configured log file descriptor/path.

This protects data pipelines and wrapper “stdout is sacred” guarantees.

#### 3.2.5 Logging Primitives Contract

`log.sh` **MUST** provide stable, consistent primitives with predictable formatting.

At minimum:

* `log_init` (or equivalent) to establish logging context
* `log_info`, `log_warn`, `log_error` (and optionally `log_debug`)
* A way to emit captured command output as clearly marked lines (if supported)

Rules:

* Message formatting **MUST** be stable (timestamp + level + message).
* Timestamps **MUST** be in local time and explicitly labeled as such (see my [Manifesto on Time](https://github.com/deadhedd/manifesto-on-time/blob/main/manifesto.txt)).
* The logger **MUST** not require non-POSIX features.

#### 3.2.6 Determinism & Safety

Logging functions **MUST** be safe to call repeatedly.

The logger **MUST NOT** mutate caller state unexpectedly (no silent `cd`, no `PATH` rewrites, no global traps).

The logger **MUST** operate under `set -eu` callers without causing spurious exits.

If the logger needs to handle failure internally (e.g., cannot open a log file), it **MUST** degrade gracefully to stderr and/or return a non-zero status for the caller to handle.

#### 3.2.7 Internal Debug (Opt-in Only)

If the logger supports internal debugging:

* It **MUST** be strictly opt-in via environment knobs (e.g., `LOG_INTERNAL_DEBUG=1`)
* Debug output **MUST** go to stderr or an explicit debug file
* Debug output **MUST NOT** pollute stdout

Debug mode must never change the semantics of normal log messages.

#### 3.2.8 Compatibility Contract

`log.sh` **MUST** remain compatible with POSIX `sh` environments (e.g., sh/dash/ksh/ash).

* No bashisms
* No reliance on GNU-only flags
* Unformatted data files (e.g., `.log`) MUST be ASCII-only for compatibility
* Formatted documents (e.g., Markdown) MAY use Unicode when it improves clarity and renders safely

#### 3.2.9 Exit Code & Return Semantics

Logging functions **SHOULD** return 0 on success.

When a logging operation fails (e.g., file open failure), functions **MAY** return non-zero.

`log.sh` **MUST NOT** call `exit` except for the “executed directly” guard path.

The caller (typically `job-wrap.sh`) owns decisions about whether logging failures should fail the job.
The default posture is **non-fatal**: logging failures **MUST NOT** fail a job that can still produce its primary notes or data artifacts.
If a logging failure implies the execution environment is unsafe or corrupted (e.g., disk is read-only, filesystem errors), the caller **MAY** treat it as fatal to protect artifact integrity.

#### 3.2.10 Non-Goals

`log.sh` **MUST NOT**:

* Manage job execution lifecycle
* Decide log file paths or rotation policy (wrapper owns this)
* Implement auto-commit behavior
* Attempt to be a general logging framework

It exists to provide stable primitives that the wrapper composes.

#### 3.2.11 Stability Promise

The logger’s public function names, message format, and stdout/stderr behavior are engine-stable.

Any breaking change to:

* function names or signatures
* log line format (timestamp/level prefixing)
* destination semantics (stderr vs file)
* library-only behavior

**MUST** be accompanied by a contract revision.

### 3.3 Commit Helper Contract (commit.sh)

**Status:** v0.1 — Early Draft

Heavy AI assistance. Requires manual review and validation.

#### 3.3.1 Role & Responsibility

The commit helper is a single-purpose engine component responsible for:

* Staging an explicit set of files
* Creating a single Git commit in the configured repository
* Reporting the outcome via exit code only

The commit helper is not a general Git interface and not a standalone automation entrypoint.

Violations of this contract are considered bugs.

#### 3.3.2 Invocation Contract

The commit helper MUST be invoked by job-wrap.sh, either directly or via re-exec.

It MUST NOT be called directly from cron.

It MUST assume it is running inside an active job-wrap execution (`JOB_WRAP_ACTIVE=1`).

If invoked outside job-wrap, behavior is undefined unless explicitly guarded.

#### 3.3.3 Logging & Output Contract

The commit helper MUST NOT source log.sh.

The commit helper MUST NOT implement its own logging system.

The commit helper MUST NOT write anything to stdout.

Any human-readable or diagnostic output MAY be written to stderr.

All logging, capture, and persistence is owned exclusively by job-wrap.sh.

#### 3.3.4 Stdout / Stderr Semantics

**Stdout:**

* Reserved for data pipelines
* MUST remain empty at all times

**Stderr:**

* May be used for operational messages (e.g., “nothing to commit”)
* May be captured and logged by job-wrap
* Must not be relied upon programmatically

#### 3.3.5 Input Contract

The commit helper MUST operate only on explicitly provided inputs.

Typical inputs include:

* Work tree root
* Commit message (or message template)
* Explicit file list to stage and commit

Rules:

* The commit helper MUST NOT implicitly stage files (e.g., no `git add -A`)
* The commit helper MUST NOT infer files from directory state
* The commit helper MUST NOT modify files it was not explicitly given

#### 3.3.6 Idempotency & Safety

Re-running the commit helper with the same inputs MUST NOT corrupt repository state.

If there are no changes to commit, the helper MUST exit cleanly with a documented non-failure code.

Partial commits, mixed commits, or stateful retries are forbidden.

The commit helper is assumed to run in a controlled, deterministic environment.

#### 3.3.7 Exit Code Semantics

Exit codes are part of the public engine contract.

Recommended semantics (exact values may change, but meanings must not):

* `0` — Commit created successfully
* `3` — No changes to commit (non-failure)
* `10+` — Operational failure (Git error, invalid input, repository unavailable)

Exit codes below the failure threshold MUST NOT be interpreted as job failure by job-wrap.

#### 3.3.8 Non-Goals

The commit helper MUST NOT:

* Perform repository discovery
* Manage branches
* Resolve conflicts
* Implement retries or backoff
* Decide when commits should happen
* Decide what should be committed beyond its explicit inputs

Those responsibilities belong to the caller (`job-wrap.sh`) or higher-level orchestration.

#### 3.3.9 Stability Promise

The commit helper’s interface and semantics are considered engine-stable.

Any breaking change to:

* invocation shape
* exit code meanings
* stdout/stderr behavior

MUST be accompanied by a contract revision.

### 3.4 Status Report Contract (`script-status-report.sh`)

**Status:** v0.1 — Early Draft
Heavy AI assistance. Requires manual review and validation.

#### 3.4.1 Role & Responsibility

The status reporter is an **observational engine component** responsible for:

* Scanning job output artifacts (primarily `*-latest.log` pointers and their target logs)
* Classifying job health using documented heuristics
* Writing a **single, stable Markdown report** into the vault

It **MUST NOT** perform orchestration, scheduling, or remediation.

Violations of this contract are considered bugs.

---

#### 3.4.2 Invocation Contract

* The status reporter **MUST** be invoked by `job-wrap.sh`, either directly or via re-exec.
* It **MUST NOT** be called directly from cron.
* It **MUST** assume it is running inside an active job-wrap execution (`JOB_WRAP_ACTIVE=1`).

If invoked outside job-wrap, behavior is undefined unless explicitly guarded.

---

#### 3.4.3 Logging & Output Contract

* The status reporter **MUST NOT** source `log.sh`.
* The status reporter **MUST NOT** implement its own logging system.
* The status reporter **MUST NOT** write report content to stdout.
* Any human-readable operational output **MAY** be written to stderr.

All logging capture/persistence is owned exclusively by `job-wrap.sh`.

---

#### 3.4.4 Inputs & Data Sources

The status reporter’s inputs are **read-only** and **restricted** to engine artifacts.

It **MAY** read:

* The log root directory (canonical engine log location)
* `*-latest.log` pointers (files or symlinks) and their referenced latest run logs
* Optional per-job metadata files if explicitly defined by contract later

It **MUST NOT**:

* Execute leaf jobs
* Parse or modify vault notes as part of “fixing” anything
* Depend on external network resources

---

#### 3.4.5 Freshness Model

The reporter’s notion of “current state” is defined as:

* The **latest available run** per job, as indicated by that job’s `*-latest.log` pointer.

Rules:

* The reporter **MUST** treat the `*-latest.log` pointer as authoritative.
* It **MUST NOT** scan arbitrary historical logs unless explicitly configured to do so.
* It **MAY** flag a job as **stale** if the latest run timestamp exceeds a documented threshold.

Staleness thresholds (if present) **MUST** be explicit and deterministic.

---

#### 3.4.6 Classification Semantics

The reporter **MUST** classify each job into a small set of stable states. Recommended minimum set:

* **OK** — latest run indicates success
* **WARN** — latest run succeeded but contains warn patterns, or is stale
* **FAIL** — latest run indicates failure (exit code or error patterns)
* **UNKNOWN** — missing logs/pointers, unreadable log, or unparseable format

Classification rules **MUST** be:

* deterministic
* documented
* stable across releases unless contract-revved

If multiple signals conflict, precedence **MUST** be documented (e.g., FAIL > WARN > OK; UNKNOWN if missing required inputs).

---

#### 3.4.7 Required Signals

At minimum, the reporter **MUST** support:

* **Exit code extraction** from latest logs (canonical job-wrap emitted value)
* **Error/warn pattern detection** using a documented pattern set

Pattern sets:

* **MUST** be centralized (not hidden inside ad-hoc code paths)
* **MUST** avoid false positives where feasible
* **MUST** be treated as contract-affecting when changed

---

#### 3.4.8 Output Contract (Markdown Report)

The reporter **MUST** write exactly one Markdown report file at a stable path.

The report **MUST** be:

* valid Markdown
* stable in structure (headings/sections/table columns)
* safe to diff (minimal nondeterministic ordering)

At minimum, the report **SHOULD** include:

* generation timestamp (local time; see my [Manifesto on Time](https://github.com/deadhedd/manifesto-on-time/blob/main/manifesto.txt))
* summary counts by state (OK/WARN/FAIL/UNKNOWN)
* per-job rows including:

  * job name
  * latest run timestamp
  * latest exit code (if known)
  * classification state
  * short reason / key signal (e.g., “stale 3d”, “exit=1”, “pattern: ERROR”)
  * link or path hint to the latest log artifact (format may vary)

Ordering:

* Per-job listing order **MUST** be deterministic (e.g., lexical by job name).

---

#### 3.4.9 Side Effects & Idempotency

The status reporter is observational.

* It **MUST** only write its own output report file (and temporary files, if any).
* It **MUST NOT** modify logs, pointers, repositories, or other notes.
* It **MUST** be safe to run repeatedly without accumulating junk artifacts.

Any temporary files **MUST** be cleaned up on success and failure.

---

#### 3.4.10 Exit Code Semantics

Exit codes are part of the public engine contract.

Recommended semantics (exact values may change, but meanings must not):

* `0` — No failures detected (overall status OK/WARN only)
* `1` — One or more failures detected (any job classified FAIL)
* `2` — Reporter error (cannot read log root, cannot write report, internal error)

The reporter **MUST NOT** return `1` merely due to WARN or stale status (unless explicitly defined otherwise).

---

#### 3.4.11 Non-Goals

The status reporter **MUST NOT**:

* Trigger jobs
* Retry failures
* Auto-fix problems
* Modify job schedules
* Interpret business meaning of failures beyond documented heuristics

It is a *dashboard generator*, not an orchestrator.

---

#### 3.4.12 Stability Promise

The reporter’s **output structure and exit code meanings are engine-stable**.

Any breaking change to:

* report file path
* report section structure or table columns
* classification states or their meanings
* exit code meanings

**MUST** be accompanied by a contract revision.

---
