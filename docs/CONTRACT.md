**Status:** v0.9 — Final Polish

This document reflects the near-final script contracts for `obsidian-note-tools`.

- AI-assisted drafting was reviewed and revised
- Content has been validated; only final polish remains
- Contracts, language, and assumptions are stabilizing

Final proofreading is underway before treating this document as fully authoritative.

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
   7. Internal Identifiers and Leading-Underscore Convention
3. Component Contracts
   1. Execution Contract (job-wrap)
   2. Logger Contract (log.sh)
   3. Commit Helper Contract (commit.sh)
   4. Status Report Contract (report.sh + helpers)

---

## 1. Engine Overview

### 1.1 What the “Engine” Is

The engine is the core execution and observability layer of obsidian-note-tools.

It is composed of a small, tightly-scoped set of components that together provide:

* Deterministic job execution
* Strict stdout/stderr discipline
* Centralized, structured logging
* Configurable, wrapper-managed auto-commit mode when enabled
* A stable, human-readable system health report

The engine exists to make scripts boring, predictable, and auditable.

---

### 1.2 Terminology: Leaf Scripts vs Jobs

To avoid ambiguity, the engine distinguishes between:

* **Leaf script** — the executable script containing domain logic.
* **Job** — a wrapper-mediated execution/run of a leaf script (the unit that produces a log run).

This document uses **leaf script** when describing code artifacts and **job** when describing executions, logs, cadence, or freshness.

---

### 1.3 Engine Components

The engine consists of the following canonical components:

* `job-wrap.sh`
  The execution wrapper and lifecycle owner.
  Responsible for:
  * enforcing execution contracts
  * environment normalization
  * stdout/stderr routing
  * orchestrating auto-commit behavior **only when configured** (Git availability is not required for engine correctness)
* `log.sh`
  The shared logging helper library.
  Provides stable, minimal logging primitives.
  Owns logging lifecycle (creation, rotation, placement).
* `commit.sh`
  The commit helper.
  A single-purpose component that stages and commits an explicit file list when instructed.
* `report.sh`
  The reporting façade.
  Coordinates report generation and vault log copy helpers to summarize engine and job health for the vault.

No other scripts are considered part of the engine unless explicitly declared by contract.

---

### 1.4 Design Philosophy

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

### 1.5 Non-Goals

The engine explicitly does not aim to:

* Be a general workflow engine
* Replace cron or external schedulers
* Provide a generic logging framework
* Perform automatic recovery or remediation
* Make policy decisions about what should run or when

Those responsibilities belong to higher-level orchestration or human operators.

---

### 1.6 Engine Boundaries

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

### 1.7 Stability & Contract Authority

This document is the authoritative specification for engine behavior.

Changes to:

* engine component responsibilities
* stdout/stderr semantics
* logging ownership
* exit code meanings
* artifact locations or formats

MUST be reflected here before being considered valid.

---

### 1.8 End-to-End Execution Flow

Engine execution follows a single linear path from invocation to reporting:

1. **Invocation and re-exec** — Every leaf script immediately re-execs itself through `utils/core/job-wrap.sh`, ensuring the wrapper owns lifecycle, environment normalization, and stdout/stderr discipline.
2. **Wrapper initialization** — `job-wrap.sh` sets predictable `PATH`, detects the repository root, and establishes logging context before the leaf script logic runs.
3. **Logging bootstrapping** — The wrapper initializes the logging subsystem, which creates a dedicated per-run log file under the logs root, binds `stderr` to structured logging (including per-line annotation), and establishes the latest-run pointer.
4. **Leaf execution and artifacts** — The leaf script runs with wrapper-provided context, emits data to stdout (if any), and produces primary artifacts (files, markdown, JSON) directly in the repository or vault locations as defined by the script’s contract.
5. **Optional commit orchestration** — If the job configuration requests it, `job-wrap.sh` invokes `utils/core/commit.sh` with an explicit file list to stage and commit generated artifacts; commits never occur implicitly from the leaf script.
   Leaf scripts MUST remain correct when commit orchestration is disabled or unavailable.
6. **Out-of-band status reporting** — After runs, `utils/core/report.sh` invokes the reporting helpers to read wrapper-generated logs and pointers (not stdout) to classify job health, produce human-readable Markdown reports, and refresh vault log copies independent of the jobs’ data outputs.

Each run yields clean stdout for consumers, structured stderr-backed logs for humans, and optional commits and reports that remain fully deterministic.

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

> Nothing may be written to stdout unless it is part of the primary data product.

---

#### 2.1.X Internal Plumbing Exception (Logging Subsystem Only)

**Normative rule (still absolute at the boundary):**
`stdout` remains reserved exclusively for primary data output. No job or engine component may emit uncaptured bytes to `stdout` that reach the job boundary. Violations are bugs.

**Single exception (narrow and explicit):**
The logger subsystem’s internal helper libraries MAY write to `stdout` **only** as a private, internal data channel when the caller captures it completely (e.g., command substitution or a pipeline whose stdout is redirected/consumed). This exception exists solely to support POSIX `sh` “return a string” mechanics inside the logging stack.

**Prohibitions / guardrails:**

* This exception applies **only** to logger subsystem helpers (e.g., format/sanitize helpers) and **only** for internal plumbing. It does not apply to leaf scripts, jobs, or higher-level engine components.
* Logger helpers MUST NOT be invoked in a way that allows their stdout to reach the job boundary. Any code path that can leak helper stdout is a contract violation.
* `log.sh` itself MUST NOT write to stdout under any circumstance.

**Rationale (non-normative):**
POSIX `sh` provides no portable, ergonomic way to return computed strings from functions except via captured `stdout`. Capturing `stderr` for return values either (a) mixes diagnostics and data, or (b) requires brittle redirection gymnastics that are easy to get wrong and risk leaking noise into logs or data streams. Therefore, the logging subsystem is granted a single, explicit exception: helper functions may use stdout as an *internal* data channel only when the caller captures it fully. The boundary rule remains intact: job stdout stays pristine.

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
* Leaf script `stderr` is intercepted and routed verbatim into the logging subsystem (no wrapper parsing, tagging, or rewriting). The logging subsystem formats and writes the resulting log lines to the per-run log file.
* The wrapper itself **never writes to stdout**

This guarantees that:

* Data output remains pristine
* Logs are complete and contextualized
* No script accidentally pollutes downstream consumers

---

#### 2.1.4 Silence Is Valid Output

A script producing **no stdout output** is valid and meaningful.
Silence on stdout is valid only when paired with a meaningful exit code and logged stderr diagnostics.

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

All logging behavior in `obsidian-note-tools` is **centralized, structured, and enforced** by `log.sh`.

Logging is not an optional feature, nor a per-script concern. It is a **system-level responsibility** with strict boundaries.

---

#### 2.2.1 Single Logging Authority

`log.sh` is the **only component permitted to create, write, rotate, or manage log files**.
(This excludes presentation-layer copies produced by the status reporter.)

Leaf scripts **MUST NOT**:

* Create log files
* Decide log paths
* Rotate or prune logs
* Write timestamps or logger-format prefixes (e.g., [ts] [LEVEL] …). Leaf scripts MAY emit the contract-defined level prefix (DEBUG:/INFO:/WARN:/ERROR:) on stderr lines solely to enable logger policy gating.
* Manage “latest” pointers
* Commit logs to Git

Any script that writes directly to a log file is in violation of this contract.

Internally, `log.sh` coordinates a small set of wrapper-only helpers located under `utils/core/`:

* `log-format.sh` — sanitizes messages, applies ASCII-only rules, gates levels, and stamps each line with a timestamp.
* `log-sink.sh` — opens the log file on a dedicated FD, maintains the `*-latest.log` symlink, and prunes old runs according to `LOG_KEEP_COUNT`.
* `log-capture.sh` — reads wrapper-provided streams (e.g., stderr from the leaf) and rewrites them as timestamped, level-tagged log lines.

These helpers are **never** sourced directly; `log.sh` is the façade that wires formatting, capture, and sink management into a single logging authority.

---

#### 2.2.2 Log Capture Model

The logging model is intentionally simple and robust:

* Leaf script `stderr` is captured verbatim
* The wrapper routes this output verbatim to the logging subsystem, which formats and writes it to the per-run log file
* Each job run produces **exactly one log file**
* (Normative): Leaf level prefix protocol
* “Leaf script stderr lines MUST begin with an explicit level prefix: DEBUG:, INFO:, WARN:, or ERROR: (optionally followed by a single space).”
* (Normative): Logger-only parsing
* “The logging subsystem MAY perform strict parsing of this prefix for level gating. This parsing is considered logger policy gating (owned by log-format.sh / log-capture.sh), not wrapper interpretation.”
* (Normative): Missing prefix handling
* “Lines missing a valid prefix MUST be tagged as UNDEF by the logging subsystem.”
* The wrapper MUST NOT assign log levels to leaf output and MUST NOT inject any per-line markers into captured leaf stderr.

