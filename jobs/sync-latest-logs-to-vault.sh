#!/bin/sh
# jobs/sync-latest-logs-to-vault.sh — Copy *-latest.log files into the Obsidian vault
#
# Leaf job (wrapper required).
# Multi-artifact job: copies latest-log snapshots into the vault and writes
# a per-run summary manifest.
#
# Author: deadhedd
# License: MIT

set -eu
PATH="/usr/local/bin:/usr/bin:/bin:${PATH:-}"

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
script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)

wrap="$script_dir/../engine/wrap.sh"

case "$0" in
  /*) script_path=$0 ;;
  *)  script_path=$script_dir/${0##*/} ;;
esac

script_path=$(
  CDPATH= cd "$(dirname "$script_path")" && \
  d=$(pwd) && \
  printf '%s/%s\n' "$d" "${script_path##*/}"
) || {
  log_error "failed to canonicalize script path"
  exit 127
}

###############################################################################
# Self-wrap (contractual)
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
# Engine libs (wrapper-provided REPO_ROOT)
###############################################################################
if [ -z "${REPO_ROOT:-}" ]; then
  log_error "REPO_ROOT not set (wrapper required)"
  exit 127
fi

repo_root=$REPO_ROOT
lib_dir=$repo_root/engine/lib

periods_lib=$lib_dir/periods.sh
datetime_lib=$lib_dir/datetime.sh

[ -r "$periods_lib" ] || { log_error "missing periods lib: $periods_lib"; exit 127; }
# shellcheck source=/dev/null
. "$periods_lib"

[ -r "$datetime_lib" ] || { log_error "missing datetime lib: $datetime_lib"; exit 127; }
# shellcheck source=/dev/null
. "$datetime_lib"

###############################################################################
# Argument parsing
###############################################################################
usage() {
  cat <<'EOF'
Usage: sync-latest-logs-to-vault.sh [--output <path>] [--dry-run]

Options:
  --output <path>   Absolute path for the per-run summary manifest
  --dry-run         Print planned copies and exit
  --help            Show this help
EOF
}

output_path=""
dry_run=0

while [ $# -gt 0 ]; do
  case "$1" in
    --output)
      [ $# -ge 2 ] || { log_error "missing value for --output"; usage >&2; exit 2; }
      output_path=$2
      shift 2
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
      log_error "unknown option: $1"
      usage >&2
      exit 2
      ;;
  esac
done

###############################################################################
# Job configuration
###############################################################################
[ -n "${VAULT_ROOT:-}" ] || { log_error "VAULT_ROOT not set"; exit 127; }

LOG_ROOT=${LOG_ROOT:-/home/obsidian/logs}
VAULT_LOG_DIR=${VAULT_LOG_DIR:-"${VAULT_ROOT%/}/Server Logs/Latest Logs"}

###############################################################################
# Determine anchor artifact (result_ref)
###############################################################################
if [ -n "$output_path" ]; then
  case "$output_path" in
    /*) result_ref=$output_path ;;
    *) log_error "--output must be an absolute path"; exit 2 ;;
  esac
else
  ts=$(dt_now_local_compact)
  result_ref="${VAULT_LOG_DIR%/}/sync-latest-logs-summary-${ts}.txt"
fi

###############################################################################
# Atomic write helper
###############################################################################
write_atomic_file() {
  dest=$1
  dir=${dest%/*}
  tmp="$dir/.tmp.$$"

  mkdir -p "$dir"
  cat >"$tmp"
  mv "$tmp" "$dest"
}

###############################################################################
# Early exit if no logs
###############################################################################
if [ ! -d "$LOG_ROOT" ]; then
  log_warn "Log root not found: $LOG_ROOT"
  write_atomic_file "$result_ref" <<EOF
sync-latest-logs-to-vault
run_at_local=$(dt_now_local_iso)
status=log_root_missing
LOG_ROOT=$LOG_ROOT
VAULT_LOG_DIR=$VAULT_LOG_DIR
EOF

  [ -n "${COMMIT_LIST_FILE:-}" ] && printf '%s\n' "$result_ref" >>"$COMMIT_LIST_FILE" || true
  exit 0
fi

###############################################################################
# Enumerate logs
###############################################################################
found=0
copied=0
failed=0
skipped_missing=0
skipped_unreadable=0

list_file=$(mktemp "${TMPDIR:-/tmp}/sync-latest-logs.XXXXXX")
copied_file=$(mktemp "${TMPDIR:-/tmp}/sync-latest-logs-copied.XXXXXX")
trap 'rm -f "$list_file" "$copied_file"' EXIT INT TERM HUP

find "$LOG_ROOT" -name '*-latest.log' 2>/dev/null >"$list_file" || true

###############################################################################
# Copy loop
###############################################################################
while IFS= read -r link || [ -n "$link" ]; do
  [ -n "$link" ] || continue
  found=$((found + 1))

  if [ ! -e "$link" ]; then
    skipped_missing=$((skipped_missing + 1))
    continue
  fi

  if [ ! -r "$link" ]; then
    skipped_unreadable=$((skipped_unreadable + 1))
    continue
  fi

  rel=${link#${LOG_ROOT%/}/}
  dest="${VAULT_LOG_DIR%/}/$rel"

  if [ "$dry_run" -eq 1 ]; then
    printf '%s -> %s\n' "$link" "$dest"
    continue
  fi

  mkdir -p "${dest%/*}" || { failed=$((failed + 1)); continue; }

  if cp -L "$link" "$dest"; then
    copied=$((copied + 1))
    printf '%s\n' "$dest" >>"$copied_file"
  else
    failed=$((failed + 1))
  fi
done <"$list_file"

[ "$dry_run" -eq 1 ] && exit 0

###############################################################################
# Write manifest (anchor artifact)
###############################################################################
write_atomic_file "$result_ref" <<EOF
sync-latest-logs-to-vault
run_at_local=$(dt_now_local_iso)
LOG_ROOT=$LOG_ROOT
VAULT_LOG_DIR=$VAULT_LOG_DIR

summary_found=$found
summary_copied=$copied
summary_failed=$failed
summary_skipped_missing=$skipped_missing
summary_skipped_unreadable=$skipped_unreadable

copied_files:
$(cat "$copied_file")
EOF

###############################################################################
# Commit registration
###############################################################################
if [ -n "${COMMIT_LIST_FILE:-}" ]; then
  printf '%s\n' "$result_ref" >>"$COMMIT_LIST_FILE" || true
  cat "$copied_file" >>"$COMMIT_LIST_FILE" || true
fi

###############################################################################
# Exit
###############################################################################
log_info "Produced artifact: $result_ref"
log_info "Summary: found=$found copied=$copied failed=$failed skipped_missing=$skipped_missing skipped_unreadable=$skipped_unreadable"

[ "$failed" -eq 0 ] || exit 1
exit 0
