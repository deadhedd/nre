#!/bin/sh
# utils/elements/generate-day-plan.sh — Extract day/blocks from "Daily Plan.md"
#
# Helper executable (NOT a leaf job):
# - Invoked by generate-daily-note.sh (which is the wrapped leaf).
# - stdout: content only (markdown text).
# - stderr: diagnostics only (never leak INFO lines into note content).
# - No wrapper, no cadence, no commit registration.
#
# Modes:
#   - No --block         -> print today's section + tomorrow preview (legacy mode)
#   - --block <BlockName>-> print only that block for resolved day/date (for subnotes)
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

# Default vault root: prefer VAULT_ROOT (new system), then VAULT_PATH (legacy), then default.
vault_base="${VAULT_ROOT:-${VAULT_PATH:-/home/obsidian/vaults/Main}}"
vault_base="${vault_base%/}"

# Default Daily Plan path (vault-relative)
relative_path='000 - General Knowledge, Information Science, and Computing/005 - Computer Programming, Information, and Security/005.7 - Data/Templates/Daily Plan.md'
default_file="${vault_base}/${relative_path}"

# Legacy helper library (weekday/date math)
# Keep existing dependency for now; this pass is organization/compliance.
core_dir=$(CDPATH= cd "$script_dir/../core" 2>/dev/null && pwd) || core_dir=""
date_helpers="${core_dir%/}/date-period-helpers.sh"

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
  - If --date is provided, weekday is derived from that date.
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
file="$default_file"

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

###############################################################################
# Preconditions
###############################################################################
if [ -z "$core_dir" ] || [ ! -r "$date_helpers" ]; then
  die "required helper lib not found/readable: $date_helpers"
fi
# shellcheck source=/dev/null
. "$date_helpers" || die "failed to source helper lib: $date_helpers"

if [ ! -f "$file" ]; then
  die "missing Daily Plan file: $file"
fi

log_debug "using day plan file: $file"

###############################################################################
# Day resolution
###############################################################################
# NOTE: these functions come from date-period-helpers.sh (legacy core helpers)
today_date=$(get_today)
today_index=$(weekday_for_utc_date "$today_date") || die "unable to resolve today's weekday"
today_name=$(weekday_name_for_index "$today_index") || die "unable to resolve today's weekday name"

tomorrow_date=$(shift_utc_date_by_days "$today_date" 1) || die "unable to resolve tomorrow's date"
tomorrow_index=$(weekday_for_utc_date "$tomorrow_date") || die "unable to resolve tomorrow's weekday"
tomorrow_name=$(weekday_name_for_index "$tomorrow_index") || die "unable to resolve tomorrow's weekday name"

dow_from_date() {
  _d=$1
  _idx=$(weekday_for_utc_date "$_d") || die "cannot derive weekday from --date on this host; omit --date or provide --day"
  weekday_name_for_index "$_idx"
}

day_resolved=""
if [ -n "$DATE_IN" ]; then
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
  _day=$1
  # Allow emojis and extra text after the day header (e.g., "## 💕 Monday (Deep Work)").
  awk -v day="$_day" '
    BEGIN { in_day = 0 }

    /^##[[:space:]]/ {
      header = $0
      gsub(/[^[:alpha:][:space:]]/, "", header)
      header = " " header " "
      if (index(header, " " day " ") > 0) {
        in_day = 1
        print $0
        next
      } else if (in_day) {
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
  _day=$1
  _block=$2

  awk -v day="$_day" -v block="$_block" '
    BEGIN { in_day=0; in_blk=0 }

    /^##[[:space:]]/ {
      header = $0
      gsub(/[^[:alpha:][:space:]]/, "", header)
      header = " " header " "
      if (index(header, " " day " ") > 0) in_day=1; else in_day=0
      in_blk=0
      next
    }

    in_day && /^####+/ {
      header = $0
      sub(/^#+[[:space:]]*/, "", header)
      if (header == block) {
        in_blk=1
      } else {
        if (in_blk) exit
        in_blk=0
      }
      next
    }

    in_day && in_blk && /^##[[:space:]]/ { exit }

    in_day && in_blk { print }
  ' "$file" | awk '
    { lines[++n]=$0 }
    END {
      s=1; while (s<=n && lines[s] ~ /^[[:space:]]*$/) s++
      e=n; while (e>=s && lines[e] ~ /^[[:space:]]*$/) e--
      for (i=s; i<=e; i++) print lines[i]
    }
  '
}

print_block() {
  _d=$1
  _b=$2

  _out=$(extract_block_for_day "$_d" "$_b" || true)
  if [ -n "${_out:-}" ]; then
    printf '%s\n' "$_out"
    return 0
  fi

  log_warn "block not found: day='$_d' block='$_b'"
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