No ad-hoc filtering or heuristic parsing is applied at capture time. The only permitted parsing is strict recognition of the leaf log level prefix defined by this contract, performed by the logger subsystem as part of policy gating. The only permitted omission is explicit logger policy gating (e.g., level gating performed by `log-format.sh`), which is treated as a non-failure “no output by design” outcome. (See Appendix C.6 for logger helper return codes, including the non-failure “suppressed by policy” outcome.)
Policy gating MUST NOT rewrite or reinterpret message content; it only determines whether a line is emitted. Prefix recognition MUST NOT alter the message payload; the full original line content MUST remain visible in logs (with UNDEF used when the prefix is missing/invalid).

This guarantees:

* Complete diagnostic fidelity
* No loss of context
* Postmortem debuggability

---

#### 2.2.2.X Leaf Level Prefix Protocol (Normative)

Leaf-level stderr diagnostics MUST follow the level prefix protocol to enable deterministic logger policy gating.

**Allowed levels**

* DEBUG
* INFO
* WARN
* ERROR

**Required syntax**

* `^(DEBUG|INFO|WARN|ERROR):[ ]?`

**Line discipline**

* One line equals one message (no embedded newlines).
* Control characters are not allowed, per ASCII-only log rules.

**Missing/invalid prefix**

* Lines missing a valid prefix are tagged as `UNDEF` by the logging subsystem.

**UNDEF handling**

* `UNDEF` lines SHOULD always be emitted regardless of `LOG_MIN_LEVEL` to surface protocol violations.

---

#### 2.2.3 Log File Structure

Each job execution produces:

* A **per-run log file**, named with a timestamp
  Example:

  ```
  <job>-2026-01-10-070512.log
  ```

* A **stable pointer** to the most recent run:

  ```
  <job>-latest.log
  ```

The `*-latest.log` file is a **symlink**, not a copy.

It is authoritative only for identifying the most recent observed run, never for determining freshness, correctness, or health.

---

#### 2.2.3.1 Log Filename Invariants (Normative)

Per-run log filenames MUST be generated by the logger subsystem and MUST be deterministic and parse-free to consume.

**Character constraints**

* Log filenames MUST be ASCII-only.
* Log filenames MUST NOT contain whitespace or newlines.

**Sortable timestamp requirement**

* The timestamp component in per-run log filenames MUST use a lexicographically sortable **local-time** format such that string sort order matches chronological order.
* The timestamp format MUST be fixed-width and zero-padded.

**Filename shape**

* Per-run logs MUST use the form:

  ```
  <job>-<ts>.log
  ```
* `<job>-latest.log` remains a symlink pointer to the most recent per-run log.

**Timestamp format selection**

* The canonical `<ts>` format is: `YYYY-MM-DD-HHMMSS` (local time).
* Example: `2026-01-10-070512`

**Stability**

* Changing the canonical `<ts>` format is a contract-breaking change and MUST be accompanied by a contract revision.

---

#### 2.2.4 Log Buckets and Placement

Logs are stored under a shared log root, grouped into **buckets** that reflect job cadence and purpose (e.g. daily, weekly, long-cycle, other).

Bucket placement is a **logger concern**, not a leaf concern.

Leaf scripts:

* Do not know where their logs live
* Do not assume log paths
* Do not reference log files directly

This decoupling allows log layout to evolve without touching jobs.

---

#### 2.2.4.X Retention Scope (Normative)

* Retention pruning performed by the logger subsystem (`log-sink.sh`) **MUST** be **directory-local**.
* “Directory-local” means: pruning considers only per-run log files that are **direct children** of the directory that contains the current run’s `LOG_FILE`.
* The logger **MUST NOT** recurse into subdirectories when pruning logs.
* The logger **MUST** prune only files matching the per-run log filename shape (`<job>-<ts>.log`) and **MUST NOT** treat `*-latest.log` as a retention candidate.

---

#### 2.2.5 Structured Log Content

Logs may contain:

* Wrapper-emitted lifecycle metadata (start, end, exit status, timing)
* Annotated stderr output from the leaf script
* Wrapper-internal diagnostics (opt-in)
* Captured output from child commands

Logs **MAY** be human-readable, but they are not required to be machine-parseable.

Any machine interpretation of log content (e.g., classification, warnings, or health status) MUST be performed by separate consumer tools, not implied by the log format itself.

---

#### 2.2.6 Logging Libraries Are Wrapper-Only

Shared logging helpers (e.g. `utils/core/log.sh`) exist to support the wrapper.

They are **library-only** and **MUST be sourced only by job-wrap.sh**.

Leaf scripts:

* MUST NOT source logging helpers
* MUST NOT call logging functions
* MUST NOT depend on logging internals

If a leaf script emits diagnostics, it does so by writing to `stderr` only. When a leaf script emits diagnostics to stderr, each line MUST follow the Leaf Level Prefix Protocol defined in §2.2.2.

---

#### 2.2.7 Character Encoding

Unformatted data outputs (e.g., `*.log` files) **MUST** remain ASCII-only:

* Avoid locale-dependent characters in raw logs
* Treat non-ASCII bytes in log output as a bug to be fixed

Formatted human-facing documents (e.g., Markdown `*.md`) **MAY** include Unicode characters when it improves clarity.

---

#### 2.2.8 Failure Visibility Is Mandatory

Even when a job fails catastrophically:

* A log file **SHOULD** exist (best-effort); if it cannot be produced, `stderr` diagnostics MUST remain intact
* Partial logs are acceptable
* Silent failure is not

Generated notes and data artifacts are the priority.
Logging failures follow a two-tier rule:

* **Soft**: file-backed logging is unavailable or incomplete but execution remains safe (and `stderr` remains intact) → the job continues
* **Hard**: the logging failure is evidence of a corrupted or unsafe execution context → wrapper failure

**Unsafe execution context (normative)**

Loss of file-backed logs **alone** MUST NOT be treated as unsafe.
A logging failure qualifies as **Hard** only when it provides evidence that wrapper-managed execution safety is compromised.

Examples of evidence that MAY qualify as unsafe include:

* wrapper cannot create or manage required temporary resources (and therefore cannot execute deterministically)
* wrapper invariants are violated (e.g., recursion/nesting guards broken)
* engine wiring is inconsistent or partially deployed (e.g., required engine components cannot be sourced or executed)
* the failure indicates broader filesystem or permission corruption likely to affect job artifacts, not just logs

All other logging failures (including inability to create/update log files or latest pointers) MUST be treated as Soft.

Logging must be best-effort and must not fail jobs unless the hard condition is met.

**Policy summary (normative):** Job outputs are the priority; logging is best-effort. Missing logs are acceptable. Only safety-compromising evidence warrants wrapper failure.

---

#### 2.2.9 Design Intent Summary

This logging contract exists to enforce these invariants:

* Logs are **complete**
* Logs are **centralized**
* Logs are **consistent**
* Logs are **boring**

Leaf scripts should never need to think about log files, log paths, timestamps, rotation, or sinks. If they emit diagnostics, they MUST follow the level prefix protocol.
If they are thinking about logging, the architecture has already failed.

#### 2.2.10 Internal Engine Debugging (Opt-In)

The engine MAY support internal debugging output intended to aid development, diagnosis, and validation of engine behavior itself (e.g., wrapper lifecycle, logging sink behavior, report classification decisions).

Internal debugging output is not job output and is strictly observational.

**Rules and Invariants:**

* Internal debugging MUST be explicitly opt-in.
* Internal debugging MUST be disabled by default.
* Internal debugging MUST NOT write to stdout under any circumstance.
* Internal debugging MUST NOT alter:
  * job execution order
  * job stdout or stderr semantics
  * exit codes
  * classification outcomes
  * commit behavior
* Internal debugging output MUST be treated as diagnostic-only and MUST NOT be relied upon programmatically.

**Scope:**

Internal debugging MAY emit information about:

* wrapper decision paths
* logging initialization and routing
* sink creation and pruning
* reporter classification logic
* internal invariant checks

Internal debugging MUST NOT:

* expose leaf script data beyond what is already present in logs
* change the meaning or structure of standard logs
* become required for correct operation

**Destination:**

Internal debugging output:

* MAY be written to stderr
* MAY be written to a dedicated debug log or stream
* MUST remain logically and visually distinct from normal job logs

Failure or absence of internal debugging output MUST NOT be treated as an error.

### 2.3 Exit Code Semantics

