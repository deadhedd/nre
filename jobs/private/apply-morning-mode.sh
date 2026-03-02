#!/bin/sh
# jobs/private/apply-morning-mode.sh
# Patch today's "Wake Up" subnote based on a selected morning mode, filtering
# tasks by Tasks-plugin priority glyphs.
#
# Leaf job (wrapper required).
#
# Mode rules (priority glyphs in task lines):
#   ⏫ = high
#   🔼 = medium
#   🔽 = low
#   unmarked = low
#
# Modes:
#   minimal -> keep high only
#   trimmed -> keep high + medium
#   normal  -> keep all
#
# Author: deadhedd
# License: MIT
# shellcheck shell=sh

set -eu

###############################################################################
# Logging (leaf responsibility: emit correctly-formatted messages to stderr)
###############################################################################
log_debug() { printf '%s\n' "DEBUG: $*" >&2; }
log_info()  { printf '%s\n' "INFO: $*"  >&2; }
log_warn()  { printf '%s\n' "WARN: $*"  >&2; }
log_error() { printf '%s\n' "ERROR: $*" >&2; }

###############################################################################
# Resolve paths + self-wrap
###############################################################################
script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)
wrap="$script_dir/../../engine/wrap.sh"

case "$0" in
  /*) script_path=$0 ;;
  *)  script_path=$script_dir/${0##*/} ;;
esac

script_path=$(
  CDPATH= cd "$(dirname "$script_path")" && \
  d=$(pwd) && \
  printf '%s/%s\n' "$d" "${script_path##*/}"
) || {
  log_error "failed to canonicalize script path: $script_path"
  exit 127
}

if [ "${JOB_WRAP_ACTIVE:-0}" != "1" ]; then
  if [ ! -x "$wrap" ]; then
    log_error "leaf wrap: wrapper not found/executable: $wrap"
    exit 127
  fi
  log_info "leaf wrap: exec wrapper: $wrap"
  exec "$wrap" "$script_path" ${1+"$@"}
else
  log_debug "leaf wrap: wrapper active; executing leaf"
fi

###############################################################################
# Cadence declaration (contract-required)
###############################################################################
JOB_CADENCE="ad-hoc"
log_info "cadence=$JOB_CADENCE"

###############################################################################
# Wrapper-provided env
###############################################################################
if [ -z "${REPO_ROOT:-}" ]; then
  log_error "REPO_ROOT not set (wrapper required)"
  exit 127
