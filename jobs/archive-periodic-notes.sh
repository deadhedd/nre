#!/bin/sh
# jobs/archive-periodic-notes.sh
# Archive old periodic notes based on filename-derived periods.
#
# Leaf job (wrapper required)
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
# Resolve paths
###############################################################################

# shellcheck disable=SC1007
script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)
wrap="$script_dir/../engine/wrap.sh"

case "$0" in
  /*) script_path=$0 ;;
  *)  script_path=$script_dir/${0##*/} ;;
esac

script_path=$(
  # shellcheck disable=SC1007
  CDPATH= cd "$(dirname "$script_path")" && \
  d=$(pwd) && \
  printf '%s/%s\n' "$d" "${script_path##*/}"
) || {
  log_error "failed to canonicalize script path: $script_path"
  exit 127
}

###############################################################################
# Self-wrap (minimal, dumb, contract-aligned)
###############################################################################

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
# Environment normalization (contract-required)
###############################################################################

PATH="/usr/local/bin:/usr/bin:/bin:${PATH:-}"
export PATH

###############################################################################
# Cadence declaration (contract-required)
###############################################################################

JOB_CADENCE=${JOB_CADENCE:-monthly}
log_info "cadence=$JOB_CADENCE"

###############################################################################
# Engine libs (wrapped path only)
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
lib_dir=$repo_root/engine/lib
datetime_lib=$lib_dir/datetime.sh
periods_lib=$lib_dir/periods.sh

if [ ! -r "$datetime_lib" ]; then
  log_error "datetime lib not found/readable: $datetime_lib"
  exit 127
fi
# shellcheck source=/dev/null
. "$datetime_lib" || {
  log_error "failed to source datetime lib: $datetime_lib"
  exit 127
}

if [ ! -r "$periods_lib" ]; then
  log_error "periods lib not found/readable: $periods_lib"
  exit 127
fi
# shellcheck source=/dev/null
. "$periods_lib" || {
  log_error "failed to source periods lib: $periods_lib"
  exit 127
}

tmpfile() {
  mktemp "${TMPDIR:-/tmp}/archive-periodic-notes.XXXXXX" 2>/dev/null || \
    printf '%s' "${TMPDIR:-/tmp}/archive-periodic-notes.$$"
}

###############################################################################
# Args
###############################################################################

usage() {
  cat <<'EOF_USAGE'
Usage: archive-periodic-notes.sh [--apply] [--dry-run|-n] [--force]

Options:
  --apply      Perform moves and write the report artifact.
  --dry-run    Do not move files; emit report to stdout. (default)
  -n           Alias for --dry-run.
  --force      Allow overwrite if destination already exists.
  --help       Show this message.

Retention env vars:
  ARCHIVE_KEEP_DAILY_DAYS       default: 400
  ARCHIVE_KEEP_WEEKLY_WEEKS     default: 104
  ARCHIVE_KEEP_MONTHLY_MONTHS   default: 24
  ARCHIVE_KEEP_QUARTERLY_QTRS   default: 12
  ARCHIVE_KEEP_YEARLY_YEARS     default: 5
EOF_USAGE
}

# Safer default: preview only unless explicitly told to apply changes.
dry_run=1
force=0

while [ $# -gt 0 ]; do
  case "$1" in
    --apply)
      dry_run=0
      shift
      ;;
    --dry-run|-n)
      dry_run=1
      shift
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
      log_error "unknown option: $1"
      usage >&2
      exit 2
      ;;
  esac
done

###############################################################################
# Config
###############################################################################

ARCHIVE_KEEP_DAILY_DAYS=${ARCHIVE_KEEP_DAILY_DAYS:-400}
ARCHIVE_KEEP_WEEKLY_WEEKS=${ARCHIVE_KEEP_WEEKLY_WEEKS:-104}
ARCHIVE_KEEP_MONTHLY_MONTHS=${ARCHIVE_KEEP_MONTHLY_MONTHS:-24}
ARCHIVE_KEEP_QUARTERLY_QTRS=${ARCHIVE_KEEP_QUARTERLY_QTRS:-12}
ARCHIVE_KEEP_YEARLY_YEARS=${ARCHIVE_KEEP_YEARLY_YEARS:-5}