Exit codes are the **primary machine-readable signal** of success or failure across the entire `obsidian-note-tools` ecosystem.

Exit codes must remain simple, predictable, and composable. Any script that exits with an ambiguous or misleading status is considered buggy.

---

#### 2.3.1 Wrapper Propagation Is Authoritative (Transparency-with-Authority Rule)

The **Transparency-with-Authority Rule**: `job-wrap.sh` behaves as a transparent execution harness while it can fulfill its contract; if the wrapper fails (pre-leaf or post-leaf) in a way that blocks reliable observability or publication, the wrapper’s reserved exit code overrides the leaf.

This section states the foundational invariant governing wrapper behavior and all exit-code propagation rules.

**Exit Status Propagation**

* If the wrapper is healthy and executes the leaf script to completion, the wrapper MUST exit with the leaf script’s exit status.
* If the leaf exits `0`, the wrapper exits `0`.
* If the leaf exits non-zero, the wrapper exits the same non-zero code.

This ensures that cron, calling scripts, and status-report tooling can treat the wrapper as transparent for leaf success or failure when the wrapper is healthy.

**Wrapper Failure Override**

* If the wrapper fails before executing the leaf script, the wrapper MUST exit non-zero with a wrapper-defined failure code.
* If the wrapper fails after executing the leaf script in a way that indicates an unsafe execution context or prevents a **contract-required** publication step (e.g., required markers or required vault commit) from being produced, the wrapper MUST exit non-zero with a wrapper-defined failure code, even if the leaf script exited `0`.
* Wrapper health → propagate leaf exit code; wrapper failure (pre- or post-leaf) that blocks required observability/publication → reserved wrapper code is authoritative.

In such cases, the wrapper’s failure is considered authoritative, as the run is effectively lost or unverifiable.

File-backed logging loss alone is not sufficient to trigger a post-leaf override unless it also meets the “unsafe execution context” definition in §2.2.8.

**Failure Classification**

Wrapper failures MUST be classified as either:

* Hard failures — failures that prevent reliable execution, observability, or publication of results; these override the leaf exit status.
* Soft failures — ancillary or telemetry-related failures that do not prevent observability; these MUST be logged and reported but MUST NOT affect the wrapper’s exit status.

**Exit Code Assignment (Deferred)**

* Specific numeric exit codes for wrapper-defined failures are intentionally not fixed in this section.
* Wrapper failure codes MUST be:
  * non-zero
  * deterministic
  * documented
  * stable once defined

Assignment and reservation of specific wrapper exit codes will be specified in a future contract revision.

---

#### 2.3.2 Meaning of `0`

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

##### `2` — Contract / Wrapper-Level Misuse

Exit code `2` is reserved for cases like:

* A library-only helper was executed instead of sourced
* A required invariant for safe execution is violated
* Wrapper initialization fails in a way that makes execution unsafe

This is a “you called this wrong / you broke the rules” signal.

> Leaf scripts SHOULD avoid using exit code `2` for their own failure modes.

##### `126` / `127` — Standard Exec Failures

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

Some internal engine helpers may return documented non-failure outcomes (e.g., “suppressed by policy”) that MUST NOT be interpreted as job failure; see Appendix C.6.

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

Logging failures are classified per §2.2.8:

* **Soft** failures (log file missing, `stderr` intact) are **not** wrapper failures and MUST allow the job to continue.
* **Hard** failures (logging implies a corrupted or unsafe execution context) are wrapper failures and override the leaf exit.

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

Each leaf script is the **authoritative source** of truth for how often its jobs are expected to run.

Cadence knowledge **MUST NOT** live in:

* `report.sh` or its helpers
* Cron configuration alone
* Internal registries or status indexes
* External documentation
* Hardcoded tables in summary tools

If the expected cadence changes, the leaf script itself must change.

---

#### 2.4.2 Declaring Expected Run Frequency

Each leaf script **MUST declare** the expected run cadence for its jobs in a machine-readable form that is emitted into each job log on every run.

Failure of a leaf script to declare cadence is an **error condition**, not an implicit “unknown” cadence.
Leaf scripts with ad-hoc or inherently unknowable cadence **MUST still declare that fact explicitly** (e.g. `cadence=ad-hoc`).

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

The reporter MAY distinguish between:

* Missing: no log exists for a job
* Stale: a log exists, but is older than allowed by cadence

Both conditions indicate an unhealthy job, but suggest different problem classes:

* Missing → job never ran, job not registered, or logging broke
* Stale → scheduler failure, crash, hang, or drift

---

#### 2.4.5 Latest Pointer Is Authoritative Only for Identity

The presence of `<job>-latest.log` does **not** imply freshness.

The `*-latest.log` pointer is authoritative for identity, not for health: it identifies the most recent observed run, but it is never evidence of freshness, correctness, or health.

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

Each executable script MUST explicitly set a safe baseline `PATH` early, using:

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

If `job-wrap.sh` cannot be found or is not executable, scripts MUST fail fast and loud rather than silently running “unwrapped”.

---

#### 2.5.4 Environment Variable Usage

Scripts in this ecosystem MUST NOT rely on arbitrary or ambient environment variables for correctness.

Only environment variables explicitly defined as part of the ecosystem contract are permitted to influence control flow, output location, or correctness.

The authoritative list of environment variables currently observed in use — including their classification (required, optional override, or internal guard) — is maintained in Appendix A: Environment Variable Inventory (Informative).

Logger helper context variables (for example, `LOG_SINK_FD` and `LOG_MIN_LEVEL`) are internal to the logger subsystem and documented under §3.2 and Appendix D; they are not part of the public environment contract for leaf scripts.

**Requirements**

If a script depends on an environment variable to behave correctly, it MUST:

* Validate the variable early in execution
* Fail fast with a clear, single-line stderr error if the variable is missing or invalid

Scripts MUST:

* Provide explicit defaults for optional overrides
* Remain correct when optional environment variables are unset
* Avoid implicit reliance on user- or host-specific ambient variables

Introduction of any new environment variable that affects correctness, output location, or control flow MUST be accompanied by an update to this contract and the appendix.

##### Core engine environment variables

Core engine components enforce the following environment variable requirements:

* `JOB_WRAP_ACTIVE` **MUST** be set to `1` inside job-wrap-managed execution, and the wrapper **MUST** exit if the value is missing or invalid before invoking leaf scripts.
  * `log.sh` additionally asserts wrapper-context before initializing the logging subsystem.
* `JOB_NAME` **MUST** be present, non-empty, and **valid** when the logging sink initializes.
  * When sourced, logger helpers (including the sink) **MUST NOT** call `exit` for missing/invalid required façade-provided context.
  * Missing/invalid `JOB_NAME` is **logger helper misuse**: the helper **MUST** emit one diagnostic line to stderr and **MUST return `11`**.
  * Escalation (soft degrade vs wrapper failure) remains owned by `log.sh` / `job-wrap.sh`.
* `LOG_FILE` **MUST** be set and non-empty after successful logging sink initialization.
  * The sink generates `LOG_FILE` according to the Log Filename Invariants (§2.2.3.1).
  * If a logger helper that requires a fully initialized sink is invoked without `LOG_FILE`, that helper **MUST** treat it as misuse (emit one diagnostic line to stderr and return `11`).

Optional overrides such as `VAULT_PATH`, `LOG_ROOT`, `TMPDIR`, `COMMIT_BARE_REPO`, and `GIT_BIN` **MUST** fall back to deterministic defaults, and components **MUST** remain correct when they are unset.

Internal guards and debug toggles (for example, `LOG_SINK_LOADED`, `LOG_FACADE_ACTIVE`, `JOB_WRAP_DEBUG`, or `LOG_ASCII_ONLY`) are implementation details and **MUST NOT** be treated as part of the public environment contract.

Validation and defaulting behavior for all other core engine variables is described in Appendix A.

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
* Git presence is not an engine prerequisite; correctness of leaf scripts must not depend on auto-commit being available

This separation ensures that:

* Idempotency can be reasoned about independently of version control
* Leaf scripts remain testable without Git side effects

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

---

### 2.7 Internal Identifiers and Leading-Underscore Convention

The engine distinguishes between public, contract-governed interfaces and internal implementation details using naming conventions.

#### 2.7.1 Leading Underscore Convention

Any variable or function name beginning with a leading underscore (for example, `_lf_ts`, `_tmp`, `_internal_helper`) is considered **internal**.

Internal identifiers:

* are implementation details
* are **not** part of the public contract surface
* have no stability guarantees
* may change, be renamed, or be removed without a contract revision

Identifiers **without** a leading underscore are considered part of the component’s public interface unless explicitly documented otherwise.

