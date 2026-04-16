# nre — Note Runtime Engine

A small runtime for automated note generation using cron and POSIX shell scripts.

**Run automated note-generation jobs with deterministic logs, clean output, and built-in health reporting.**

nre is a small POSIX shell runtime for cron-driven Markdown workflows.

It standardizes how jobs run, how they log, how results are committed, and how job health is reported — all without requiring plugins, background services, or proprietary tooling.

Originally built for Obsidian vault automation, but usable for any Markdown-based workflow.

---

# What nre Gives You

Many note automation workflows rely on editor plugins, templates, or small scripts. nre provides the infrastructure needed to run note-generation jobs reliably outside the editor using cron and POSIX shell scripts.

### Deterministic job logging

Every run produces a structured log file and updates a `<job>-latest.log` pointer.

You always know:

* when the job ran
* what it did
* whether it succeeded

---

### Clean stdout (no log pollution)

Leaf scripts follow a simple rule:

```
stdout = data
stderr = diagnostics
```

This allows scripts to safely participate in pipelines or redirection without log messages contaminating the output.

---

### A single execution wrapper

Every job runs through the same wrapper:

```
cron
  ↓
engine/wrap.sh
  ↓
job script
```

The wrapper takes care of:

* environment normalization
* structured logging
* stderr capture
* exit code propagation
* optional commit orchestration

This lets job scripts stay small and focused.

---

### Automatic Markdown status dashboard

nre includes a reporting job that reads logs and generates a Markdown dashboard.

The report shows:

* last run time
* success or failure
* warning counts
* freshness relative to declared cadence

The dashboard can be embedded directly inside your notes.

The report can be generated periodically via cron, or invoked at the end of jobs for more-or-less real-time updates.

---

### Optional Git auto-commit

Jobs can declare which artifacts should be committed.

After a job finishes, the wrapper runs the commit helper automatically.

This means you get:

* consistent commits
* no Git logic inside job scripts
* explicit artifact staging

---

### Included leaf job template

nre includes a ready-to-use template for creating new jobs that already follows the runtime contract.

---

# Quick Start (60 seconds)

Create a new job from the template:

```sh
cp jobs/leaf-template.sh jobs/my-job.sh
chmod +x jobs/my-job.sh
```

Add it to cron:

```sh
0 5 * * * /bin/sh /path/to/repo/jobs/my-job.sh
```

That’s it.

The runtime will automatically:

* create structured logs
* update `<job>-latest.log`
* optionally commit artifacts
* include the job in the status dashboard

---

# Writing New Jobs

nre includes a template for creating new jobs:

```
jobs/leaf-template.sh
```

The template demonstrates the standard job structure, including:

* wrapper re-execution
* structured diagnostic logging
* cadence declaration
* correct stdout/stderr discipline
* artifact declaration for commits

To create a new job:

```sh
cp jobs/leaf-template.sh jobs/my-new-job.sh
```

Then implement your job logic inside the template.

The wrapper handles logging, environment setup, and commit orchestration automatically.

---

# Example

Minimal job:

```sh
#!/bin/sh
set -eu

# re-exec via wrapper
if [ "${JOB_WRAP_ACTIVE:-0}" != "1" ]; then
  exec /path/to/engine/wrap.sh "$0" "$@"
fi

printf '%s\n' "INFO: cadence=daily" >&2

printf '# Daily Note\n'
```

Cron:

```
0 5 * * * /bin/sh jobs/generate-daily-note.sh
```

Result:

* structured log written
* `<job>-latest.log` updated

If the job registers artifacts for commit, the wrapper can also run the commit helper automatically (depending on `COMMIT_MODE`).

---

# Core Concepts

### Jobs

A **job** is a shell script that generates or updates notes.

Jobs:

* emit diagnostics to stderr
* optionally emit data to stdout
* declare cadence for freshness evaluation

---

### Wrapper

`engine/wrap.sh` is responsible for executing jobs and managing runtime behavior.

It:

* initializes logging
* captures job stderr
* preserves stdout
* runs commit orchestration
* writes structured run metadata

---

### Logs

Each run produces:

```
logs/<bucket>/<job>-<timestamp>.log
```

and updates:

```
<job>-latest.log
```

Logs use plain ASCII and include timestamps for every entry.

---

### Reporting

`script-status-report.sh` scans the latest logs and produces a Markdown report.

You can keep the dashboard up to date in two ways:

• schedule `jobs/script-status-report.sh` in cron
• run it at the end of other jobs for near real-time updates

Example invocation:

```sh
/bin/sh "$repo_root/jobs/script-status-report.sh"
```

Jobs are classified as:

* OK
* WARN
* FAIL
* UNKNOWN

Freshness is evaluated from observed runs rather than cron configuration.

---

# Project Layout

```
engine/
  wrap.sh
  log.sh
  log-capture.sh
  log-format.sh
  log-sink.sh
  lib/
    commit.sh
    datetime.sh
    periods.sh

jobs/
  leaf-template.sh
  script-status-report.sh
  generate-test-note.sh

  helpers/
    sync-latest-logs-to-vault.sh
```

Most users will start by copying `jobs/leaf-template.sh` and scheduling the resulting job with cron.

---

# Design Goals

nre prioritizes:

* deterministic execution
* observable automation
* POSIX portability
* minimal dependencies
* clear separation between data and diagnostics

The runtime intentionally avoids plugins, background daemons, and hidden state in order to keep behavior predictable.

---

# Documentation

For the full behavioral specification of the runtime, see:

```
docs/CONTRACT.md
```

---

# Platform

Designed for Unix environments with:

* POSIX `sh`
* cron
* standard core utilities
