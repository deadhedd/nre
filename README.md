# Obsidian Note Tools

This repository contains shell scripts that help automate common tasks in an
[Obsidian](https://obsidian.md/) vault. All periodic note generators live in the
`generators/` directory to keep the repository root tidy.

## Cron wrapper (`utils/job-wrap.sh`)

`utils/job-wrap.sh` records structured logs for cron jobs and now resolves script
names automatically. Provide the job label followed by the script or command
name; the wrapper searches the repository root and `utils/` directory before
falling back to the system `PATH`.

```sh
/bin/sh utils/job-wrap.sh daily-note generate-daily-note.sh --dry-run
```

Set `JOB_WRAP_SEARCH_PATH` to a colon-delimited list to customize the search
order when running from other directories.

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
if present to populate sections such as a day plan or weekly goal.


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