Callers MUST NOT rely on internal identifiers.

### 2.8 Trusted Internal Components & Fail-Fast Assumption

This system operates as a closed, trusted environment.

All engine components, helpers, and documented leaf scripts are assumed to:

* exist at their contracted paths
* be executable where required
* conform to their documented interfaces and behaviors

As a result, defensive checks for the presence, discoverability, or validity of internal components are intentionally omitted.

#### 2.8.1 Scope of the Assumption

This assumption applies to:

* Core engine components (`job-wrap.sh`, `log.sh`, `commit.sh`, `report.sh`)
* Wrapper-only helpers under `utils/core/`
* Documented leaf scripts invoked as part of the system
* Internal libraries and helper functions sourced by engine components

These components are treated as correct-by-construction and version-controlled as a unit.

#### 2.8.2 Failure Semantics

If an internal component is:

* missing
* non-executable
* malformed
* incompatible with its documented contract

the resulting failure is considered a bug or configuration error, not a runtime condition to be handled gracefully.

In such cases, the system MUST fail fast and visibly, allowing:

* shell diagnostics to surface naturally on stderr
* wrapper or engine failures to propagate via exit codes
* logs to capture the failure context where possible

Silent recovery, fallback behavior, or partial execution is explicitly disallowed.

#### 2.8.3 Rationale (Non-Normative)

Defensive coding at internal boundaries is intentionally avoided because it would:

* obscure real errors and misconfigurations
* mask contract violations
* increase cognitive and maintenance overhead
* introduce misleading “successful” states
* degrade determinism and observability

The system prefers early, loud failure over graceful degradation when internal assumptions are violated.

#### 2.8.4 External Boundaries

This contract does not prohibit validation or defensive handling at true external boundaries, such as:

* user input
* environment variables that affect correctness
* filesystem state outside contracted roots
* external tools or network resources

Defensive checks are appropriate at those boundaries and are governed by their respective contracts.

#### 2.8.5 Design Intent Summary

This contract exists to enforce the following principle:

Internal correctness is enforced by contract, documentation, and version control — not by runtime guards.

If an internal dependency breaks, the system should stop, not guess.

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
* Exit code propagation
* An optional auto-commit mode that may be disabled without affecting engine correctness

Logging lifecycle and helper sourcing are governed by §2.2 (Logging Contract) and §3.2 (Logger Contract).
`job-wrap.sh` enforces that centralized model; leaf scripts must rely on it rather than sourcing `log.sh` or child helpers directly.

Leaf scripts **MUST NOT**:

* Commit files to Git
* Implement their own lifecycle wrappers

Any such behavior is a contract violation.

---

#### 3.1.3 Single-Process Wrapper Model

The execution model is intentionally **single-wrapper, single-shell**:

* `job-wrap.sh` remains the sole lifecycle owner for the duration of the job run.
* The leaf script is executed as a **program in a child process** (not sourced).
* No subshell constructs, pipelines, or background execution are introduced by the wrapper by default.
* The leaf process inherits the wrapper’s exported environment variables and working directory.
* `stdout` remains sacred (unchanged); `stderr` routing is controlled by the wrapper per the Stdout/Stderr and Logging Contracts.

This enables:

* Reliable exit code propagation (leaf exit status is captured and returned by the wrapper)
* Deterministic cleanup and shutdown handling (signals, traps, temp files) owned by the wrapper
* Post-run orchestration steps (structured log finalization, optional commit orchestration) without leaf involvement
* A clear process boundary: leaf scripts run as normal executables while the wrapper enforces invariants

---

#### 3.1.3.X Leaf `stderr` Capture Transport (Normative)

To preserve the Stdout/Stderr Contract and the Logging Contract while remaining portable to POSIX `sh`,
`job-wrap.sh` MUST capture leaf-script `stderr` using a temporary file buffer and then forward that
buffer into the logging subsystem.

**Required behavior**

* The wrapper MUST execute the leaf as a program in a child process.
* The wrapper MUST redirect leaf `stderr` to a wrapper-owned temporary file (or equivalent stable buffer).
* After the leaf exits, the wrapper MUST forward the captured bytes into the logging subsystem
  (e.g., `log-capture.sh`) **without modification**.
* The wrapper MUST NOT assign log levels, inject markers, or rewrite leaf `stderr` content.
  Logger-only parsing (level prefix gating) remains owned by the logging subsystem.

**Prohibited mechanisms (portability + semantics)**

Because POSIX `sh` lacks portable process substitution and because pipelines alter exit-code and stream
semantics, the wrapper MUST NOT implement leaf `stderr` capture by:

* process substitution (non-POSIX)
* piping leaf output directly into logger processes
* merging `stdout`/`stderr` to achieve capture
* introducing wrapper-owned pipelines as the default execution path

These approaches risk violating the “stdout is sacred” boundary, wrapper transparency, and reliable
exit-code propagation.

**Fallback behavior**

If the wrapper cannot create a temporary capture file/buffer, it MAY degrade to `stderr` passthrough
for observability (leaf `stderr` reaches the job boundary intact). This is a *soft logging failure*:
job correctness and exit-code propagation MUST remain unchanged, and the wrapper MUST NOT treat this
condition alone as evidence of an unsafe execution context.

---

#### 3.1.4 Wrapper Transparency

From the perspective of the leaf script:

* Invocation arguments are passed through unchanged
* Working directory is preserved
* Standard input is preserved
* Environment variables are preserved (with the addition of wrapper-specific variables)

The wrapper is designed to be **behaviorally transparent** under the Transparency-with-Authority Rule, except where explicitly defined by other contracts (stdout/stderr handling, logging, exit semantics).

---

#### 3.1.5 Wrapper Availability Guarantee

All production execution paths (cron jobs, automation pipelines, manual invocations) **ASSUME** that:

* `job-wrap.sh` exists
* It is executable
* Its path is stable relative to the repository root

If `job-wrap.sh` is missing or non-executable, execution **MUST fail fast and loud** rather than silently degrading behavior.

---

#### 3.1.6 Design Intent Summary

This execution contract exists to enforce the following invariants:

* There is exactly **one execution model**
* There is exactly **one logging authority**
* There is exactly **one place to reason about job behavior** and, when enabled, commit orchestration
* Leaf scripts remain simple, testable, and boring

Any script that attempts to bypass or reimplement this contract is considered **incorrect by design**, even if it appears to “work”.

### 3.2 Logger Contract (log.sh)

#### 3.2.1 Role & Responsibility

`log.sh` is the shared logging helper for the engine.

It provides a small, stable set of logging primitives used by engine components, primarily `job-wrap.sh`.

It is intentionally minimal and opinionated to preserve engine invariants.

`log.sh` is the **façade and coordinator** for the logger subsystem. It sources and orchestrates the following child helpers (all wrapper-only):

* `log-format.sh`
* `log-sink.sh`
* `log-capture.sh`

Because POSIX `sh` cannot portably discover the library’s own path when sourced, the wrapper **MUST** provide `LOG_LIB_DIR`.

---

#### Logger façade ownership and failure semantics (Normative)

`log.sh` is the **sole authority** responsible for:

* validating wrapper context (`JOB_WRAP_ACTIVE=1`)
* establishing façade ownership by setting `LOG_FACADE_ACTIVE=1`
* supplying required sink inputs (`JOB_NAME`)
* supplying logger configuration inputs (for example: `LOG_ROOT`, `LOG_BUCKET`, `LOG_KEEP_COUNT`, `LOG_MIN_LEVEL`) when present, with deterministic defaults when absent
* initializing the logging sink (`log-sink.sh`) and publishing sink outputs to the wrapper context
  * **Sink outputs include:** `LOG_FILE` (per-run log path) and `LOG_SINK_FD` (open FD for the active sink)
* deciding whether logger helper failures escalate to wrapper failure

`LOG_FACADE_ACTIVE=1` means the log façade has been sourced/initialized and owns the façade context for the current wrapper execution. It is an internal guard variable, not part of the public environment contract for leaf scripts.

Logger child helpers (including `log-sink.sh`) operate under the following strict rules:

##### LOG_FILE ownership (Normative)

`LOG_FILE` is **generated by the logging sink** (`log-sink.sh`) as part of sink initialization.

* The wrapper MUST NOT configure, select, or pass in a log filename.
* The sink MUST generate `LOG_FILE` according to the Log Filename Invariants (§2.2.3.1).
* After successful sink initialization, `LOG_FILE` MUST be set, non-empty, and refer to the current run’s per-run log file.
* If sink initialization degrades (soft logging failure), `LOG_FILE` MAY be unset; the façade remains responsible for degradation behavior and signaling.

##### Required context handling

