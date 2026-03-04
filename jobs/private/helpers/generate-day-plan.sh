#!/bin/sh
# utils/elements/generate-day-plan.sh — Extract day/blocks from "Daily Plan.md"
#
# Helper executable (NOT a leaf job):
# - Invoked by generate-daily-note.sh (the wrapped leaf job).
# - stdout: content only (markdown text).
# - stderr: diagnostics only (never leak INFO lines into note content).
# - No wrapper, no cadence, no commit registration.
#
# Modes:
#   - No --block         -> print today's section + tomorrow preview (legacy mode)
#   - --block <BlockName>-> print only that block for the resolved day/date (for subnotes)
#
# Options:
#   --date YYYY-MM-DD    (optional; derives weekday)
#   --day  Monday..Sunday(optional; overrides derived weekday)
#   --file <path>        (optional; overrides default Daily Plan.md path)
#
# Author: deadhedd
# License: MIT
# shellcheck shell=sh

set -eu
PATH="/usr/local/bin:/usr/bin:/bin:${PATH:-}"

###############################################################################
# Logging (stderr only)
###############################################################################
log_debug() { printf '%s\n' "DEBUG: $*" >&2; }
log_info()  { printf '%s\n' "INFO: $*"  >&2; }
log_warn()  { printf '%s\n' "WARN: $*"  >&2; }
log_error() { printf '%s\n' "ERROR: $*" >&2; }

die() { log_error "$*"; exit 1; }

###############################################################################
# Resolve paths
###############################################################################
script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)

if [ -z "${REPO_ROOT:-}" ]; then
  die "REPO_ROOT not set (expected wrapped invocation)"
