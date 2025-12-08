#!/bin/sh
# Generate a yearly note markdown file inspired by the legacy Node version.
# Provides CLI options to control the vault, output directory, target year, and overwrite behavior.

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd -P)
utils_dir="$repo_root/utils"
date_helper="$utils_dir/core/date-period-helpers.sh"
job_wrap="$utils_dir/core/job-wrap.sh"
script_path="$script_dir/$(basename "$0")"

log_info() { printf 'INFO %s\n' "$*"; }
log_warn() { printf 'WARN %s\n' "$*" >&2; }
log_err() { printf 'ERR %s\n' "$*" >&2; }

if [ "${JOB_WRAP_ACTIVE:-0}" != "1" ] && [ -x "$job_wrap" ]; then
  JOB_WRAP_ACTIVE=1 exec /bin/sh "$job_wrap" "$script_path" "$@"
fi

. "$date_helper"

usage() {
  cat <<'EOF_USAGE'
Usage: generate-yearly-note.sh [--vault <path>] [--outdir <name>] [--year YYYY] [--force] [--dry-run]

Options:
  --vault <path>    Vault root where the note should be created. Defaults to $VAULT_PATH or /home/obsidian/vaults/Main.
  --outdir <name>   Subdirectory inside the vault. Defaults to "Periodic Notes/Yearly Notes".
  --year YYYY       Year to generate. Defaults to the current UTC year.
  --force           Overwrite the note if it already exists.
  --dry-run         Output the note contents to stdout without writing files.
  --help            Show this message.
EOF_USAGE
}

vault_path=${VAULT_PATH:-/home/obsidian/vaults/Main}
outdir="Periodic Notes/Yearly Notes"
year_arg=""
force=0
dry_run=0

write_output() {
  dest=$1
  if [ "$dry_run" -eq 1 ]; then
    if [ -n "${dry_run_primary_path:-}" ] && [ -n "${dry_run_output_path:-}" ] && [ "$dest" = "$dry_run_primary_path" ]; then
      log_info "DRY RUN start: $dest -> $dry_run_output_path"
      cat | tee "$dry_run_output_path"
    else
      log_info "DRY RUN start: $dest"
      cat
    fi
    log_info "DRY RUN end: $dest"
  else
    cat >"$dest"
  fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    --vault)
      if [ $# -lt 2 ]; then
        log_err "Missing value for --vault"
        usage
        exit 2
      fi
      vault_path=$2
      shift 2
      ;;
    --outdir)
      if [ $# -lt 2 ]; then
        log_err "Missing value for --outdir"
        usage
        exit 2
      fi
      outdir=$2
      shift 2
      ;;
    --year)
      if [ $# -lt 2 ]; then
        log_err "Missing value for --year"
        usage
        exit 2
      fi
      year_arg=$2
      shift 2
      ;;
    --force)
      force=1
      shift
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      log_err "Unknown option: $1"
      usage
      exit 2
      ;;
  esac
done

if [ -n "$year_arg" ]; then
  case "$year_arg" in
    [0-9][0-9][0-9][0-9])
      target_year=$year_arg
      ;;
    *)
      log_err "--year must use the format YYYY (e.g., 2025)"
      exit 2
      ;;
  esac
else
  if ! utc_today=$(get_today_utc); then
    log_err "Failed to determine current UTC date"
    exit 1
  fi

  if ! target_year=$(year_for_utc_date "$utc_today"); then
    log_err "Failed to determine current year"
    exit 1
  fi
fi

prev_year=$((target_year - 1))
next_year=$((target_year + 1))

vault_root="${vault_path%/}"

trimmed_outdir=$outdir
while [ "${trimmed_outdir#/}" != "$trimmed_outdir" ]; do
  trimmed_outdir=${trimmed_outdir#/}
done
while [ "${trimmed_outdir%/}" != "$trimmed_outdir" ]; do
  trimmed_outdir=${trimmed_outdir%/}
done

if [ -n "$trimmed_outdir" ]; then
  note_dir="$vault_root/$trimmed_outdir"
else
  note_dir="$vault_root"
fi

note_path="${note_dir%/}/${target_year}.md"
dry_run_primary_path=$note_path
dry_run_output_path="${repo_root%/}/Yearly Note Sample.md"

if [ "$dry_run" -eq 1 ]; then
  log_info "Dry run: would ensure directory exists: $note_dir"
else
  mkdir -p "$note_dir"
fi

if [ -f "$note_path" ] && [ "$force" -ne 1 ]; then
  log_err "Refusing to overwrite existing file: $note_path"
  log_err "Re-run with --force to overwrite."
  exit 1
fi

write_output "$note_path" <<EOF_NOTE
# ${target_year}

- [[Periodic Notes/Yearly Notes/${prev_year}|${prev_year}]]
- [[Periodic Notes/Yearly Notes/${next_year}|${next_year}]]

## Cascading Tasks

\`\`\`dataview
task
from ""
where contains(tags, "due/${target_year}")
\`\`\`

## Yearly Checklist

-  Reflect on the past year
-  Set yearly theme or focus
-  Define major life goals
-  Create financial plan
-  Plan vacations / time off
-  Assess personal habits and routines
-  Declutter home, digital spaces, and commitments

## Annual Theme / Focus

## Major Goals

## Review

- Highlights of the year:

- Challenges faced:

- Lessons learned:

- Changes for next year:

## Notes
EOF_NOTE

if [ "$dry_run" -eq 1 ]; then
  log_info "Dry run: yearly note sample written to $dry_run_output_path"
fi

