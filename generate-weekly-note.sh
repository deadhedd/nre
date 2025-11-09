#!/bin/sh
# generate-weekly-note.sh — Generate a weekly note equivalent to the legacy Node script.
# Author: deadhedd
# License: MIT
set -eu

usage() {
  cat <<'EOF_USAGE'
Usage: generate-weekly-note.sh [--vault <path>] [--outdir <name>] [--date YYYY-MM-DD] [--force] [--dry-run]

Options:
  --vault <path>    Vault root where the note should be created. Defaults to $VAULT_PATH or /home/obsidian/vaults/Main.
  --outdir <name>   Subdirectory inside the vault. Defaults to "Periodic Notes/Weekly Notes".
  --date YYYY-MM-DD Target date used to determine the week tag. Defaults to the current UTC date.
  --force           Overwrite the note if it already exists.
  --dry-run         Output the note contents to stdout without writing files.
  --help            Show this message.
EOF_USAGE
}

log_info() { printf 'INFO %s\n' "$*"; }
log_err() { printf 'ERR %s\n' "$*"; }

vault_path=${VAULT_PATH:-/home/obsidian/vaults/Main}
outdir="Periodic Notes/Weekly Notes"
date_arg=""
force=0
dry_run=0

write_output() {
  dest=$1
  if [ "$dry_run" -eq 1 ]; then
    log_info "DRY RUN start: $dest"
    cat
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

if [ -z "$date_arg" ]; then
  date_arg=$(date -u +%Y-%m-%d)
fi

case "$date_arg" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
    :
    ;;
  *)
    log_err "--date must be in YYYY-MM-DD format"
    exit 2
    ;;
esac

if ! target_epoch=$(date -u -d "$date_arg" +%s 2>/dev/null); then
  log_err "Invalid --date supplied: $date_arg"
  exit 2
fi

iso_week_tag=$(date -u -d "@$target_epoch" +%G-W%V)
prev_week_tag=$(date -u -d "@$((target_epoch - 7 * 86400))" +%G-W%V)
next_week_tag=$(date -u -d "@$((target_epoch + 7 * 86400))" +%G-W%V)
current_month_tag=$(date -u -d "@$target_epoch" +%Y-%m)
current_year=$(date -u -d "@$target_epoch" +%Y)
month_number=$(date -u -d "@$target_epoch" +%m)
month_number=${month_number#0}
if [ -z "$month_number" ]; then
  month_number=0
fi
quarter=$(( (month_number + 2) / 3 ))
current_quarter_tag=$(printf 'Q%d-%s' "$quarter" "$current_year")

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

if [ "$dry_run" -eq 1 ]; then
  log_info "Dry run: would ensure directory exists: $note_dir"
else
  mkdir -p "$note_dir"
fi

if [ -f "$note_path" ] && [ "$force" -ne 1 ]; then
  log_err "Refusing to overwrite existing file: $note_path"
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

\`\`\`dataview
task
from ""
where contains(tags, "due/${iso_week_tag}")
   OR contains(tags, "due/${current_month_tag}")
   OR contains(tags, "due/${current_quarter_tag}")
   OR contains(tags, "due/${current_year}")
\`\`\`

## Links

[[Weekly Routine]]
[[Weekly Goal Queue]]
[[Weekly Note Template]]

EOF_NOTE

if [ "$dry_run" -eq 1 ]; then
  log_info "Dry run: weekly note would be written to $note_path"
fi

log_info "Weekly note created: $note_path"
