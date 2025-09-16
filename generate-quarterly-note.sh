#!/bin/sh
# Generate a quarterly note markdown file based on the legacy Node implementation.
# Supports configuring the vault, output directory, target quarter, and overwrite behavior.

set -eu

usage() {
  cat <<'EOF_USAGE'
Usage: generate-quarterly-note.sh [--vault <path>] [--outdir <name>] [--date YYYY-QN] [--force]

Options:
  --vault <path>    Vault root where the note should be created. Defaults to $PWD or $VAULT_PATH if set.
  --outdir <name>   Subdirectory inside the vault. Defaults to "Quarterly Notes".
  --date YYYY-QN    Quarter to generate (e.g., 2025-Q3). Defaults to the current UTC quarter.
  --force           Overwrite the note if it already exists.
  --help            Show this message.
EOF_USAGE
}

vault_path=${VAULT_PATH:-$(pwd)}
outdir="Quarterly Notes"
date_arg=""
force=0

while [ $# -gt 0 ]; do
  case "$1" in
    --vault)
      if [ $# -lt 2 ]; then
        echo "❌ Missing value for --vault" >&2
        usage
        exit 2
      fi
      vault_path=$2
      shift 2
      ;;
    --outdir)
      if [ $# -lt 2 ]; then
        echo "❌ Missing value for --outdir" >&2
        usage
        exit 2
      fi
      outdir=$2
      shift 2
      ;;
    --date)
      if [ $# -lt 2 ]; then
        echo "❌ Missing value for --date" >&2
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
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "❌ Unknown option: $1" >&2
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
      echo "❌ --date must use the format YYYY-QN (e.g., 2025-Q3)" >&2
      exit 2
      ;;
  esac
else
  current_year=$(date -u +%Y)
  current_month=$(date -u +%m)
  month_number=${current_month#0}
  if [ -z "$month_number" ]; then
    month_number=0
  fi
  target_year=$current_year
  target_quarter=$(( (month_number + 2) / 3 ))
fi

tag="${target_year}-Q${target_quarter}"

if [ "$target_quarter" -lt 1 ] || [ "$target_quarter" -gt 4 ]; then
  echo "❌ Quarter must be between 1 and 4" >&2
  exit 2
fi

if [ "$target_quarter" -eq 1 ]; then
  prev_year=$((target_year - 1))
  prev_quarter=4
else
  prev_year=$target_year
  prev_quarter=$((target_quarter - 1))
fi

if [ "$target_quarter" -eq 4 ]; then
  next_year=$((target_year + 1))
  next_quarter=1
else
  next_year=$target_year
  next_quarter=$((target_quarter + 1))
fi

prev_link="Q${prev_quarter} ${prev_year}"
next_link="Q${next_quarter} ${next_year}"

note_dir="$vault_path/$outdir"
note_path="$note_dir/${tag}.md"

mkdir -p "$note_dir"

if [ -f "$note_path" ] && [ "$force" -ne 1 ]; then
  echo "❌ Refusing to overwrite existing file: $note_path" >&2
  echo "   Re-run with --force to overwrite." >&2
  exit 1
fi

cat <<EOF_NOTE >"$note_path"
# ${tag}

- [[${prev_link}]]
- [[${next_link}]]

## Cascading Tasks

\`\`\`dataview
task
from ""
where contains(tags, "due/${tag}")
   OR contains(tags, "due/${target_year}")
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
