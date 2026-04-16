#!/bin/sh
# jobs/script-status-report.sh
# Leaf facade for script status report generation.
#
# Responsibilities:
# - self-wrap via engine/wrap.sh (leaf contract)
# - when wrapped, dispatch to helper in standalone mode so cadence/self-row
#   behavior is preserved for direct invocations.
#
# Author: deadhedd
# License: MIT
# shellcheck shell=sh

set -eu

log_debug() { printf '%s\n' "DEBUG: $*" >&2; }
log_info()  { printf '%s\n' "INFO: $*"  >&2; }
log_error() { printf '%s\n' "ERROR: $*" >&2; }

script_dir=$(CDPATH='' cd "$(dirname "$0")" && pwd)
wrap="$script_dir/../engine/wrap.sh"
helper="$script_dir/helpers/script-status-report-helper.sh"

case "$0" in
  /*) script_path=$0 ;;
  *)  script_path=$script_dir/${0##*/} ;;
esac

script_path=$(
  CDPATH='' cd "$(dirname "$script_path")" &&
  d=$(pwd) &&
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

if [ ! -x "$helper" ]; then
  log_error "helper not found/executable: $helper"
  exit 127
fi

SCRIPT_STATUS_REPORT_STANDALONE=1 exec "$helper" "$@"
