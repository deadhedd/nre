#!/bin/sh
# Generate a monthly note markdown file equivalent to the legacy Node script.
# The script accepts optional CLI arguments to control the vault location,
# output directory, target month, locale, and overwrite behavior.

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd -P)
utils_dir="$repo_root/utils"
commit_helper="$utils_dir/core/commit.sh"
date_helper="$utils_dir/core/date-period-helpers.sh"

. "$date_helper"

usage() {
  cat <<'EOF_USAGE'
Usage: generate-monthly-note.sh [--vault <path>] [--outdir <name>] [--date YYYY-MM] [--locale <locale>] [--force] [--dry-run]

Options:
  --vault <path>    Vault root where the note should be created. Defaults to $VAULT_PATH or /home/obsidian/vaults/Main.
  --outdir <name>   Subdirectory inside the vault. Defaults to "Periodic Notes/Monthly Notes".
  --date YYYY-MM    Month to generate. Defaults to the current UTC month.
  --locale <locale> Locale for the month name (e.g., en-US). Defaults to en_US.UTF-8.
  --force           Overwrite the note if it already exists.
  --dry-run         Output the note contents to stdout without writing files.
  --help            Show this message.
EOF_USAGE
}

normalize_locale() {
  input=$1
  if [ -z "$input" ]; then
    printf 'en_US.UTF-8'
    return
  fi
  converted=$(printf '%s' "$input" | tr '-' '_')
  case "$converted" in
    C|POSIX) printf '%s' "$converted" ;;
    *.*) printf '%s' "$converted" ;;
    *) printf '%s.UTF-8' "$converted" ;;
  esac
}

get_month_name() {
  locale_value=$1
  target=$2

  if ! epoch=$(epoch_for_utc_date "$target"); then
    printf '❌ Failed to compute epoch for %s\n' "$target" >&2
    return 1
  fi

  # Offset into the middle of the month to prevent timezone rollbacks into the previous month.
  shifted_epoch=$((epoch + (12 * 60 * 60)))

  if month=$(LC_TIME="$locale_value" format_epoch_local "$shifted_epoch" '%B' 2>/dev/null); then
    printf '%s' "$month"
    return 0
  fi

  if fallback=$(LC_TIME=C format_epoch_local "$shifted_epoch" '%B' 2>/dev/null); then
    printf '%s' "$fallback"
    return 0
  fi

  printf '❌ Failed to format month name for %s\n' "$target" >&2
  return 1
}

vault_path=${VAULT_PATH:-/home/obsidian/vaults/Main}
outdir="Periodic Notes/Monthly Notes"
date_arg=""
locale="en_US.UTF-8"
force=0
dry_run=0

write_output() {
  dest=$1
  if [ "$dry_run" -eq 1 ]; then
    printf 'ℹ️ DRY RUN start: %s\n' "$dest"
    cat
    printf 'ℹ️ DRY RUN end: %s\n' "$dest"
  else
    cat >"$dest"
  fi
}

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
    --locale)
      if [ $# -lt 2 ]; then
        echo "❌ Missing value for --locale" >&2
        usage
        exit 2
      fi
      locale=$(normalize_locale "$2")
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
      echo "❌ Unknown option: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [ -z "$date_arg" ]; then
  date_arg=$(date -u +%Y-%m)
fi

case "$date_arg" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9])
    :
    ;;
  *)
    echo "❌ --date must be in YYYY-MM format" >&2
    exit 2
    ;;
esac

year=${date_arg%%-*}
month_part=${date_arg#*-}
month_number=${month_part#0}
if [ -z "$month_number" ]; then
  month_number=0
fi
if [ "$month_number" -lt 1 ] || [ "$month_number" -gt 12 ]; then
  echo "❌ Invalid month supplied: $month_part" >&2
  exit 2
fi

month=$(printf '%02d' "$month_number")
month_tag="${year}-${month}"
quarter=$(( (month_number + 2) / 3 ))
quarter_tag="${year}-Q${quarter}"

if ! set -- $(add_months "$year" "$month" -1); then
  printf '❌ Failed to compute previous month for %s-%s\n' "$year" "$month" >&2
  exit 1
fi
prev_tag=$(printf '%04d-%02d' "$1" "$2")

if ! set -- $(add_months "$year" "$month" 1); then
  printf '❌ Failed to compute next month for %s-%s\n' "$year" "$month" >&2
  exit 1
fi
next_tag=$(printf '%04d-%02d' "$1" "$2")

if ! month_name=$(get_month_name "$locale" "${year}-${month}-01"); then
  printf '❌ Failed to determine localized month name\n' >&2
  exit 1
fi

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

note_path="${note_dir%/}/${month_tag}.md"

if [ "$dry_run" -eq 1 ]; then
  printf 'ℹ️ Dry run: would ensure directory exists: %s\n' "$note_dir"
else
  mkdir -p "$note_dir"
fi

if [ -f "$note_path" ] && [ "$force" -ne 1 ]; then
  echo "❌ Refusing to overwrite existing file: $note_path" >&2
  echo "   Re-run with --force to overwrite." >&2
  exit 1
fi

write_output "$note_path" <<EOF_NOTE
# ${month_name} ${year}

- [[Periodic Notes/Monthly Notes/${prev_tag}|${prev_tag}]]
- [[Periodic Notes/Monthly Notes/${next_tag}|${next_tag}]]

## Cascading Tasks

\`\`\`dataview
task
from ""
where contains(tags, "due/${month_tag}")
   OR contains(tags, "due/${quarter_tag}")
   OR contains(tags, "due/${year}")
\`\`\`

## Monthly Checklist

-  Check home maintenance tasks
-  Plan major goals for next month
- [ ] Clean out the fridge
- [ ] Order Johnie's inhaler
- [ ] Finance review

## budget

### Regular expenses:
##### Essentials:
- Garbage: 70 (Feb, May, Aug, Nov)
- Internet: 45 (Monthly)
- Electricity: 120-300 (Monthly)
- Car Payment: 616 (monthly)
- Car insurance 1750 (Jul, Nov)
**Total**: 781-2781
##### Non-essentials:
- Chatgpt: 22 (Monthly)
- YT Premium: 25 (Monthly)
- Audible 18 (Bi-monthly (odd))
- Patreon: 4 (Monthly)
- Apple Music: 11 (Monthly)
- Fitbod: 80 (Yearly (Oct))
- itunes match: 25 (Yearly (Jun))
- F1TV: 85 (Jul)
**Total**: 62-227

##### **Total Regular Expenses:
- 843-3008
##### Income:
(~1400 expected)
- (###)
##### Expenses:
- (###)
##### Net:
- (###)

## Goals

## Review

- What went well:

- What didn’t:

- Lessons learned:

## Notes
EOF_NOTE

if [ "$dry_run" -eq 1 ]; then
  printf 'ℹ️ Dry run: monthly note would be written to %s\n' "$note_path"
fi

if [ "$dry_run" -eq 1 ]; then
  printf 'ℹ️ Dry run: skipping commit helper\n'
elif [ -x "$commit_helper" ]; then
  printf 'ℹ️ Invoking commit helper\n'
  "$commit_helper" -c "monthly note" "$vault_path" "monthly note: $month_tag" "$note_path"
else
  printf '⚠️ commit helper not found: %s\n' "$commit_helper" >&2
fi
