#!/bin/sh
# Generate a quarterly note markdown file based on the legacy Node implementation.
# Supports configuring the vault, output directory, target quarter, and overwrite behavior.

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
Usage: generate-quarterly-note.sh [--vault <path>] [--outdir <name>] [--date YYYY-QN] [--force] [--dry-run]

Options:
  --vault <path>    Vault root where the note should be created. Defaults to $VAULT_PATH or /home/obsidian/vaults/Main.
  --outdir <name>   Subdirectory inside the vault. Defaults to "Periodic Notes/Quarterly Notes".
  --date YYYY-QN    Quarter to generate (e.g., 2025-Q3). Defaults to the current UTC quarter.
  --force           Overwrite the note if it already exists.
  --dry-run         Output the note contents to stdout without writing files.
  --help            Show this message.
EOF_USAGE
}

vault_path=${VAULT_PATH:-/home/obsidian/vaults/Main}
outdir="Periodic Notes/Quarterly Notes"
date_arg=""
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
    --date)
      if [ $# -lt 2 ]; then
        log_err "Missing value for --date"
        usage
        exit 2
      fi
      date_arg=$2
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

if [ -n "$date_arg" ]; then
  case "$date_arg" in
    [0-9][0-9][0-9][0-9]-Q[1-4])
      target_year=${date_arg%%-*}
      target_quarter=${date_arg#*-Q}
      target_quarter=${target_quarter#0}
      if [ -z "$target_quarter" ]; then
        target_quarter=0
      fi
      ;;
    *)
      log_err "--date must use the format YYYY-QN (e.g., 2025-Q3)"
      exit 2
      ;;
  esac
else
  if ! utc_today=$(get_today_utc); then
    log_err "Failed to determine current UTC date"
    exit 1
  fi

  if ! quarter_info=$(quarter_tag_for_utc_date "$utc_today"); then
    log_err "Failed to determine current quarter"
    exit 1
  fi

  target_quarter=${quarter_info#Q}
  target_quarter=${target_quarter%%-*}
  target_year=${quarter_info##*-}
fi

tag="${target_year}-Q${target_quarter}"

if [ "$target_quarter" -lt 1 ] || [ "$target_quarter" -gt 4 ]; then
  log_err "Quarter must be between 1 and 4"
  exit 2
fi

start_month=$(( (target_quarter - 1) * 3 + 1 ))

if ! set -- $(add_months "$target_year" "$start_month" -3); then
  log_err "Failed to compute previous quarter"
  exit 1
fi
prev_year=$1
prev_month=$2
prev_month=$((prev_month + 0))
prev_quarter=$(( (prev_month + 2) / 3 ))

if ! set -- $(add_months "$target_year" "$start_month" 3); then
  log_err "Failed to compute next quarter"
  exit 1
fi
next_year=$1
next_month=$2
next_month=$((next_month + 0))
next_quarter=$(( (next_month + 2) / 3 ))

prev_link="Q${prev_quarter} ${prev_year}"
next_link="Q${next_quarter} ${next_year}"

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

note_path="${note_dir%/}/${tag}.md"
dry_run_primary_path=$note_path
dry_run_output_path="${repo_root%/}/Quarterly Note Sample.md"

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
# ${tag}

- [[Periodic Notes/Quarterly Notes/${prev_year}-Q${prev_quarter}|${prev_link}]]
- [[Periodic Notes/Quarterly Notes/${next_year}-Q${next_quarter}|${next_link}]]

## Cascading Tasks

\`\`\`tasks
not done
tag includes due/${tag}
\`\`\`

## Quarterly Checklist

-  Review yearly goals
-  Set quarterly priorities
-  Review financial plan
-  Plan major home or work projects
-  Schedule any needed health checkups
-  Clean out unnecessary files or papers

## Major Goals

## Key Projects

## Review

- What went well:

- What didn’t:

- Lessons learned:

## Notes
EOF_NOTE

if [ "$dry_run" -eq 1 ]; then
  log_info "Dry run: quarterly note sample written to $dry_run_output_path"
fi

