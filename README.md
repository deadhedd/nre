# 🧠 nre — Note Runtime Engine

A contract-driven automation engine for managing and generating structured knowledge inside an Obsidian vault.

This project is a **POSIX shell–based execution framework** designed to make automation:

* deterministic
* observable
* composable
* and resilient to common failure modes

---

## 🚀 What This Is

A **wrapper-managed job execution framework** that provides:

* deterministic, reproducible execution for the documented shell runtime
* strict separation of data and diagnostics (stdout vs stderr)
* centralized, structured logging
* explicit artifact tracking and commit orchestration
* cadence-aware job monitoring and staleness detection

Conceptually, this is a **lightweight CI-style execution system for shell-based automation**.

---

## 🔑 Key Capabilities

### ⚙️ Execution Engine

* Wrapper-managed jobs execute through a central wrapper (`engine/wrap.sh`)
* The wrapper manages:

  * wrapper context and deployment configuration
  * execution lifecycle and error handling
  * logging integration
  * artifact commit behavior

This reduces reliance on implicit shell state and reduces non-deterministic failures.

---

### 📜 Output Discipline (Hard Guarantees)

* `stdout` is reserved for **primary data output only**
* `stderr` is reserved for **diagnostics and logs**

This guarantees:

* safe composition in pipelines
* machine-readable outputs without filtering
* predictable behavior across automation layers

---

### 🪵 Centralized Logging & Observability

* Single logging authority (`engine/log.sh`)
* Per-run logs with timestamped entries and level-based filtering (DEBUG / INFO / WARN / ERROR)
* Stable pointer to latest execution (`*-latest.log`)
* Bootstrap logging for degraded or early-failure scenarios

Designed for:

* reliable postmortem debugging
* consistent log structure across all jobs
* observability independent of job success

---

### 📦 Artifact Tracking & Commit Orchestration

* Jobs explicitly declare outputs via `COMMIT_LIST_FILE`
* Wrapper handles commit behavior:

  * required commit mode
  * best-effort commit mode
  * disabled mode

This enforces:

* deterministic outputs
* traceable side effects
* separation between job logic and persistence

---

### ⏱️ Cadence & Freshness Monitoring

* Each job declares its expected run frequency
* Status reporting evaluates:

  * freshness (has it run recently enough?)
  * staleness
  * missing executions

This enables **health monitoring without centralized scheduling logic**.

---

## 🔒 Core Design Guarantees

This system enforces strict execution contracts to eliminate common failure modes in shell automation.

### Strict stdout/stderr separation

* Prevents data corruption in pipelines
* Ensures outputs remain machine-consumable

### Wrapper-managed execution lifecycle

* Wrapper-managed jobs run in a controlled environment
* Enforces consistent behavior across wrapper-managed scripts

### Centralized logging ownership

* Logging is handled exclusively by the logging subsystem
* Jobs never manage log files directly

### Deterministic execution model

* No reliance on interactive shell configuration
* Predictable behavior under cron and automation

### Explicit artifact declaration

* All outputs must be declared
* Prevents hidden side effects and implicit state