* Logger helpers **MUST NOT call `exit` when sourced**, except for the “executed directly” misuse guard.
* When required façade-provided context is missing or invalid (for example, missing `JOB_NAME` or `LOG_LIB_DIR`):

  * Logger helpers **MUST treat this as misuse**
  * Logger helpers **MUST emit a single diagnostic line to stderr**
  * Logger helpers **MUST return exit code `11`**
* Logger helpers **MUST NOT attempt to recover, infer defaults, or silently degrade behavior** in this situation.

Note: `LOG_FILE` is not façade-provided input. It is a sink output produced during initialization.
Logger helpers MUST treat missing `LOG_FILE` as misuse (`11`) only when they are invoked in a context that requires a successfully initialized sink (i.e., the façade called them out of order).

##### Logger helper context variables (façade-provided, internal)

* These variables are an **internal contract** between `log.sh` and logger helpers.
* They are **not** part of the external/public environment contract (they are not guaranteed for leaf scripts).
* Logger helpers **MUST** treat missing or invalid values as **misuse** and **MUST** return `11` with a single diagnostic line to stderr.
* `log.sh` remains the **sole authority** to set these variables and decide escalation.

The façade-provided internal variables include:

* `LOG_LIB_DIR`
  * **Meaning:** absolute (or resolvable) directory containing logger child helpers (`log-format.sh`, `log-sink.sh`, `log-capture.sh`).
  * **Owner:** `job-wrap.sh` (or the engine wiring path that sources `log.sh`).
  * **Consumers:** `log.sh` (to source logger children).
  * **Validity:** non-empty; MUST refer to an existing directory; SHOULD be an absolute, physical path (or must be normalizable to one).
  * **Missing/invalid:** misuse → return `11`.
* `LOG_SINK_FD`
  * **Meaning:** open file descriptor for the active log sink (where capture writes).
  * **Validity:** non-empty, numeric, and refers to an open FD suitable for `printf ... >&FD`.
  * **Owner:** `log.sh` (or the sink init path it orchestrates).
  * **Consumers:** `log-capture.sh`.
  * **Missing/invalid:** misuse → return `11`.
* `LOG_MIN_LEVEL`
  * **Meaning:** policy gate threshold passed into the formatter.
  * **Validity:** non-empty; must be one of the supported levels defined by the formatter.
  * **Owner:** `log.sh`.
  * **Consumers:** `log-capture.sh` / formatter calls.
  * **Missing/invalid:** misuse → return `11`.

##### Operational failures

* When a logger helper encounters an operational failure (for example, cannot create a directory, cannot open a log file, cannot update the latest symlink):

  * The helper **MUST emit a diagnostic line to stderr**
  * The helper **MUST return exit code `10`**

##### Escalation authority

* Logger helpers **MUST NOT decide whether a failure is fatal to the job**
* `log.sh` (and ultimately `job-wrap.sh`) is the **sole authority** that decides whether:

  * a helper failure degrades to stderr-only logging (soft failure), or
  * a helper failure constitutes a corrupted or unsafe execution context (hard failure)

This preserves centralized policy, deterministic behavior, and wrapper authority.

---

#### Library-only contract

`log.sh` and all logger child helpers **MUST be sourced, not executed**.

If executed directly:

* The component **MUST** emit a clear error to stderr
* The component **MUST** exit with code `2`

This rule applies uniformly to:

* `log.sh`
* `log-format.sh`
* `log-sink.sh`
* `log-capture.sh`

---

#### Output contract

* `log.sh` **MUST NOT** write to stdout under any circumstance.
* Logger child helpers **MAY** use stdout **only** under the Internal Plumbing Exception (§2.1.X), and only when fully captured.
* No logger output may reach the job stdout boundary.

#### 3.2.2 Library-Only (Sourcing) Contract

`log.sh` **MUST** be sourced, not executed.

If executed directly, `log.sh` **MUST**:

* emit a clear error to stderr
* exit with code 2

Rationale: the logger is a library, not a runnable job.

The logger’s child helpers (`log-format.sh`, `log-sink.sh`, `log-capture.sh`) are also library-only. If any logger helper is executed directly, it **MUST** print a clear error to stderr and exit 2 to signal misuse.

#### 3.2.3 Ownership & Call-Site Contract

`job-wrap.sh` is the primary owner of logging lifecycle (init, file selection, routing).

Leaf scripts **MUST NOT** source `log.sh` unless explicitly approved by contract.

Engine components other than `job-wrap.sh` **SHOULD NOT** source `log.sh` (default rule: wrapper-only).

If an exception exists (e.g., a diagnostic-only tool), it **MUST** be explicitly documented as a contract override.

#### 3.2.4 Output Contract (Stdout/Stderr)

**Normative:**

* `log.sh` MUST NOT write to `stdout` under any circumstance.
* Logger child helpers MAY use `stdout` only under the Internal Plumbing Exception (§2.1.X) and must not produce observable stdout at the job boundary.

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
* Timestamps **MUST** be in local time and explicitly labeled as such.
* The logger **MUST** not require non-POSIX features.

