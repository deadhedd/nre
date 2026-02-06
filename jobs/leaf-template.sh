#!/bin/sh
# Leaf job template (wrapper required)
#
# Responsibilities:
# - Perform one job
# - Produce one primary artifact
# - Declare that artifact via COMMIT_LIST_FILE (if provided)
#
# Non-responsibilities:
# - Logging setup
# - Commit orchestration
# - Wrapper recursion control
#
# Author: deadhedd
# License: MIT

set -eu

###############################################################################
# Logging (leaf responsibility: emit correctly-formatted messages to stderr)
###############################################################################
#
# Contract expectation (example):
#   DEBUG: <message>
#   INFO:  <message>
#   WARN:  <message>
#   ERROR: <message>
#
# Notes:
# - Leaf does not initialize logging; it only emits messages.
# - Wrapper captures leaf stderr and forwards to centralized logging when healthy.
#
log_debug() { printf '%s\n' "DEBUG: $*" >&2; }
log_info()  { printf '%s\n' "INFO: $*"  >&2; }
log_warn()  { printf '%s\n' "WARN: $*"  >&2; }
log_error() { printf '%s\n' "ERROR: $*" >&2; }

###############################################################################
# Resolve paths
###############################################################################

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)
repo_root=$(CDPATH= cd "$script_dir/.." && pwd)

wrap="$repo_root/engine/wrap.sh"

# Prefer passing an absolute script path to the wrapper for sturdiness.
case "$0" in
  /*) script_path=$0 ;;
  *)  script_path=$script_dir/${0##*/} ;;
esac

###############################################################################
# Self-wrap (minimal, dumb, contract-aligned)
###############################################################################

# engine/wrap.sh owns JOB_WRAP_ACTIVE; leaf does not set it.
if [ "${JOB_WRAP_ACTIVE:-0}" != "1" ]; then
  if [ ! -x "$wrap" ]; then
    log_error "leaf wrap: wrapper not found/executable: $wrap"
    exit 127
  fi
  log_info "leaf wrap: exec wrapper: $wrap"
  exec "$wrap" "$script_path" ${1+"$@"}
else
  # Wrapped execution path; informational only.
  log_debug "leaf wrap: wrapper active; executing leaf"
fi

###############################################################################
# Engine libs (wrapped path only)
###############################################################################

datetime_lib=$repo_root/engine/datetime.sh
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
# Argument parsing (example - customize per job)
###############################################################################

usage() {
  cat <<'EOF_USAGE'
Usage: leaf-template.sh [--output <path>] [--dry-run]

Options:
  --output <path>   Output file path.
  --dry-run         Emit content to stdout instead of writing a file.
  --help            Show this message.
EOF_USAGE
}

output_path=""
dry_run=0

while [ $# -gt 0 ]; do
  case "$1" in
    --output)
      [ $# -ge 2 ] || { printf 'ERROR: missing value for --output\n' >&2; usage >&2; exit 2; }
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
      printf 'ERROR: unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

###############################################################################
# Job logic
###############################################################################

# Logging examples (copy/paste patterns):
# log_debug "starting: foo=$foo bar=$bar"
# log_info  "doing thing: step=1"
# log_warn  "non-fatal issue: falling back to default"
# log_error "fatal: missing required input"
#
# NOTE: prefer *one line per message*; if you must emit multiline, it will be
# captured, but boundary emission may summarize it depending on wrapper state.

# Contract:
# - absolute path
# - single, obvious artifact
# - stored in `primary_result`
# Artifact root:
# - Must be provided by wrapper.
if [ -z "${VAULT_ROOT:-}" ]; then
  log_error "VAULT_ROOT not set (wrapper required)"
  exit 127
fi
artifact_root=$VAULT_ROOT

if [ -z "$output_path" ]; then
  ts_local=$(dt_now_local_compact 2>/dev/null || printf '%s' "")
  if [ -z "$ts_local" ]; then
    log_error "datetime unavailable: dt_now_local_compact failed (refusing unsafe filename)"
    exit 127
  fi
  primary_result="$artifact_root/example-${ts_local}.md"
else
  # Contract: --output must be an absolute path.
  case "$output_path" in
    /*)
      primary_result="$output_path"
      ;;
    *)
      log_error "--output must be an absolute path: $output_path"
      exit 2
      ;;
  esac
fi

generate_content() {
  cat <<EOF_CONTENT
Example leaf output

Generated at (local): $(dt_now_local_iso 2>/dev/null || printf '%s' "<unknown>")
Job: ${JOB_NAME:-<unset>}
EOF_CONTENT
}

if [ "$dry_run" -eq 1 ]; then
  generate_content
  exit 0
fi

# Avoid an extra process (dirname) by using shell pattern removal.
primary_parent=${primary_result%/*}
mkdir -p "$primary_parent"
generate_content >"$primary_result"

###############################################################################
# Commit registration (contractual)
###############################################################################

# Leaf declares what it produced; wrapper decides whether/how to commit.
if [ -n "${COMMIT_LIST_FILE:-}" ]; then
  printf '%s\n' "$primary_result" >>"$COMMIT_LIST_FILE" 2>/dev/null || :
fi

###############################################################################
# Diagnostics
###############################################################################

log_info "Produced artifact: $primary_result"

exit 0