Full specification (engine contracts, execution model, logging guarantees):
[https://github.com/deadhedd/nre/blob/master/docs/CONTRACT.md](https://github.com/deadhedd/nre/blob/master/docs/CONTRACT.md)

---

## 🧩 Example Jobs

Representative jobs running under this framework:

* Weather-based yardwork suitability analysis
  → [https://github.com/deadhedd/nre/blob/master/jobs/check-yardwork-suitability.sh](https://github.com/deadhedd/nre/blob/master/jobs/check-yardwork-suitability.sh)

* Sleep data processing and summarization
  → [https://github.com/deadhedd/nre/blob/master/jobs/sleep-summary.sh](https://github.com/deadhedd/nre/blob/master/jobs/sleep-summary.sh)

* Periodic note archiving and retention enforcement
  → [https://github.com/deadhedd/nre/blob/master/jobs/archive-periodic-notes.sh](https://github.com/deadhedd/nre/blob/master/jobs/archive-periodic-notes.sh)

* Self-updating automation system via Git
  → [https://github.com/deadhedd/nre/blob/master/jobs/pull-nre.sh](https://github.com/deadhedd/nre/blob/master/jobs/pull-nre.sh)

* Snapshotting dynamic Obsidian embeds into static content
  → [https://github.com/deadhedd/nre/blob/master/jobs/daily-note-snapshot.sh](https://github.com/deadhedd/nre/blob/master/jobs/daily-note-snapshot.sh)

Each job:

* runs under wrapper control
* produces deterministic outputs
* integrates with centralized logging and reporting

---

## 🧪 Testing & Reliability

The system includes regression tests for core execution guarantees:

* wrapper boundary enforcement
* stdout/stderr contract compliance
* degraded-mode behavior
* commit orchestration

Example test suite:
[https://github.com/deadhedd/nre/tree/master/engine/tests](https://github.com/deadhedd/nre/tree/master/engine/tests)

---

## 🧱 System Architecture

```
Leaf Script (job)
        ↓
engine/wrap.sh (execution + enforcement)
        ↓
engine/log.sh (centralized logging)
        ↓
engine/lib/commit.sh (artifact tracking)
        ↓
jobs/script-status-report.sh (system health + status)
```

Design goals:

* predictable behavior under failure
* strong observability guarantees
* minimal operational complexity

---

## 📁 Environment Model

Configuration is centralized via environment variables. Start with the public example:

[https://github.com/deadhedd/nre/blob/master/env.example.sh](https://github.com/deadhedd/nre/blob/master/env.example.sh)

Key properties:

* configuration for scheduled execution through the wrapper
* no required interactive shell configuration
* configurable vault and log paths

The core engine targets POSIX `/bin/sh`. Ubuntu CI exercises its shell syntax,
ShellCheck policy, regression suites, and public release checks. The private
deployment is currently OpenBSD-oriented and is documented in
the private deployment documentation. Ubuntu CI does not prove the complete
OpenBSD deployment environment, and this project does not claim end-to-end Linux
runtime support.

When commit mode is enabled, the current commit helper uses `doas` to run Git
as the configured Git user. The required privilege rules and isolated index
permissions are deployment requirements, not wrapper portability guarantees.

---

## 📄 Additional Documentation

* Environment variable inventory
  [https://github.com/deadhedd/nre/blob/master/docs/environment-variable-inventory.md](https://github.com/deadhedd/nre/blob/master/docs/environment-variable-inventory.md)

* Date and period logic reference
  [https://github.com/deadhedd/nre/blob/master/docs/date-logic-inventory.md](https://github.com/deadhedd/nre/blob/master/docs/date-logic-inventory.md)

---

## 🧠 Why This Exists

Shell-based automation frequently fails due to:

* mixed output streams (data + logs)
* inconsistent or missing logging
* reliance on implicit environment state
* silent or ambiguous failures

This system addresses those issues through:

* strict execution contracts
* centralized control via a wrapper
* observability-first design

---

## 📖 Deep Dive

For detailed design rationale and system philosophy:

👉 [https://deadhedd.com/](https://deadhedd.com/)

Covers:

* architectural decisions
* tradeoffs and constraints
* contract-driven design approach
* real-world lessons from building the system

---

## 📚 Full Contracts & Specification

Authoritative system contracts:

[https://github.com/deadhedd/nre/blob/master/docs/CONTRACT.md](https://github.com/deadhedd/nre/blob/master/docs/CONTRACT.md)

---

## 🛠️ Tech Stack

* POSIX shell (`/bin/sh`)
* Git (artifact tracking and persistence)
* Cron (scheduling)
* jq (data processing)
* Obsidian (knowledge layer)

For general public deployment requirements, see:

```
docs/deployment-public.md
```

---

## 🎯 What This Demonstrates

This project demonstrates:

* systems design and architecture
* CI/CD-style execution modeling
* logging and observability patterns
* contract-driven development
* POSIX shell automation with an OpenBSD-oriented private deployment
* reliability-focused scripting

---

## ⚠️ Status

Actively developed.

Core contracts are stabilizing and treated as authoritative.

---

## 👤 Author

deadhedd