fi
case "$REPO_ROOT" in
  /*) : ;;
  *) die "REPO_ROOT not absolute: $REPO_ROOT" ;;
esac
repo_root=$REPO_ROOT

lib_dir=$repo_root/engine/lib
datetime_lib=$lib_dir/datetime.sh
periods_lib=$lib_dir/periods.sh

# Engine libs (local-first): datetime then periods (periods depends on datetime)
if [ ! -r "$datetime_lib" ]; then
  die "datetime lib not found/readable: $datetime_lib"
fi
# shellcheck source=/dev/null
. "$datetime_lib" || die "failed to source datetime lib: $datetime_lib"

if [ ! -r "$periods_lib" ]; then
  die "periods lib not found/readable: $periods_lib"
fi
# shellcheck source=/dev/null
. "$periods_lib" || die "failed to source periods lib: $periods_lib"

###############################################################################
# Default Daily Plan path
###############################################################################
# Prefer VAULT_ROOT (new system), then VAULT_PATH (legacy), then default.
vault_base="${VAULT_ROOT:-${VAULT_PATH:-/home/obsidian/vaults/Main}}"
vault_base="${vault_base%/}"
relative_path='000 - General Knowledge, Information Science, and Computing/005 - Computer Programming, Information, and Security/005.7 - Data/Templates/Daily Plan.md'
file="${vault_base}/${relative_path}"

###############################################################################
# Usage
###############################################################################
usage() {
  cat <<'EOT'
Usage:
  generate-day-plan.sh [--day <Monday..Sunday> | --date YYYY-MM-DD] [--block <BlockName>] [--file <Daily Plan.md>]

Modes:
  - No --block     -> prints today's section + tomorrow preview (legacy)
  - With --block   -> prints only that block for the resolved day/date (for subnotes)

Notes:
  - If --date is provided, weekday is derived from that date (local-first).
  - If --day is provided, it overrides the derived weekday.
  - Recognized blocks are headings under "#### <BlockName>" or "##### <BlockName>" in Daily Plan.md.
  - stdout is content only; diagnostics go to stderr.
EOT
}

###############################################################################
# Args
###############################################################################
DAY_NAME=""
DATE_IN=""
BLOCK=""

while [ $# -gt 0 ]; do
  case "$1" in
    --day)
      [ $# -ge 2 ] || { usage >&2; die "missing value for --day"; }
      DAY_NAME=$2
      shift 2
      ;;
    --date)
      [ $# -ge 2 ] || { usage >&2; die "missing value for --date"; }
      DATE_IN=$2
      shift 2
      ;;
    --block)
      [ $# -ge 2 ] || { usage >&2; die "missing value for --block"; }
      BLOCK=$2
      shift 2
      ;;
    --file)
      [ $# -ge 2 ] || { usage >&2; die "missing value for --file"; }
      file=$2
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage >&2
      die "unknown argument: $1"
      ;;
  esac
done

if [ ! -f "$file" ]; then
  die "missing Daily Plan file: $file"
fi

log_debug "using day plan file: $file"

###############################################################################
# Day resolution (local-first via datetime+periods)
###############################################################################
today_date=$(pr_today) || die "unable to resolve today's date"
today_index=$(pr_weekday_index_for_date "$today_date") || die "unable to resolve today's weekday index"
today_name=$(pr_weekday_name_for_index "$today_index") || die "unable to resolve today's weekday name"

tomorrow_date=$(pr_tomorrow) || die "unable to resolve tomorrow's date"
tomorrow_index=$(pr_weekday_index_for_date "$tomorrow_date") || die "unable to resolve tomorrow's weekday index"
tomorrow_name=$(pr_weekday_name_for_index "$tomorrow_index") || die "unable to resolve tomorrow's weekday name"

dow_from_date() {
  _d=${1:-}
  [ -n "$_d" ] || die "internal: dow_from_date missing date"
  _idx=$(pr_weekday_index_for_date "$_d") || die "cannot derive weekday from --date $_d"
  pr_weekday_name_for_index "$_idx" || die "cannot map weekday index to name (idx=$_idx)"
}

day_resolved=""
if [ -n "$DATE_IN" ]; then
  # Validate format early for clearer errors.
  dt_check_ymd "$DATE_IN" || die "invalid --date (expected YYYY-MM-DD): $DATE_IN"
  day_resolved=$(dow_from_date "$DATE_IN")
  log_debug "resolved weekday from --date $DATE_IN: $day_resolved"
else
  day_resolved=$today_name
fi

if [ -n "$DAY_NAME" ]; then
  day_resolved=$DAY_NAME
  log_debug "using explicit --day override: $day_resolved"
fi

###############################################################################
# Extraction helpers (stdout is content)
###############################################################################
extract_day_section() {
  day=$1
  # Allow emojis and extra text after the day header (e.g., "## 💕 Monday (Deep Work)").
  awk -v day="$day" '
    BEGIN { in_day = 0 }

    # Any H2 header: "## ...".
    /^##[[:space:]]/ {
      header = $0
      # Strip anything that is not a letter or space: removes "##", emojis, punctuation.
      gsub(/[^[:alpha:][:space:]]/, "", header)
      # Pad with spaces to make word-boundary detection easy.
      header = " " header " "
      if (index(header, " " day " ") > 0) {
        in_day = 1
        # IMPORTANT: print the original header so emoji survive
        print $0
        next
      } else if (in_day) {
        # We hit the next day header; stop this section.
        exit
      } else {
        in_day = 0
        next
      }
    }

    in_day { print }
  ' "$file"
}

extract_block_for_day() {
  day=$1
  block=$2
  # Accept 4+ hash headers so the plan can use either #### or ##### levels.
  awk -v day="$day" -v block="$block" '
    BEGIN {
      in_day  = 0
      in_blk  = 0
    }

    # Day headers like:
    #   "## 😓 Sunday"
    #   "## 💕 Saturday"
    #   "## Wednesday (Stuff)"
    /^##[[:space:]]/ {
      header = $0
      gsub(/[^[:alpha:][:space:]]/, "", header)
      header = " " header " "
      if (index(header, " " day " ") > 0) {
        in_day = 1
      } else {
        in_day = 0
      }
      in_blk = 0
      next
    }

    # Within the day, find block headers:
    #   "##### Morning"
    #   "##### Wake Up"
    in_day && /^####+/ {
      header = $0
      sub(/^#+[[:space:]]*/, "", header)  # strip leading #s and spaces
      if (header == block) {
        in_blk = 1
      } else {
        # If we were already in a block and see a different block, stop.
        if (in_blk) {
          exit
        }
        in_blk = 0
      }
      next
    }

    # If we’re in a block and hit the next day, stop.
    in_day && in_blk && /^##[[:space:]]/ { exit }

    # Lines that belong to the chosen block for the chosen day.
    in_day && in_blk {
      print
    }
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
  d=$1
  b=$2
  out=$(extract_block_for_day "$d" "$b" || true)
  if [ -n "${out:-}" ]; then
    printf '%s\n' "$out"
    return 0
  fi
  log_warn "block not found: day='$d' block='$b'"
  return 0
}

###############################################################################
# Main
###############################################################################
if [ -n "$BLOCK" ]; then
  log_debug "extracting block='$BLOCK' for day='$day_resolved'"
  print_block "$day_resolved" "$BLOCK"
  exit 0
fi

# Legacy mode: full today + tomorrow
log_debug "printing full plan for today='$today_name' with preview tomorrow='$tomorrow_name'"

printf '# Daily Plan - %s\n\n' "$today_name"
extract_day_section "$today_name" || true

printf '\n## Preview of Tomorrow: %s\n' "$tomorrow_name"
extract_day_section "$tomorrow_name" || true

exit 0