for n in \
  "$ARCHIVE_KEEP_DAILY_DAYS" \
  "$ARCHIVE_KEEP_WEEKLY_WEEKS" \
  "$ARCHIVE_KEEP_MONTHLY_MONTHS" \
  "$ARCHIVE_KEEP_QUARTERLY_QTRS" \
  "$ARCHIVE_KEEP_YEARLY_YEARS"
do
  case "$n" in
    ''|*[!0-9]*)
      log_error "retention values must be non-negative integers"
      exit 2
      ;;
  esac
done

###############################################################################
# Paths
###############################################################################

if [ -z "${VAULT_ROOT:-}" ]; then
  log_error "VAULT_ROOT not set (wrapper required)"
  exit 127
fi

periodic_root="${VAULT_ROOT%/}/${PERIODIC_NOTES_DIR:-10 - Periodic Notes}"
archive_root="${VAULT_ROOT%/}/${PERIODIC_ARCHIVE_DIR:-10 - Periodic Notes/Archive}"
SERVER_LOGS_DIR=${SERVER_LOGS_DIR:-"00 - System/Server Logs"}
report_path="${VAULT_ROOT%/}/${SERVER_LOGS_DIR}/Periodic Note Archive Report.md"

daily_dir="$periodic_root/Daily Notes"
subnotes_dir="${VAULT_ROOT%/}/${SUBNOTES_DIR:-${PERIODIC_NOTES_DIR:-10 - Periodic Notes}/Daily Notes/Subnotes}"
weekly_dir="$periodic_root/Weekly Notes"
monthly_dir="$periodic_root/Monthly Notes"
quarterly_dir="$periodic_root/Quarterly Notes"
yearly_dir="$periodic_root/Yearly Notes"

today=$(dt_today_local) || {
  log_error "failed to determine today"
  exit 1
}

daily_cutoff=$(dt_date_shift_days "$today" "-$ARCHIVE_KEEP_DAILY_DAYS") || exit 1

# shellcheck disable=SC2046
set -- $(dt_date_parts "$today") || {
  log_error "failed to get date parts for today"
  exit 1
}
today_y=$1
today_m=$2

to_decimal() {
  _n=$1
  # shellcheck disable=SC2003
  # Using expr intentionally for POSIX-safe decimal coercion (avoids 10# syntax).
  # Leading zeros must be handled safely across /bin/sh implementations.
  expr "$_n" + 0
}

today_y_num=$(to_decimal "$today_y") || {
  log_error "failed to coerce year to decimal: $today_y"
  exit 1
}
today_m_num=$(to_decimal "$today_m") || {
  log_error "failed to coerce month to decimal: $today_m"
  exit 1
}

today_q=$(( (today_m_num + 2) / 3 ))

log_info "periodic_root=$periodic_root"
log_info "archive_root=$archive_root"
log_info "today=$today"
log_info "daily_cutoff=$daily_cutoff"
if [ "$dry_run" -eq 1 ]; then
  log_info "mode=dry-run"
else
  log_info "mode=apply"
fi
log_info "dry_run=$dry_run"
log_info "force=$force"

###############################################################################
# Helpers
###############################################################################

write_atomic_file() {
  _dest=$1
  _dir=${_dest%/*}
  _tmp="${_dir}/${_dest##*/}.tmp.$$"

  if ! mkdir -p "$_dir"; then
    log_error "failed to create artifact directory: $_dir"
    exit 1
  fi

  (
    trap 'rm -f "$_tmp"' HUP INT TERM 0
    if ! cat >"$_tmp"; then
      exit 1
    fi
    if ! mv "$_tmp" "$_dest"; then
      exit 1
    fi
    trap - HUP INT TERM 0
    exit 0
  ) || {
    log_error "failed atomic write: $_dest"
    rm -f "$_tmp" 2>/dev/null || true
    exit 1
  }
}

safe_year() {
  case "${1:-}" in
    [0-9][0-9][0-9][0-9]) printf '%s\n' "$1" ;;
    *) return 1 ;;
  esac
}

