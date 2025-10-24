#!/bin/sh
# Generate a yearly note markdown file inspired by the legacy Node version.
# Provides CLI options to control the vault, output directory, target year, and overwrite behavior.

set -eu

usage() {
  cat <<'EOF_USAGE'
Usage: generate-yearly-note.sh [--vault <path>] [--outdir <name>] [--year YYYY] [--force]

Options:
  --vault <path>    Vault root where the note should be created. Defaults to $VAULT_PATH or /home/obsidian/vaults/Main.
  --outdir <name>   Subdirectory inside the vault. Defaults to "Periodic Notes/Yearly Notes".
  --year YYYY       Year to generate. Defaults to the current UTC year.
  --force           Overwrite the note if it already exists.
  --help            Show this message.
EOF_USAGE
}

vault_path=${VAULT_PATH:-/home/obsidian/vaults/Main}
outdir="Periodic Notes/Yearly Notes"
year_arg=""
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
    --year)
      if [ $# -lt 2 ]; then
        echo "❌ Missing value for --year" >&2
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

if [ -n "$year_arg" ]; then
  case "$year_arg" in
    [0-9][0-9][0-9][0-9])
      target_year=$year_arg
      ;;
    *)
      echo "❌ --year must use the format YYYY (e.g., 2025)" >&2
      exit 2
      ;;
  esac
else
  target_year=$(date -u +%Y)
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

mkdir -p "$note_dir"

if [ -f "$note_path" ] && [ "$force" -ne 1 ]; then
  echo "❌ Refusing to overwrite existing file: $note_path" >&2
  echo "   Re-run with --force to overwrite." >&2
  exit 1
fi

cat <<EOF_NOTE >"$note_path"
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
