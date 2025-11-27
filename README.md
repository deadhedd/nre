# Obsidian Note Tools

This repository contains shell scripts that help automate common tasks in an
[Obsidian](https://obsidian.md/) vault. All periodic note generators live in the
`generators/` directory to keep the repository root tidy.

## Cron wrapper (`utils/core/job-wrap.sh`)

`utils/core/job-wrap.sh` records structured logs for cron jobs and now resolves script
names automatically. Provide the job label followed by the script or command
name; the wrapper searches the repository root and `utils/` directory before
falling back to the system `PATH`.

```sh
/bin/sh utils/core/job-wrap.sh daily-note generate-daily-note.sh --dry-run
```

Set `JOB_WRAP_SEARCH_PATH` to a colon-delimited list to customize the search
order when running from other directories.

## Logging pipeline

### When run through `utils/core/job-wrap.sh`

* Resolves the requested command name by checking `JOB_WRAP_SEARCH_PATH`, then searching the repository for executables, and finally falling back to `PATH`; unknown commands abort with exit 127.
* Sanitizes the job label to derive the log folder (daily/weekly/periodic), creates the folder under `${HOME:-/home/obsidian}/logs`, and names each run log `<job>-<UTC timestamp>.log` alongside a `latest` symlink.
* Writes a header with start time, cwd, user, path, requested/resolved command, and argv, then appends all stdout/stderr from the invoked script, and finally records exit code, end time, and duration.
* Rotates logs by keeping the newest `LOG_KEEP` (default 20) per job name, deleting older files after each run.

### When a generator runs directly

* Scripts such as `generators/generate-daily-note.sh` print status messages with `log_info`/`log_warn`/`log_err`, sending informational output to stdout and errors to stderr.
* The daily note script pins `PATH` to `/usr/local/bin:/usr/bin:/bin:${PATH:-}` before doing any work and logs high-level milestones like vault path selection or missing folder warnings.
* Without the wrapper, these logs remain on the calling terminal; when invoked through `job-wrap.sh`, the same messages are captured in the run log alongside the wrapper's header/footer metadata.

### Shared logging helper (`utils/core/log.sh`)

Source `utils/core/log.sh` to standardize log output across scripts:

```sh
. "$(cd -- "$(dirname -- "$0")" && pwd -P)/../core/log.sh"
log_info "Starting"      # -> "2025-02-14T00:00:00Z INFO Starting"
log_warn "Missing file"  # stderr
LOG_DEBUG=1 log_debug "Verbose details"
```

Defaults favor ASCII-only lines for cron safety and append to a log file when
`LOG_FILE` is set (parents are created automatically). Environment toggles:

* `LOG_FILE` — Path to append every log line (unset = no file output).
* `LOG_TIMESTAMP` — `1` (default) to include UTC timestamps, `0` to omit.
* `LOG_DEBUG` — `1` enables `log_debug` output; `0` suppresses it.
* `LOG_ASCII_ONLY` — `1` (default) strips non-ASCII characters; set to `0` to allow them.

## `generators/generate-daily-note.sh`

`generators/generate-daily-note.sh` creates a Markdown file for today's date in your vault.
The script is provided as a template—edit the vault paths and note sections to
match your own workflow.

### Usage

```sh
export VAULT_PATH=/path/to/your/obsidian/vault
./generators/generate-daily-note.sh
```

By default the note is placed inside `/Periodic Notes/Daily Notes/` within the
specified vault. Optional helper scripts in the `utils/` directory will be used
if present to populate sections such as a day plan. The weekly goal is pulled
in via an Obsidian embed of the current weekly note rather than a helper
script; generated notes include an embed similar to:

```
![[Periodic Notes/Weekly Notes/2025-W06#🎯 Weekly Goal]]
```


## `generators/generate-monthly-note.sh`

`generators/generate-monthly-note.sh` mirrors the original Node-based generator but in POSIX shell.
It accepts the same core options (`--vault`, `--outdir`, `--date`, and `--locale`) while
respecting the `VAULT_PATH` environment variable when present.

### Usage

```sh
./generators/generate-monthly-note.sh --vault "$VAULT_PATH" --date 2024-09
```

Passing `--force` allows overwriting an existing note. The script creates missing
folders as needed and falls back to the `C` locale if the requested locale is
unavailable.

## `generators/generate-quarterly-note.sh`

`generators/generate-quarterly-note.sh` produces quarterly notes in the same format that the
legacy script emitted. It defaults to the current quarter in UTC and accepts
`--vault`, `--outdir`, `--date`, and `--force` flags.

### Usage

```sh
./generators/generate-quarterly-note.sh --outdir "Periodic Notes/Quarterly Notes" --date 2024-Q4
```

## `generators/generate-yearly-note.sh`

`generators/generate-yearly-note.sh` writes yearly notes with cascading task blocks and
checklists. Provide `--year` to generate a specific year or rely on the default of
`date -u +%Y`.

### Usage

```sh
./generators/generate-yearly-note.sh --vault "$VAULT_PATH" --year 2025
```

Monthly, quarterly, and yearly notes default to `/Periodic Notes/Monthly Notes/`,
`/Periodic Notes/Quarterly Notes/`, and `/Periodic Notes/Yearly Notes/`
respectively. All three periodic note scripts overwrite existing files only when
`--force` is supplied, matching the behavior of their legacy Node counterparts.