month_index() {
  _ym=$1
  _y=${_ym%-*}
  _m=${_ym#*-}
  _y_num=$(to_decimal "$_y") || return 1
  _m_num=$(to_decimal "$_m") || return 1
  printf '%s\n' $(( (_y_num * 12) + _m_num ))
}

quarter_index() {
  _yq=$1
  _y=${_yq%-Q*}
  _q=${_yq#*-Q}
  _y_num=$(to_decimal "$_y") || return 1
  _q_num=$(to_decimal "$_q") || return 1
  printf '%s\n' $(( (_y_num * 4) + _q_num ))
}

should_archive_monthly() {
  _note=$1   # YYYY-MM
  _note_idx=$(month_index "$_note") || return 1
  _today_idx=$(( (today_y_num * 12) + today_m_num ))
  _diff=$((_today_idx - _note_idx))
  [ "$_diff" -gt "$ARCHIVE_KEEP_MONTHLY_MONTHS" ]
}

should_archive_quarterly() {
  _note=$1   # YYYY-QN
  _note_idx=$(quarter_index "$_note") || return 1
  _today_idx=$(( (today_y_num * 4) + today_q ))
  _diff=$((_today_idx - _note_idx))
  [ "$_diff" -gt "$ARCHIVE_KEEP_QUARTERLY_QTRS" ]
}

should_archive_yearly() {
  _year=$1
  _year_num=$(to_decimal "$_year") || return 1
  _diff=$((today_y_num - _year_num))
  [ "$_diff" -gt "$ARCHIVE_KEEP_YEARLY_YEARS" ]
}

ymd_before() {
  _left=$1
  _right=$2
  awk -v left="$_left" -v right="$_right" 'BEGIN {
    exit !(left < right)
  }'
}

move_note() {
  _src=$1
  _type=$2
  _year=$3

  _dest_dir="$archive_root/$_year/$_type"
  _dest="$_dest_dir/$(basename "$_src")"

  if [ -e "$_dest" ] && [ "$force" -ne 1 ]; then
    log_error "destination exists (use --force): $_dest"
    exit 1
  fi

  log_info "archive: $_src -> $_dest"

  if [ "$dry_run" -eq 0 ]; then
    mkdir -p "$_dest_dir" || {
      log_error "failed to create archive dir: $_dest_dir"
      exit 1
    }
    mv "$_src" "$_dest" || {
      log_error "failed to move note: $_src"
      exit 1
    }
  fi

  printf '%s\n' "$_dest"
}

###############################################################################
# Work files
###############################################################################

moved_file=$(tmpfile)
removed_file=$(tmpfile)
cleanup_tmp() {
  rm -f "$moved_file" "$removed_file"
}
trap cleanup_tmp HUP INT TERM 0
: >"$moved_file"
: >"$removed_file"

###############################################################################
# Daily notes: YYYY-MM-DD.md
###############################################################################

if [ -d "$daily_dir" ]; then
  find "$daily_dir" -maxdepth 1 -type f -name '????-??-??.md' | sort | \
  while IFS= read -r src; do
    base=$(basename "$src")
    stem=${base%.md}

    if ! dt_check_ymd "$stem" >/dev/null 2>&1; then
      log_warn "skipping invalid daily note filename: $src"
      continue
    fi

    if ymd_before "$stem" "$daily_cutoff"; then
      year=${stem%%-*}
      printf '%s\n' "$src" >>"$removed_file"
      move_note "$src" "Daily Notes" "$year" >>"$moved_file"
    fi
  done
fi

###############################################################################
# Daily note subnotes: YYYY-MM-DD*.md
###############################################################################

if [ -d "$subnotes_dir" ]; then
  find "$subnotes_dir" -maxdepth 1 -type f -name '????-??-??*.md' | sort | \
  while IFS= read -r src; do
    base=$(basename "$src")
    stem=${base%.md}
    note_date=$(printf '%.10s\n' "$stem")

    if ! dt_check_ymd "$note_date" >/dev/null 2>&1; then
      log_warn "skipping invalid daily subnote filename: $src"
      continue
    fi

    if ymd_before "$note_date" "$daily_cutoff"; then
      year=${note_date%%-*}
      printf '%s\n' "$src" >>"$removed_file"
      move_note "$src" "Daily Notes/Subnotes" "$year" >>"$moved_file"
    fi
  done
fi

###############################################################################
# Weekly baseline: current ISO week as a stable comparable index
###############################################################################

current_week_tag=$(pr_week_tag "$today" 2>/dev/null || true)
case "$current_week_tag" in
  [0-9][0-9][0-9][0-9]-W[0-9][0-9])
    current_year=${current_week_tag%-W*}
    if ! current_year_num=$(to_decimal "$current_year"); then
      log_warn "could not coerce current ISO week year to decimal: $current_year"
      current_week_idx=
      current_week=
    else
      current_week=${current_week_tag#*-W}
      if ! current_week_num=$(to_decimal "$current_week"); then
        log_warn "could not coerce current ISO week number to decimal: $current_week"
        current_week_idx=
      else
        current_week_idx=$(( (current_year_num * 53) + current_week_num ))
      fi
    fi
    ;;
  *)
    current_week_idx=
    ;;