Rationale (non-normative): Local timestamps keep logs aligned with operator context and avoid silent UTC conversions. See my [Manifesto on Time](https://github.com/deadhedd/manifesto-on-time/blob/main/manifesto.txt) for background.

#### 3.2.6 Determinism & Safety

Logging functions **MUST** be safe to call repeatedly.

The logger **MUST NOT** mutate caller state unexpectedly (no silent `cd`, no `PATH` rewrites, no global traps).

The logger **MUST** operate under `set -eu` callers without causing spurious exits.

If the logger needs to handle failure internally (e.g., cannot open a log file), it **MUST** degrade gracefully to stderr and/or return a non-zero status for the caller to handle.

* Logger helpers should avoid mechanisms that mutate caller shell state (e.g., positional parameters) and should implement retention enumeration without side effects (see §2.2.4.X).

#### 3.2.7 Internal Debug (Opt-in Only)

If the logger supports internal debugging:

* It **MUST** be strictly opt-in via environment knobs (e.g., `LOG_INTERNAL_DEBUG=1`)
* Debug output **MUST** go to stderr or an explicit debug file
* Debug output **MUST NOT** pollute stdout

Debug mode must never change the semantics of normal log messages.

#### 3.2.8 Exit Code & Return Semantics

Logging functions **MUST** return 0 on success.

When a logging operation fails (e.g., file open failure), functions **MAY** return non-zero.

`log.sh` **MUST NOT** call `exit` except for the “executed directly” guard path.
When sourced, logger subsystem helpers **MUST NOT** call `exit`. The only permitted `exit` is the “executed directly” misuse guard (exit 2).

Generated notes and data artifacts are the priority.
The caller (for example, `job-wrap.sh`) must treat logging as best-effort and **MUST NOT** fail a job purely because logging failed, unless the failure meets the **hard** criteria defined in §2.2.8 (corrupted or unsafe execution context). **Soft** failures (file unavailable but `stderr` intact) **MUST** be allowed to proceed.

#### 3.2.X Dependency Resolution and Diagnostic Noise

Logger subsystem helpers may depend on functions provided by other sourced libraries (for example, `datetime.sh`). These dependencies are considered part of the engine’s internal wiring and are assumed to be present in correct-by-construction execution.

The engine does not require logger helpers to perform preflight dependency discovery (for example, via `command -v` or equivalent mechanisms) before invoking required functions.

Rules:

* Logger helpers **MUST** treat missing or unusable dependencies as operational failures and return exit code 10 as defined in Appendix C.6.
* Logger helpers **MAY** rely on direct invocation of required functions rather than attempting to probe for their existence.
* In dependency-missing scenarios, the shell may emit its own diagnostics to stderr (e.g., “not found”) prior to the helper emitting its own controlled error message.
* The presence of such shell-emitted diagnostics on stderr **MUST NOT** be considered a contract violation.
* Logger helpers **MUST NOT** emit dependency diagnostics to stdout.

Rationale (non-normative):
Experience has shown that portable, reliable preflight dependency checks are not consistently available or robust across supported environments, and can introduce complexity or false confidence without improving correctness. The engine therefore prefers explicit wiring and fail-fast behavior over defensive probing at internal seams.

#### 3.2.9 Global Scratch Variables (POSIX `sh` constraint)

Because POSIX `sh` does not provide function-local variables (`local`), logger components and helper libraries MAY use temporary scratch variables at global scope.

Rules:

* Scratch variables MUST be namespaced with a component-unique prefix (for example, `_lf_` for `log-format.sh`, `_ls_` for `log-sink.sh`, `_lc_` for `log-capture.sh`).
* Scratch variables are internal implementation details and are not part of the public API surface.
* Scratch variables MUST be treated as ephemeral and MUST NOT carry semantic meaning across calls.
* Helpers MUST NOT require callers to unset or reset scratch variables.
* Helpers MUST NOT clobber caller-provided output variables or contract-defined environment variables.
* Any façade-ownership guard variable (for example, `LOG_FACADE_ACTIVE`) is an internal implementation detail and is not part of the public environment contract surface.

Rationale (non-normative): Namespacing is the primary defense against collisions in POSIX `sh` and keeps helpers small while preserving the “do not mutate caller state unexpectedly” requirement.

#### 3.2.10 Non-Goals

`log.sh` **MUST NOT**:

* Manage job execution lifecycle
* Implement auto-commit behavior
* Attempt to be a general logging framework
* Own scheduling, invocation, or wrapper responsibilities beyond logging

It exists to provide stable primitives that the wrapper composes.

#### 3.2.11 Stability Promise

The logger’s public function names, message format, and stdout/stderr behavior are engine-stable.

Any breaking change to:

* function names or signatures
* log line format (timestamp/level prefixing)
* destination semantics (stderr vs file)
* library-only behavior
* logger helper return-code meanings (Appendix C.6)

**MUST** be accompanied by a contract revision.

### 3.3 Commit Helper Contract (commit.sh)

#### 3.3.1 Role & Responsibility

The commit helper is a single-purpose engine component responsible for:

* Staging an explicit set of files
* Creating a single Git commit in the configured repository
* Reporting the outcome via exit code only

The commit helper is not a general Git interface and not a standalone automation entrypoint.

Violations of this contract are considered bugs.

The helper is only engaged when job-wrap is operating in auto-commit mode; absence of Git or disabled commit mode does not imply an engine failure.

#### 3.3.2 Invocation Contract

The commit helper MUST be invoked by job-wrap.sh, either directly or via re-exec.

It MUST NOT be called directly from cron.

It MUST assume it is running inside an active job-wrap execution (`JOB_WRAP_ACTIVE=1`).

In hardened deployments, the commit helper executes git commands as a dedicated system account (default `git`), configurable via `GIT_USER`.

job-wrap.sh owns the decision of whether to invoke the helper at all; leaf scripts must be correct regardless of whether commit orchestration runs.

If invoked outside job-wrap, no guarantees are made about correctness or side effects unless the helper explicitly detects and rejects such invocation.

##### Privilege Boundary (doas)

Execution identity

* The commit helper **MUST NOT** perform Git operations as the invoking user.
* The commit helper **MUST** execute all Git commands as the dedicated Git account (`GIT_USER`, default `git`) via `doas -u ${GIT_USER}`.
* If the commit helper is invoked while already executing as `GIT_USER`, it **MUST** treat that as misuse and exit 10.

doas requirements

* `doas` **MUST** be available.
* The invoking user (expected `obsidian`) **MUST** be permitted by `doas.conf` to run the required Git commands as `GIT_USER`.
* If `doas` is missing or permission is denied, the helper **MUST** exit 10.

#### 3.3.3 Logging & Output Contract

Logging authority is centralized per §2.2 (Logging Contract) and §3.2 (Logger Contract).
The commit helper relies on wrapper-managed capture and **MUST NOT** source `log.sh` or implement its own logging system.

The commit helper **MUST NOT** write anything to stdout.

Any human-readable or diagnostic output **MAY** be written to stderr.

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

In hardened deployments, the commit helper executes git commands as a dedicated system account (default `git`), configurable via `GIT_USER`.

Rules:

* The commit helper MUST NOT implicitly stage files (e.g., no `git add -A`)
* The commit helper MUST NOT infer files from directory state
* The commit helper MUST NOT modify files it was not explicitly given

Bare Repository Selection

* The commit helper MUST support an explicit bare repository override via `COMMIT_BARE_REPO`.
* If `COMMIT_BARE_REPO` is set, it MUST be used as the authoritative bare repository path.
* If `COMMIT_BARE_REPO` is unset, the commit helper MUST use the engine default bare repository path (`/home/git/vaults/Main.git`).
* The engine default bare repository path MUST be documented and stable unless this contract is revised.

#### 3.3.6 Idempotency & Safety

Re-running the commit helper with the same inputs MUST NOT corrupt repository state.

If there are no changes to commit, the helper MUST exit cleanly with a documented non-failure code.

Partial commits, mixed commits, or stateful retries are forbidden.

The commit helper is assumed to run in a controlled, deterministic environment.

#### 3.3.7 Exit Code Semantics

Exit codes are part of the public engine contract.

The commit helper MUST use a stable set of exit outcomes with documented meanings. The authoritative mapping of exit codes to outcomes is defined in Appendix C — Engine Exit Codes.

job-wrap.sh MUST treat the commit helper’s “no-op / nothing to commit” outcome as non-failure.

Any exit outcome designated as failure in the appendix MUST be treated as an engine failure by job-wrap.sh, and job-wrap.sh MUST exit with an engine-reserved failure code as defined in the appendix.

Exit outcomes designated as non-failure in the appendix MUST NOT be interpreted as job failure by job-wrap.sh.

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

### 3.4 Status Report Contract (`report.sh` + helpers)

#### 3.4.1 Role & Responsibility

`report.sh` is the **coordinator and façade** for the reporting subsystem.

It orchestrates two child helpers:

* `script-status-report.sh`
  * Generates the Markdown status report and places it at the contracted path in the vault.
* `sync-latest-logs-to-vault.sh`
  * Refreshes presentation-only vault copies of job logs from the latest log pointers.

Together, the reporting helpers are an **observational engine component** responsible for:

* Scanning job output artifacts (primarily `*-latest.log` pointers and their target logs)
* Classifying engine and job health using documented heuristics
* Writing a **single, stable Markdown report** into the vault

The reporter **MUST NOT** introduce policy, defaults, or inferred expectations; it **MUST** derive state exclusively from engine artifacts and job-declared metadata.

It **MUST NOT** perform orchestration, scheduling, or remediation.

Violations of this contract are considered bugs.

---

#### 3.4.2 Invocation Contract

* `job-wrap.sh` **MUST** invoke the reporting subsystem via `report.sh`, either directly or via re-exec.
* Child helpers (`script-status-report.sh`, `sync-latest-logs-to-vault.sh`) **MUST** be reached through `report.sh`, not called directly from cron or leaf jobs.
* `report.sh` **MUST** assume it is running inside an active job-wrap execution (`JOB_WRAP_ACTIVE=1`).

If invoked outside job-wrap, behavior is undefined unless explicitly guarded.

---

#### 3.4.3 Logging & Output Contract

Logging authority is centralized per §2.2 (Logging Contract) and §3.2 (Logger Contract).
The status reporter relies on wrapper-managed capture and **MUST NOT** source `log.sh` or implement its own logging system.

The status reporter **MUST NOT** write report content to stdout.
Any human-readable operational output **MAY** be written to stderr.

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

The reporter’s notion of a job’s current state is derived from the latest observed execution and the job’s self-declared run cadence.

**Source of Execution State**

* For each job, the reporter locates the most recent execution by resolving that job’s `*-latest.log` pointer.
* The resolved log identifies the latest observed run, but pointer presence alone does not imply freshness or correctness.

The `*-latest.log` pointer is authoritative for identity, not for health: it identifies the most recent observed run, but it is never evidence of freshness, correctness, or health.

**Cadence Authority**

* Each job is the authoritative source of its own expected run cadence.
* The reporter **MUST** extract cadence declarations from the latest log and use them when evaluating freshness.
* The reporter interprets cadence declarations but **MUST NOT** invent, assume, or default cadence values.
* Freshness **MUST** be evaluated by comparing:
  * the timestamp of the latest run
  * against the job-declared cadence
  * relative to the current time

**Rules**

* The reporter **MUST** use the `*-latest.log` pointer solely to identify the most recent run.
* The reporter **MUST NOT** infer freshness from pointer presence alone.
* The reporter **MUST NOT** scan arbitrary historical logs unless explicitly configured to do so.
* A job **MAY** be flagged as stale if the elapsed time since its latest run exceeds what is permitted by its declared cadence.
* If cadence information is missing, unreadable, or unparseable, the reporter **MUST** classify the job as indeterminate according to the classification semantics.

All staleness thresholds and cadence interpretations **MUST** be explicit, deterministic, and derived from job-declared metadata rather than reporter-side assumptions.

---

#### 3.4.6 Classification Semantics

The reporter **MUST** classify each job into a small, fixed set of states.

The set of classification states, including their identifiers and meanings, is defined in Appendix B — Reporter Classification States.

Classification rules **MUST** be:

* Deterministic
* Fully documented
* Stable across releases unless the contract version is explicitly changed

The reporter **MUST** define explicit precedence rules for resolving conflicting classification signals.
Precedence rules **MUST** be deterministic and documented.

If required inputs for classification are missing, unreadable, or unparseable, the reporter **MUST** assign the designated indeterminate state defined in the appendix.

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

At minimum, the report **MUST** include:

* generation timestamp (local time)
* summary counts by state (OK/WARN/FAIL/UNKNOWN)
* per-job rows including:

  * job name
  * latest run timestamp (local time)
  * latest exit code (if known)
  * classification state
  * short reason / key signal (e.g., “stale 3d”, “exit=1”, “pattern: ERROR”)
  * link or path hint to the latest log artifact (format may vary)

Ordering:

* Per-job listing order **MUST** be deterministic (e.g., lexical by job name).

Rationale (non-normative): Local timestamps are easier for humans to interpret and line up with cron-triggered expectations. See my [Manifesto on Time](https://github.com/deadhedd/manifesto-on-time/blob/main/manifesto.txt) for background.

---

#### 3.4.9 Side Effects & Idempotency

The status reporter is observational.

* It **MUST** only write its own output report file, presentation-layer vault log copies (via the log copy helper), and temporary files (if any).
* It **MUST NOT** modify logs, pointers, repositories, or other notes.
* It **MUST** be safe to run repeatedly without accumulating junk artifacts.

Any temporary files **MUST** be cleaned up on success and failure.

---

#### 3.4.10 Vault Log Copies (Presentation Artifacts)

The status reporter **MAY** create vault-visible copies of job log artifacts for human inspection and linking from the status report.

These copies exist solely to support navigation, review, and debugging from within the vault and are **not** authoritative execution records.

**Role & Ownership**

* `report.sh` is the **sole** entry point for creating or updating vault log copies.
* It orchestrates the dedicated log copy helper (`sync-latest-logs-to-vault.sh`).
* No other engine component (including `job-wrap.sh`, `log.sh`, or leaf scripts) may write logs into the vault.

Vault log copies are considered **presentation artifacts**, not execution artifacts.

**Source of Truth**

* The authoritative log files remain under the engine log root (`LOG_ROOT`).
* Vault copies are derived from the resolved target of each job’s `*-latest.log` pointer.
* The vault copy **MUST NOT** be used as input to freshness evaluation, classification, or exit code determination.

All classification logic **MUST** continue to operate exclusively on engine logs.

**Copy Semantics**

When producing vault log copies, the status reporter:

* **MUST** copy or mirror only the latest resolved log per job.
* **MUST** overwrite existing vault copies deterministically.
* **MUST NOT** append or accumulate historical logs.
* **MUST** ensure that reruns are idempotent.

The vault copy **SHOULD** preserve the original filename or include enough context to clearly identify the job and run timestamp.

**Failure Behavior**

Failure to create or update vault log copies:

* **MUST** be logged and surfaced in the status report.
* **MUST NOT** invalidate the status report itself.
* **MUST NOT** retroactively alter job classification.

Vault log copy failures are considered presentation-layer degradation, not execution failure.

---

#### 3.4.11 Exit Code Semantics

Exit codes are part of the public engine contract.

The reporter **MUST** use a stable set of exit outcomes with documented meanings. The authoritative mapping of exit codes to outcomes is defined in **Appendix C — Engine Exit Codes**.

The reporter **MUST** return the designated failure outcome if one or more jobs are classified as failure according to the classification semantics.

The reporter **MUST NOT** return a failure outcome solely due to warning or stale classifications, unless explicitly defined by the contract.

If the reporter cannot complete its function due to missing inputs, unreadable state, or internal error, it **MUST** return an engine-reserved error outcome as defined in the appendix.

---

#### 3.4.12 Non-Goals

The status reporter **MUST NOT**:

* Trigger jobs
* Retry failures
* Auto-fix problems
* Modify job schedules
* Interpret business meaning of failures beyond documented heuristics

It is a *dashboard generator*, not an orchestrator.

---

#### 3.4.13 Stability Promise

The reporter’s **output structure and exit code meanings are engine-stable**.

Any breaking change to:

* report file path
* report section structure or table columns
* classification states or their meanings
* exit code meanings

**MUST** be accompanied by a contract revision.

---

## Appendix A — Core Engine Environment Variable Inventory (Informative)
This appendix defines the core engine environment variables and their required validation behavior.
> **Scope:** Core engine components only (`job-wrap.sh`, logging sink, commit helper).
>
> This appendix documents environment variables in use by the core engine at the time of writing.
> It does **not** grant permission to introduce new variables, nor does it define required behavior by itself.
> Normative rules governing environment variable usage are defined in Section 2.5.4.

### A.1 Summary

| Variable         | Component          | Role / Default                                       | Validation behavior                |
| ---------------- | ------------------ | ---------------------------------------------------- | ---------------------------------- |
| JOB_WRAP_ACTIVE  | Wrapper / Log sink | Wrapper recursion guard; expected `1` inside wrapper | Wrapper initialization fails if invalid; wrapper treats this as fatal |
| JOB_NAME         | Log sink           | Job identifier used for log naming                   | Sink initialization fails if missing/invalid (misuse → return `11`); escalation owned by wrapper |
| LOG_LIB_DIR      | Wrapper / Logger façade | Directory containing logger helper libs        | Required; missing/invalid is misuse (return `11`); escalation owned by wrapper/façade |
| LOG_SINK_LOADED  | Log sink           | Guard to prevent double sourcing                     | Checked early                      |
| VAULT_PATH       | Wrapper / Commit   | Default work tree for commits                        | Defaulted; not strictly validated |
| LOG_ROOT         | Wrapper / Log sink | Base log directory                                   | Defaulted; not strictly validated |
| TMPDIR           | Wrapper / Log sink | Temporary file parent                                | Default `/tmp`; not validated |
| COMMIT_BARE_REPO | Commit helper      | Optional bare repo override                          | Used directly; git validates |
| GIT_BIN          | Commit helper      | Optional git binary override                         | Executable verified |
| GIT_USER         | Commit helper      | Optional git user override                           | Non-empty; used for `doas -u` |
| PATH             | All                | Command search path                                  | Reset with safe defaults |

---

### A.2 Required Variables

The following variables are treated as required by the core engine and are validated when their owning component initializes:

#### JOB_WRAP_ACTIVE

* **Owner:** Wrapper / Log sink
* **Purpose:** Recursion guard to ensure exactly one wrapper instance per job
* **Expected value:** `1` when executing under `job-wrap.sh`
* **Failure behavior:** Wrapper initialization fails if value is missing or invalid; wrapper treats this as fatal

#### JOB_NAME

* **Owner:** Logging sink
* **Purpose:** Stable job identifier for log naming and latest pointers
* **Validity requirements (Normative):**
  * **MUST** be ASCII and **MUST NOT** contain whitespace or control characters.
  * **MUST NOT** contain `/` (path separator) or `.` / `..` path segments.
  * **MUST NOT** contain shell glob metacharacters or pattern syntax:
    `* ? [ ] { }`
  * **MUST** be safe for direct inclusion in filenames and glob patterns used by retention logic.
  * **Recommended allowed set:** `[A-Za-z0-9._-]`
    * (If the implementation chooses to be stricter, that is allowed. If it chooses to be looser, it must still satisfy the prohibitions above.)
  * **Length SHOULD** be kept reasonable (recommended ≤ 64 chars) to avoid path-length issues.
* **Failure behavior (when sourced):**
  * Missing/invalid `JOB_NAME` is **logger helper misuse**.
  * The sink **MUST** emit a single diagnostic line to stderr and **MUST return `11`**.
  * The sink **MUST NOT** call `exit` (except for the executed-directly guard).
  * `log.sh` / `job-wrap.sh` remain the sole escalation authority.

#### LOG_LIB_DIR

* **Owner:** Wrapper / Logger façade
* **Purpose:** Directory containing logger helper libs (`log-format.sh`, `log-sink.sh`, `log-capture.sh`)
* **Validity requirements (Normative):**
  * **MUST** be non-empty.
  * **MUST** refer to an existing directory.
  * **SHOULD** be an absolute, physical path (or must be normalizable to one).
* **Failure behavior (when sourced):**
  * Missing/invalid `LOG_LIB_DIR` is **logger helper misuse**.
  * The helper **MUST** emit a single diagnostic line to stderr and **MUST return `11`**.
  * Escalation remains owned by `log.sh` / `job-wrap.sh`.

---

### A.3 Recognized Optional Overrides

These variables are overrides for default behavior.
The core engine has been implemented to remain correct when they are unset.

#### VAULT_PATH

* **Owner:** Wrapper / Commit helper
* **Purpose:** Override vault work tree root
* **Default:** Repo-defined path (e.g. `/home/obsidian/vaults/Main`)
* **Validation:** Downstream existence checks only

#### LOG_ROOT

* **Owner:** Wrapper / Log sink
* **Purpose:** Base directory for job logs
* **Default:** Derived (often `${HOME}/logs`)
* **Validation:** Not strictly validated

#### TMPDIR

* **Owner:** Wrapper / Log sink
* **Purpose:** Temporary file location
* **Default:** `/tmp`
* **Validation:** Not validated beyond mktemp behavior

#### COMMIT_BARE_REPO

* **Owner:** Commit helper
* **Purpose:** Override bare git repository path
* **Default:** `/home/git/vaults/Main.git`
* **Validation:** Deferred to git

#### GIT_BIN

* **Owner:** Commit helper
* **Purpose:** Override git executable
* **Validation:** Must resolve to an executable file

#### GIT_USER

* **Owner:** Commit helper
* **Purpose:** Override system account used to invoke git commands
* **Default:** `git`
* **Validation:** Must be non-empty; used as `doas -u ${GIT_USER}`

---

### A.4 Internal Guards and Debug Knobs

The following variables are **internal implementation details**.
They are documented here for auditability only and are **not part of the public contract surface**:

* `LOG_SINK_LOADED` — prevents double initialization of logging sink
* Wrapper debug and tracing flags (`JOB_WRAP_DEBUG`, `JOB_WRAP_XTRACE`, etc.)
* Logging verbosity / formatting controls (`LOG_INTERNAL_LEVEL`, `LOG_ASCII_ONLY`, etc.)

External callers and leaf scripts are not intended to rely on these variables.

---

### A.5 Sink Outputs (Informative)

The following values are produced by the logger subsystem during initialization and are not expected to be set by callers.

#### LOG_FILE

* **Owner:** Logging sink
* **Purpose:** Path to the current run’s timestamped per-run log file
* **Set by:** `log-sink.sh` during sink initialization (or by `log.sh` as façade wiring)
* **Contract:**
  * MUST be set and non-empty after successful sink initialization.
  * MAY be unset if the façade degrades to stderr-only logging due to a soft logging failure.
* **Misuse rule (when sourced):**
  * If a helper that requires an initialized sink is invoked and `LOG_FILE` is missing/invalid, that helper MUST treat it as misuse and MUST return `11` with one diagnostic line to stderr.

---

### A.6 Explicitly Out of Scope

This appendix intentionally omits:

* Leaf script domain variables (e.g. sleep summaries, vault snapshots, celestial timing)
* Content-specific overrides
* Feature- or job-specific knobs

Such variables are governed by the contracts of their respective components, not the core engine.

---

## Appendix B — Classification States

### B.1 Classification States

The reporter uses the following classification states:

**OK**

The most recent job run completed successfully and no warning conditions were detected.

**WARN**

The most recent job run completed successfully, but one or more warning conditions were detected, or the job’s latest run is considered stale according to documented criteria.

**FAIL**

The most recent job run indicates failure, as determined by exit status or documented error-detection rules.

**UNKNOWN**

The job’s state cannot be determined due to missing required inputs, unreadable or missing logs or pointers, or unparseable data.

### B.2 Stability and Evolution

The set of classification states is finite and explicitly enumerated.

The identifiers and semantic meanings defined in this appendix MUST NOT change without a corresponding contract version change.

Additional states MAY be introduced only via a contract revision.

---

## Appendix C — Engine Exit Codes
> **Applies to:** Sections 3.3.7 and 3.4.11

This appendix defines the exit codes used by core engine components.

Exit code meanings defined here are part of the public engine contract and MUST remain stable unless the contract version is explicitly changed.

---

### C.1 General Rules

- Exit code 0 always indicates successful completion of the component’s primary responsibility.
- Non-zero exit codes indicate either a non-failure outcome explicitly defined as such, or a failure.
- `job-wrap.sh` is transparent with respect to leaf script exit codes unless it encounters an engine failure.
- Engine-reserved failure codes are used only when the engine itself cannot fulfill its contract.

---

### C.2 Commit Helper Exit Codes

| Exit Code | Meaning                                      |
| --------- | -------------------------------------------- |
| 0         | Commit created successfully                  |
| 3         | No changes to commit (non-failure outcome)   |
| 10        | Commit helper operational failure (e.g., git error, invalid input, repository unavailable) |

**Rules:**

- Exit code 3 MUST be treated as a successful, non-failure outcome by `job-wrap.sh`.
- Exit code 10 indicates a failure of the commit helper itself and MUST be treated as an engine failure by `job-wrap.sh`.

---

### C.3 Wrapper Exit Code Semantics (`job-wrap.sh`)

| Exit Code             | Meaning                                              |
| --------------------- | ---------------------------------------------------- |
| 0–255 (non-reserved)  | Exit code propagated directly from the leaf script   |
| 120                   | Wrapper invocation or usage error                    |
| 121                   | Wrapper initialization failure                       |
| 122                   | Logging sink initialization or operation failure     |
| 123                   | Commit helper failure                                |
| 124                   | Internal wrapper error or invariant violation        |

**Rules:**

- If the wrapper completes normally, it MUST exit with the leaf script’s exit code unchanged.
- If the wrapper cannot fulfill its responsibilities, it MUST exit with the appropriate engine-reserved failure code.
- Engine-reserved codes apply only when wrapper responsibilities fail; otherwise the wrapper exits exactly with the leaf code.
- Engine-reserved exit codes MUST NOT be used by leaf scripts.

---

### C.4 Reporter Exit Codes

| Exit Code | Meaning                                                                              |
| --------- | ------------------------------------------------------------------------------------ |
| 0         | Report generated successfully; no jobs classified as FAIL                            |
| 1         | Report generated successfully; one or more jobs classified as FAIL                   |
| 2         | Reporter usage or invocation error                                                   |
| 3         | Reporter operational failure (missing inputs, unreadable state, cannot write report, internal error) |

**Rules:**

- The reporter MUST return 1 if and only if at least one job is classified as FAIL.
- WARN or stale classifications MUST NOT cause a failure exit code unless explicitly defined by a future contract revision.
- Reporter operational failures MUST use exit code 3.

---

### C.5 Stability and Evolution

- Exit code meanings defined in this appendix are stable and normative.
- Numeric values MUST NOT be reassigned to different meanings without a contract version change.
- Additional exit codes MAY be introduced only via a contract revision.

---

### C.6 Logger Subsystem Helper Return Codes

Applies to logger child helpers orchestrated by `log.sh` (e.g., `log-format.sh`, `log-capture.sh`, `log-sink.sh`) when they are sourced. These are return codes consumed internally by `log.sh` / `job-wrap.sh`, not standalone job or engine exit codes.

| Code | Meaning |
| --- | --- |
| 0 | Success; output produced (line/stream formatted, sink op succeeded) |
| 4 | Suppressed / gated by policy (non-failure; caller should treat as “no output by design”) |
| 10 | Operational failure (invalid args, invalid level, unusable backend, invariant violation) |
| 11 | Logger helper misuse (missing façade context) |

Rules:

- `log.sh` MUST treat 4 as a non-failure outcome (similar to how the wrapper treats the commit helper’s 3 as non-failure).
- Logger helpers MUST NOT return 1 for any internal meaning to avoid collision with engine and reporter conventions.
- Logger helper misuse (missing façade context) MUST:
  - NOT perform sink mutation or other side effects
  - emit a single-line error to stderr
  - return 11 (not exit) when sourced
  - allow the caller (`log.sh` and/or `job-wrap.sh`) to decide whether to treat this as hard engine failure or soft degradation
- Direct execution of any logger helper remains misuse and MUST exit 2 (per §3.2.2).

---

## Appendix D — Logger Internal Context Variables (Informative)

These are internal engine wiring variables; they are not a stable public environment interface and must not be used by leaf scripts.

| Variable         | Owner              | Consumers                         | Purpose                                       | Validation / failure |
| ---------------- | ------------------ | --------------------------------- | --------------------------------------------- | -------------------- |
| LOG_FACADE_ACTIVE | log.sh             | log-format / log-sink / log-capture | Proves façade ownership active                | Missing → helper misuse → return `11` |
| LOG_LIB_DIR      | job-wrap.sh        | log.sh                             | Directory containing logger helper libs       | Missing/invalid → misuse → return `11` |
| LOG_SINK_FD      | log.sh / sink init | log-capture                        | FD to write formatted lines to                | Missing/invalid → misuse → return `11` |
| LOG_MIN_LEVEL    | log.sh             | log-format / log-capture           | Minimum log level gate                        | Missing/invalid → misuse → return `11` |
