#!/bin/sh
# jobs/private/generate-yearly-note.sh
# Leaf job (wrapper required)
#
# Version: 1.0
# Status: contract-aligned (leaf template)
#
# Generate a yearly note markdown file inspired by the legacy Node version.
# Produces one artifact: <VAULT_ROOT>/Periodic Notes/Yearly Notes/<YYYY>.md
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

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)

# C1 bootstrap rule: wrapper location is assumed stable *relative to this file*
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
# Cadence declaration (contract-required)
###############################################################################

JOB_CADENCE=${JOB_CADENCE:-yearly}
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
periods_lib=$lib_dir/periods.sh
datetime_lib=$lib_dir/datetime.sh

if [ ! -r "$periods_lib" ]; then
  log_error "periods lib not found/readable: $periods_lib"
  exit 127
fi
# shellcheck source=/dev/null
. "$periods_lib" || {
  log_error "failed to source periods lib: $periods_lib"
  exit 127
}

if [ ! -r "$datetime_lib" ]; then
  log_error "datetime lib not found/readable: $datetime_lib"
  exit 127
fi
# shellcheck source=/dev/null
. "$datetime_lib" || {
  log_error "failed to source datetime lib: $datetime_lib"
  exit 127
}

###############################################################################
# Argument parsing (template baseline)
###############################################################################

usage() {
  cat <<'EOF_USAGE'
Usage: generate-yearly-note.sh [--output <path>] [--dry-run] [--force]

Options:
  --output <path>   Output file path (absolute). Overrides default vault location.
  --dry-run         Emit note content to stdout instead of writing a file.
  --force           Overwrite existing files if present.
  --help            Show this message.
EOF_USAGE
}

output_path=""
dry_run=0
force=0

while [ $# -gt 0 ]; do
  case "$1" in
    --output)
      [ $# -ge 2 ] || { printf 'ERROR: missing value for --output\n' >&2; usage >&2; exit 2; }
      output_path=$2
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
      printf 'ERROR: unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

###############################################################################
# Job logic
###############################################################################

###############################################################################
# Compute anchor artifact path (result_ref)
###############################################################################

if [ -z "${VAULT_ROOT:-}" ]; then
  log_error "VAULT_ROOT not set (wrapper required)"
  exit 127
fi
artifact_root=$VAULT_ROOT

# Determine target year using datetime helper (local time)
iso=$(dt_now_local_iso 2>/dev/null || printf '%s' "")
if [ -z "$iso" ]; then
  log_error "failed to determine current local date (dt_now_local_iso)"
  exit 127
fi

target_year=${iso%%-*}
case "$target_year" in
  [0-9][0-9][0-9][0-9]) : ;;
  *)
    log_error "unexpected year format from datetime helper: $target_year"
    exit 127
    ;;
esac

prev_year=$((target_year - 1))
next_year=$((target_year + 1))

if [ -z "$output_path" ]; then
  result_ref="$artifact_root/Periodic Notes/Yearly Notes/${target_year}.md"
else
  case "$output_path" in
    */)
      log_error "internal: --output ends with '/': $output_path"
      exit 2
      ;;
  esac
  case "$output_path" in
    /*) result_ref="$output_path" ;;
    *)
      log_error "--output must be an absolute path: $output_path"
      exit 2
      ;;
  esac
fi

case "$result_ref" in
  ""|*/) log_error "internal: invalid result_ref: $result_ref"; exit 127 ;;
esac

###############################################################################
# Overwrite guards
###############################################################################

if [ -f "$result_ref" ] && [ "$force" -ne 1 ]; then
  log_error "refusing to overwrite existing file: $result_ref (use --force)"
  exit 1
fi

generate_content() {
  cat <<EOF_NOTE
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
}

if [ "$dry_run" -eq 1 ]; then
  if [ -n "$output_path" ]; then
    log_warn "--dry-run ignores --output: $output_path"
  fi
  if [ "$force" -eq 1 ]; then
    log_warn "--dry-run ignores --force"
  fi
  generate_content
  exit 0
fi

###############################################################################
# Write anchor artifact (atomic)
###############################################################################

primary_parent=${result_ref%/*}
if ! mkdir -p "$primary_parent"; then
  log_error "failed to create artifact directory: $primary_parent"
  exit 1
fi

tmp="${primary_parent}/${result_ref##*/}.tmp.$$"
cleanup_tmp() {
  [ -n "${tmp:-}" ] && [ -f "$tmp" ] && rm -f "$tmp"
}
trap cleanup_tmp HUP INT TERM 0

if ! generate_content >"$tmp"; then
  log_error "failed to write temp artifact: $tmp"
  exit 1
fi
if ! mv "$tmp" "$result_ref"; then
  log_error "failed to finalize artifact (mv): $tmp -> $result_ref"
  exit 1
fi

tmp=""
trap - HUP INT TERM 0

###############################################################################
# Commit registration (contractual)
###############################################################################

if [ -n "${COMMIT_LIST_FILE:-}" ]; then
  if ! printf '%s\n' "$result_ref" >>"$COMMIT_LIST_FILE" 2>/dev/null; then
    log_warn "failed to append to COMMIT_LIST_FILE: $COMMIT_LIST_FILE"
  fi
fi

###############################################################################
# Diagnostics
###############################################################################

log_info "Produced artifact: $result_ref"

exit 0