esac

###############################################################################
# Weekly notes: YYYY-WNN.md
###############################################################################

if [ -d "$weekly_dir" ]; then
  find "$weekly_dir" -maxdepth 1 -type f -name '????-W??.md' | sort | \
  while IFS= read -r src; do
    base=$(basename "$src")
    stem=${base%.md}

    case "$stem" in
      [0-9][0-9][0-9][0-9]-W[0-9][0-9]) : ;;
      *)
        log_warn "skipping invalid weekly note filename: $src"
        continue
        ;;
    esac

    year=${stem%%-*}
    week=${stem#*-W}

    case "$week" in
      00|5[4-9]|[6-9][0-9])
        log_warn "skipping out-of-range weekly note filename: $src"
        continue
        ;;
    esac

    if [ -z "$current_week_idx" ]; then
      log_warn "could not derive current ISO week; weekly archiving skipped for: $src"
      continue
    fi

    year_num=$(to_decimal "$year") || {
      log_warn "skipping weekly note with non-decimal year: $src"
      continue
    }
    week_num=$(to_decimal "$week") || {
      log_warn "skipping weekly note with non-decimal week: $src"
      continue
    }
    note_week_idx=$(( (year_num * 53) + week_num ))
    diff=$(( current_week_idx - note_week_idx ))

    if [ "$diff" -le "$ARCHIVE_KEEP_WEEKLY_WEEKS" ]; then
      continue
    fi

    printf '%s\n' "$src" >>"$removed_file"
    move_note "$src" "Weekly Notes" "$year" >>"$moved_file"
  done
fi

###############################################################################
# Monthly notes: YYYY-MM.md
###############################################################################

if [ -d "$monthly_dir" ]; then
  find "$monthly_dir" -maxdepth 1 -type f -name '????-??.md' | sort | \
  while IFS= read -r src; do
    base=$(basename "$src")
    stem=${base%.md}

    case "$stem" in
      [0-9][0-9][0-9][0-9]-[0-9][0-9]) : ;;
      *)
        log_warn "skipping invalid monthly note filename: $src"
        continue
        ;;
    esac

    year=${stem%-*}
    month=${stem#*-}

    case "$month" in
      01|02|03|04|05|06|07|08|09|10|11|12) : ;;
      *)
        log_warn "skipping invalid monthly note filename: $src"
        continue
        ;;
    esac

    if should_archive_monthly "$stem"; then
      printf '%s\n' "$src" >>"$removed_file"
      move_note "$src" "Monthly Notes" "$year" >>"$moved_file"
    fi
  done
fi

###############################################################################
# Quarterly notes: YYYY-QN.md
###############################################################################

