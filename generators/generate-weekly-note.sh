#!/bin/sh
# generate-weekly-note.sh — Generate a weekly note equivalent to the legacy Node script.
# Author: deadhedd
# License: MIT
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd -P)
utils_dir="$repo_root/utils"
date_helper="$utils_dir/core/date-period-helpers.sh"
job_wrap="$repo_root/utils/core/job-wrap.sh"
script_path="$script_dir/$(basename "$0")"


if [ "${JOB_WRAP_ACTIVE:-0}" != "1" ] && [ -x "$job_wrap" ]; then
  JOB_WRAP_ACTIVE=1 exec /bin/sh "$job_wrap" "$script_path" "$@"
fi

. "$date_helper"

usage() {
  cat <<'EOF_USAGE'
Usage: generate-weekly-note.sh [--vault <path>] [--outdir <name>] [--date YYYY-MM-DD] [--force] [--dry-run]

Options:
  --vault <path>    Vault root where the note should be created. Defaults to $VAULT_PATH or /home/obsidian/vaults/Main.
  --outdir <name>   Subdirectory inside the vault. Defaults to "Periodic Notes/Weekly Notes".
  --date YYYY-MM-DD Target date used to determine the week tag. Defaults to the current UTC date.
  --force           Overwrite the note if it already exists.
  --dry-run         Write note content to "Weekly Note Sample.md" in the repo root without touching the vault.
  --help            Show this message.
EOF_USAGE
}

vault_path=${VAULT_PATH:-/home/obsidian/vaults/Main}
outdir="Periodic Notes/Weekly Notes"
date_arg=""
force=0
dry_run=0

write_output() {
  dest=$1
  output_target=$dest

  if [ "$dry_run" -eq 1 ] && [ -n "${dry_run_primary_path:-}" ] && [ -n "${dry_run_output_path:-}" ] && [ "$dest" = "$dry_run_primary_path" ]; then
    output_target=$dry_run_output_path
    printf 'INFO %s\n' "Dry run: redirecting output to sample file: $output_target"
    cat >"$output_target"
    return
  fi

  if [ "$dry_run" -eq 1 ]; then
    printf 'INFO %s\n' "DRY RUN start: $dest"
    cat
    printf 'INFO %s\n' "DRY RUN end: $dest"
  else
    cat >"$dest"
  fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    --vault)
      if [ $# -lt 2 ]; then
        printf 'ERR  %s\n' "Missing value for --vault" >&2
        usage
        exit 2
      fi
      vault_path=$2
      shift 2
      ;;
    --outdir)
      if [ $# -lt 2 ]; then
        printf 'ERR  %s\n' "Missing value for --outdir" >&2
        usage
        exit 2
      fi
      outdir=$2
      shift 2
      ;;
    --date)
      if [ $# -lt 2 ]; then
        printf 'ERR  %s\n' "Missing value for --date" >&2
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
      printf 'ERR  %s\n' "Unknown option: $1" >&2
      usage
      exit 2
      ;;
  esac
done

printf 'INFO %s\n' "Starting weekly note generation"

if [ -z "$date_arg" ]; then
  date_arg=$(get_today_utc)
fi

if ! is_utc_date_format "$date_arg"; then
  printf 'ERR  %s\n' "--date must be in YYYY-MM-DD format" >&2
  exit 2
fi

if ! week_nav=$(week_nav_tags_for_utc_date "$date_arg" 2>/dev/null); then
  printf 'ERR  %s\n' "Invalid --date supplied: $date_arg" >&2
  exit 2
fi

set -- $week_nav
prev_week_tag=$1
iso_week_tag=$2
next_week_tag=$3
set --

if ! current_month_tag=$(month_tag_for_utc_date "$date_arg" 2>/dev/null); then
  printf 'ERR  %s\n' "Invalid --date supplied: $date_arg" >&2
  exit 2
fi

if ! current_year=$(year_for_utc_date "$date_arg" 2>/dev/null); then
  printf 'ERR  %s\n' "Invalid --date supplied: $date_arg" >&2
  exit 2
fi

if ! current_quarter_tag=$(quarter_tag_for_utc_date "$date_arg" 2>/dev/null); then
  printf 'ERR  %s\n' "Invalid --date supplied: $date_arg" >&2
  exit 2
fi

vault_root=${vault_path%/}

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

note_path="${note_dir%/}/${iso_week_tag}.md"

dry_run_primary_path=$note_path
dry_run_output_path="${repo_root%/}/Weekly Note Sample.md"

printf 'INFO %s\n' "Vault path: $vault_root"
printf 'INFO %s\n' "Weekly note directory: $note_dir"
printf 'INFO %s\n' "Target week/date: ${iso_week_tag} (source date: $date_arg)"
printf 'INFO %s\n' "Primary weekly note path: $note_path"

if [ "$dry_run" -eq 1 ]; then
  printf 'INFO %s\n' "Dry run: would ensure directory exists: $note_dir"
else
  mkdir -p "$note_dir"
fi

if [ -f "$note_path" ] && [ "$force" -ne 1 ]; then
  printf 'ERR  %s\n' "Refusing to overwrite existing file: $note_path" >&2
  printf '     Re-run with --force to overwrite.\n' >&2
  exit 1
fi

write_output "$note_path" <<EOF_NOTE
# Week ${iso_week_tag}

<<[[Periodic Notes/Weekly Notes/${prev_week_tag}|${prev_week_tag}]] || [[Periodic Notes/Weekly Notes/${next_week_tag}|${next_week_tag}]]>>

## 🎯 Weekly Goal

**Goal:**  
\`weekly_goal:: \`

**Why it matters:**  
> One or two sentences at most.

**Definition of Done:**  
- [ ] Clear outcome  
- [ ] Observable result  

---

## 📋 Weekly Checklist
(These need to be incorporated into the cascading tasks system)
- [ ] Weekly Review
- [ ] Plan Weekly Goal
- [ ] Review Calendar
- [ ] Prep Meals / Ingredients

---

## 🧩 Cascading Tasks

\`\`\`tasks
not done
tag includes due/${iso_week_tag}
\`\`\`

## Links

[[Weekly Routine]]
[[Weekly Goal Queue]]
[[Weekly Note Template]]

EOF_NOTE

if [ "$dry_run" -eq 1 ]; then
  printf 'INFO %s\n' "Dry run: weekly note sample written to $dry_run_output_path"
else
  printf 'INFO %s\n' "Weekly note created: $note_path"
fi

