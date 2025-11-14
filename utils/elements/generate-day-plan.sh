#!/bin/sh
# Extract day/blocks out of "Daily Plan.md" for automation use.
# Modes:
#   - No --block → print today's section + tomorrow preview (legacy mode)
#   - --block <BlockName> → print only that block for the resolved day/date (for subnotes)
# Args:
#   --date YYYY-MM-DD  (optional; derives weekday)
#   --day  Monday..Sunday (optional; overrides derived weekday)
#   --file <path to Daily Plan.md> (optional; overrides default)

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
core_dir=$(dirname -- "$script_dir")/core
# shellcheck source=../core/date-period-helpers.sh
. "$core_dir/date-period-helpers.sh"

vault_base="${VAULT_PATH:-/home/obsidian/vaults/Main}"
vault_base="${vault_base%/}"
relative_path='000 - General Knowledge, Information Science, and Computing/005 - Computer Programming, Information, and Security/005.7 - Data/Templates/Daily Plan.md'
file="${vault_base}/${relative_path}"

die(){ printf '%s\n' "$*" >&2; exit 1; }

[ -f "$file" ] || die "❓ Missing template: $file"

DAY_NAME=""
DATE_IN=""
BLOCK=""

while [ $# -gt 0 ]; do
  case "$1" in
    --day)   DAY_NAME="${2:-}"; shift 2 || true ;;
    --date)  DATE_IN="${2:-}"; shift 2 || true ;;
    --block) BLOCK="${2:-}"; shift 2 || true ;;
    --file)  file="${2:-}";  shift 2 || true ;;
    --help|-h)
      cat <<'EOT'
Usage:
  generate-day-plan.sh [--day <Mon..Sun> | --date YYYY-MM-DD] [--block <BlockName>] [--file <Daily Plan.md>]

Modes:
  - No --block     → prints today's section + tomorrow preview (legacy)
  - With --block   → prints only that block for the resolved day/date (for subnotes)

Notes:
  - If --date is provided, weekday is derived from that date.
  - If --day is provided, it overrides the derived weekday.
  - Recognized blocks are the headings under "##### <BlockName>" in Daily Plan.md.
EOT
      exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

today_date=$(get_today)
today_index=$(weekday_for_utc_date "$today_date") || die "Unable to resolve today's weekday"
today_name=$(weekday_name_for_index "$today_index") || die "Unable to resolve today's weekday name"
tomorrow_date=$(shift_utc_date_by_days "$today_date" 1) || die "Unable to resolve tomorrow's date"
tomorrow_index=$(weekday_for_utc_date "$tomorrow_date") || die "Unable to resolve tomorrow's weekday"
tomorrow_name=$(weekday_name_for_index "$tomorrow_index") || die "Unable to resolve tomorrow's weekday name"

dow_from_date() {
  d="$1"
  idx=$(weekday_for_utc_date "$d") || die "This host cannot derive weekday from --date; omit --date or provide --day"
  weekday_name_for_index "$idx"
}

if [ -n "$DATE_IN" ]; then
  day_resolved=$(dow_from_date "$DATE_IN")
else
  day_resolved="$today_name"
fi

if [ -n "$DAY_NAME" ]; then
  day_resolved="$DAY_NAME"
fi

extract_day_section() {
  awk -v pat="^## ${1}\$" '
    $0 ~ pat {in_day=1; next}
    in_day && /^## / {exit}
    in_day {print}
  ' "$file"
}

extract_block_for_day() {
  day="$1"; block="$2"
  awk -v d="^## ${day}$" -v b="^##### ${block}($| )" '
    $0 ~ d {in_day=1; next}
    in_day && /^## / {in_day=0}
    in_day && $0 ~ b {in_blk=1; next}
    in_blk && (/^##### / || /^## /) {exit}
    in_blk {print}
  ' "$file" | awk '
    {lines[++n]=$0}
    END{
      s=1; while(s<=n && lines[s] ~ /^[[:space:]]*$/) s++
      e=n; while(e>=s && lines[e] ~ /^[[:space:]]*$/) e--
      for(i=s;i<=e;i++) print lines[i]
    }
  '
}

print_block() {
  d="$1"; b="$2"
  out="$(extract_block_for_day "$d" "$b" || true)"
  if [ -n "$out" ]; then
    printf '%s\n' "$out"
    return 0
  fi
  return 0
}

if [ -n "$BLOCK" ]; then
  print_block "$day_resolved" "$BLOCK"
  exit 0
fi

# Legacy: full today + tomorrow
printf '# Daily Plan - %s\n\n' "$today_name"
printf '## %s\n' "$today_name"
extract_day_section "$today_name" || true
printf '\n## Preview of Tomorrow: %s\n' "$tomorrow_name"
printf '## %s\n' "$tomorrow_name"
extract_day_section "$tomorrow_name" || true