if [ -d "$quarterly_dir" ]; then
  find "$quarterly_dir" -maxdepth 1 -type f -name '????-Q?.md' | sort | \
  while IFS= read -r src; do
    base=$(basename "$src")
    stem=${base%.md}

    case "$stem" in
      [0-9][0-9][0-9][0-9]-Q[1-4]) : ;;
      *)
        log_warn "skipping invalid quarterly note filename: $src"
        continue
        ;;
    esac

    year=${stem%-Q*}
    year=${year%-}

    if should_archive_quarterly "$stem"; then
      printf '%s\n' "$src" >>"$removed_file"
      move_note "$src" "Quarterly Notes" "$year" >>"$moved_file"
    fi
  done
fi

###############################################################################
# Yearly notes: YYYY.md
###############################################################################

if [ -d "$yearly_dir" ]; then
  find "$yearly_dir" -maxdepth 1 -type f -name '????.md' | sort | \
  while IFS= read -r src; do
    base=$(basename "$src")
    stem=${base%.md}

    if ! safe_year "$stem" >/dev/null 2>&1; then
      log_warn "skipping invalid yearly note filename: $src"
      continue
    fi

    if should_archive_yearly "$stem"; then
      printf '%s\n' "$src" >>"$removed_file"
      move_note "$src" "Yearly Notes" "$stem" >>"$moved_file"
    fi
  done
fi

###############################################################################
# Report
###############################################################################

generate_report() {
  moved_count=$(wc -l <"$moved_file" | tr -d ' ')
  printf '# Periodic Note Archive Report\n\n'
  # shellcheck disable=SC2016
  # Format strings are intentionally single-quoted.
  printf -- '- Run date: `%s`\n' "$today"
  # shellcheck disable=SC2016
  printf -- '- Dry run: `%s`\n' "$dry_run"
  # shellcheck disable=SC2016
  printf -- '- Periodic root: `%s`\n' "$periodic_root"
  # shellcheck disable=SC2016
  printf -- '- Archive root: `%s`\n' "$archive_root"
  # shellcheck disable=SC2016
  printf -- '- Daily keep days: `%s`\n' "$ARCHIVE_KEEP_DAILY_DAYS"
  # shellcheck disable=SC2016
  printf -- '- Weekly keep weeks: `%s`\n' "$ARCHIVE_KEEP_WEEKLY_WEEKS"
  # shellcheck disable=SC2016
  printf -- '- Monthly keep months: `%s`\n' "$ARCHIVE_KEEP_MONTHLY_MONTHS"
  # shellcheck disable=SC2016
  printf -- '- Quarterly keep quarters: `%s`\n' "$ARCHIVE_KEEP_QUARTERLY_QTRS"
  # shellcheck disable=SC2016
  printf -- '- Yearly keep years: `%s`\n' "$ARCHIVE_KEEP_YEARLY_YEARS"
  # shellcheck disable=SC2016
  printf -- '- Archived count: `%s`\n\n' "$moved_count"

  if [ "$moved_count" -gt 0 ]; then
    # shellcheck disable=SC2016
    printf '## Archived Notes\n\n'
    while IFS= read -r path; do
      [ -n "$path" ] || continue
      # shellcheck disable=SC2016
      printf -- '- `%s`\n' "$path"
    done <"$moved_file"
  else
    printf 'No notes were archived.\n'
  fi
}

if [ "$dry_run" -eq 1 ]; then
  generate_report
else
  log_info "writing report artifact: $report_path"

  write_atomic_file "$report_path" <<EOF
$(generate_report)
EOF
fi

###############################################################################
# Commit registration
###############################################################################

if [ "$dry_run" -eq 0 ] && [ -n "${COMMIT_LIST_FILE:-}" ]; then
  printf '%s\n' "$report_path" >>"$COMMIT_LIST_FILE"

  while IFS= read -r path; do
    [ -n "$path" ] || continue
    printf '%s\n' "$path" >>"$COMMIT_LIST_FILE"
  done <"$moved_file"

  while IFS= read -r path; do
    [ -n "$path" ] || continue
    printf '%s\n' "$path" >>"$COMMIT_LIST_FILE"
  done <"$removed_file"
fi

if [ "$dry_run" -eq 1 ]; then
  log_info "dry run complete (no files moved); re-run with --apply to perform archive"
fi

log_info "archive-periodic-notes complete"
trap - HUP INT TERM 0
cleanup_tmp
exit 0
