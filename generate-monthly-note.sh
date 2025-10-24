#!/bin/sh
# Generate a monthly note markdown file equivalent to the legacy Node script.
# The script accepts optional CLI arguments to control the vault location,
# output directory, target month, locale, and overwrite behavior.

set -eu

usage() {
  cat <<'EOF_USAGE'
Usage: generate-monthly-note.sh [--vault <path>] [--outdir <name>] [--date YYYY-MM] [--locale <locale>] [--force]

Options:
  --vault <path>    Vault root where the note should be created. Defaults to $VAULT_PATH or /home/obsidian/vaults/Main.
  --outdir <name>   Subdirectory inside the vault. Defaults to "Periodic Notes/Monthly Notes".
  --date YYYY-MM    Month to generate. Defaults to the current UTC month.
  --locale <locale> Locale for the month name (e.g., en-US). Defaults to en_US.UTF-8.
  --force           Overwrite the note if it already exists.
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
  if month=$(LC_TIME="$locale_value" date -u -d "$target" +%B 2>/dev/null); then
    printf '%s' "$month"
  else
    LC_TIME=C date -u -d "$target" +%B
  fi
}

vault_path=${VAULT_PATH:-/home/obsidian/vaults/Main}
outdir="Periodic Notes/Monthly Notes"
date_arg=""
locale="en_US.UTF-8"
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

prev_tag=$(date -u -d "${year}-${month}-01 -1 month" +%Y-%m)
next_tag=$(date -u -d "${year}-${month}-01 +1 month" +%Y-%m)

month_name=$(get_month_name "$locale" "${year}-${month}-01")

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

mkdir -p "$note_dir"

if [ -f "$note_path" ] && [ "$force" -ne 1 ]; then
  echo "❌ Refusing to overwrite existing file: $note_path" >&2
  echo "   Re-run with --force to overwrite." >&2
  exit 1
fi

cat <<EOF_NOTE >"$note_path"
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