fi
case "$REPO_ROOT" in
  /*) : ;;
  *) log_error "REPO_ROOT not absolute: $REPO_ROOT"; exit 127 ;;
esac
repo_root=$REPO_ROOT

if [ -z "${VAULT_ROOT:-}" ]; then
  log_error "VAULT_ROOT not set (wrapper required)"
  exit 127
fi
vault_root=$VAULT_ROOT

###############################################################################
# Engine libs
###############################################################################
lib_dir=$repo_root/engine/lib
periods_lib=$lib_dir/periods.sh
datetime_lib=$lib_dir/datetime.sh

if [ ! -r "$periods_lib" ]; then
  log_error "periods lib not found/readable: $periods_lib"
  exit 127
fi
# shellcheck source=/dev/null
. "$periods_lib" || { log_error "failed to source periods lib: $periods_lib"; exit 127; }

if [ ! -r "$datetime_lib" ]; then
  log_error "datetime lib not found/readable: $datetime_lib"
  exit 127
fi
# shellcheck source=/dev/null
. "$datetime_lib" || { log_error "failed to source datetime lib: $datetime_lib"; exit 127; }

###############################################################################
# Args
###############################################################################
usage() {
  cat <<'EOF_USAGE'
Usage: apply-morning-mode.sh --mode <minimal|trimmed|normal> [--date YYYY-MM-DD]

Notes:
- Patches today's Wake Up subnote by filtering tasks from Daily Plan.md Wake Up block.
- Requires generate-daily-note.sh to have written DP_BLOCK markers.
EOF_USAGE
}

MODE=""
DATE_IN=""

while [ $# -gt 0 ]; do
  case "$1" in
    --mode)
      [ $# -ge 2 ] || { log_error "missing value for --mode"; usage >&2; exit 2; }
      MODE=$2
      shift 2
      ;;
    --date)
      [ $# -ge 2 ] || { log_error "missing value for --date"; usage >&2; exit 2; }
      DATE_IN=$2
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      log_error "unknown option: $1"
      usage >&2
      exit 2
      ;;
  esac
done

case "$MODE" in
  minimal|trimmed|normal) : ;;
  *) log_error "invalid --mode: '$MODE' (expected minimal|trimmed|normal)"; exit 2 ;;
esac

if [ -n "$DATE_IN" ]; then
  dt_check_ymd "$DATE_IN" || { log_error "invalid --date (expected YYYY-MM-DD): $DATE_IN"; exit 2; }
  today=$DATE_IN
else
  today=$(pr_today) || { log_error "failed to resolve today"; exit 127; }
fi

###############################################################################
# Paths
###############################################################################
helpers_dir="$repo_root/jobs/private/helpers"
day_plan_script="$helpers_dir/generate-day-plan.sh"

periodic_dir="${vault_root%/}/Periodic Notes"
daily_note_dir="${periodic_dir%/}/Daily Notes"
subnotes_dir="${daily_note_dir%/}/Subnotes"
wake_subnote="${subnotes_dir%/}/${today} - Wake Up.md"

###############################################################################
# Helpers
###############################################################################
read_wake_block() {
  if [ ! -r "$day_plan_script" ]; then
    log_error "day plan script not found/readable: $day_plan_script"
    return 1
  fi
  # generate-day-plan.sh resolves weekday from local date, but if we pass --date
  # it will derive weekday for that date and extract correct day's block.
  if [ -n "$DATE_IN" ]; then
    sh "$day_plan_script" --date "$DATE_IN" --block "Wake Up"
  else
    sh "$day_plan_script" --block "Wake Up"
  fi
}

filter_by_mode() {
  _mode=$1
  # Rules:
  # - keep non-checklist lines as-is
  # - checklist lines:
  #   minimal -> keep only ⏫
  #   trimmed -> keep ⏫ or 🔼
  #   normal  -> keep all (including 🔽 and unmarked)
  awk -v mode="$_mode" '
    function is_checklist(line) {
      return (line ~ /^[[:space:]]*-[[:space:]]*\[[ xX]\][[:space:]]+/)
    }
    {
      line = $0
      if (!is_checklist(line)) {
        print line
        next
      }

      has_high = (index(line, "⏫") > 0)
      has_med  = (index(line, "🔼") > 0)
      has_low  = (index(line, "🔽") > 0)

      # unmarked counts as low
      unmarked = (!has_high && !has_med && !has_low)

      if (mode == "minimal") {
        if (has_high) print line
        next
      }

      if (mode == "trimmed") {
        if (has_high || has_med) print line
        next
      }

      # normal
      print line
    }
  '
}

rewrite_dp_block() {
  _file=$1
  _replacement=$2

  if [ ! -f "$_file" ]; then
    log_error "wake subnote not found: $_file"
    return 1
  fi

  # Ensure markers exist
  if ! grep -q '<!-- DP_BLOCK:BEGIN -->' "$_file" || ! grep -q '<!-- DP_BLOCK:END -->' "$_file"; then
    log_error "DP_BLOCK markers not found in: $_file (patch generate-daily-note.sh subnote template first)"
    return 1
  fi

  _dir=${_file%/*}
  _tmp="${_dir}/${_file##*/}.tmp.$$"

  (
    trap 'rm -f "$_tmp"' HUP INT TERM 0

    awk -v repl="$_replacement" '
      BEGIN { inblk = 0 }
      /<!--[[:space:]]*DP_BLOCK:BEGIN[[:space:]]*-->/ {
        print $0
        print repl
        inblk = 1
        next
      }
      /<!--[[:space:]]*DP_BLOCK:END[[:space:]]*-->/ {
        inblk = 0
        print $0
        next
      }
      !inblk { print $0 }
    ' "$_file" >"$_tmp" || exit 1

    mv "$_tmp" "$_file" || exit 1
    trap - HUP INT TERM 0
    exit 0
  ) || {
    log_error "failed to rewrite managed block in: $_file"
    rm -f "$_tmp" 2>/dev/null || true
    return 1
  }

  return 0
}

register_commit() {
  _path=$1
  if [ -n "${COMMIT_LIST_FILE:-}" ]; then
    if ! printf '%s\n' "$_path" >>"$COMMIT_LIST_FILE" 2>/dev/null; then
      log_warn "failed to append to COMMIT_LIST_FILE: $COMMIT_LIST_FILE"
    fi
  fi
}

###############################################################################
# Main
###############################################################################
log_info "apply morning mode: date=$today mode=$MODE"
log_info "target subnote: $wake_subnote"

wake_block=$(read_wake_block) || {
  _rc=$?
  log_error "failed to read Wake Up block from Daily Plan (rc=$_rc)"
  exit 1
}

filtered=$(printf '%s\n' "$wake_block" | filter_by_mode "$MODE")

# If filtering removes everything, keep a friendly placeholder.
if [ -z "${filtered:-}" ]; then
  filtered='_No entries for this block._'
fi

# Optional: include a short header inside the block (keeps it “official”).
# (This stays within the managed region only.)
stamp="> morning_mode:: ${MODE}  (set by out-of-bed)"
replacement=$(printf '%s\n\n%s\n' "$stamp" "$filtered")

if rewrite_dp_block "$wake_subnote" "$replacement"; then
  register_commit "$wake_subnote"
  log_info "patched Wake Up block successfully"
  exit 0
fi

exit 1
