#!/bin/sh
# Leaf job template (wrapper required)
#
# Version: 1.0
# Status: frozen (contract-stable)
#
# ---------------------------------------------------------------------------
# How to use this template
#
# This file is a *reference leaf job*. It is not meant to be executed directly
# in production or modified in-place.
#
# To create a new leaf job:
#   1. Copy this file to a new job-specific path/name.
#   2. Modify ONLY the sections marked "Argument parsing" and "Job logic".
#      - The pre-existing scaffold within those two sections is part of the template contract.
#      - Do NOT remove or rewrite the baseline patterns; extend them to support job-specific logic.
#      - Keep existing options, defaults, variable initialization, and validation unless you are
#        deliberately changing the template itself.
#   3. Preserve the wrapper logic, path resolution, logging helpers,
#      artifact/result declaration, and commit registration exactly as-is.
#
# Design intent:
# - One leaf = one job = one result set.
# - A result set may contain one or many artifacts.
# - Leaf code assumes a healthy wrapper unless explicitly degraded.
# - Leaf emits structured stderr logs; it never initializes logging.
# - Leaf declares outputs; wrapper decides whether/how to commit.
#
# Result declaration rules:
# - All produced artifacts MUST be declared via COMMIT_LIST_FILE (if provided).
# - Leaf scripts producing multiple artifacts:
#   - MUST declare the full result set via COMMIT_LIST_FILE
#   - MUST append one absolute artifact path per line
#   - MUST do so only after each artifact is fully finalized (e.g., after
#     atomic mv)
#
#   Notes:
#   - A separate manifest file is OPTIONAL.
#   - If a manifest is produced, it is treated as a normal artifact and MUST be
#     declared via COMMIT_LIST_FILE like any other output.
#
# This template is contract-stable.
# If it needs to change, the engine or wrapper contract probably does first.
# ---------------------------------------------------------------------------
#
# Responsibilities:
# - Perform one job
# - Produce one result set (one or more artifacts)
# - Declare all produced artifacts via COMMIT_LIST_FILE (if provided)
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
#   INFO: <message>
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

# Canonicalize the final script path to avoid surprises (symlinks/cwd oddities).
# POSIX note: this resolves directory via cd+pwd; basename is preserved.
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

# Rules for this section:
# - Keep the baseline scaffold: usage(), default flags (--output/--dry-run/--help),
#   variable initialization, and the parsing loop structure.
# - Extend by adding job-specific flags, validation, and derived variables.
# - Avoid changing parsing style or removing baseline flags; that is a template change.

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

# Rules for this section:
# - Keep the baseline artifact contract: result_ref computation, absolute-path requirements,
#   atomic write (temp + mv), cleanup trap, and COMMIT_LIST_FILE registration.
# - Extend by adding job-specific artifact(s) or additional logic while preserving the baseline
#   write/declare pattern.
# - Do not bypass atomic write, bypass result declaration, or change wrapper expectations.

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
# - stored in `result_ref`
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
  result_ref="$artifact_root/example-${ts_local}.md"
else
  case "$output_path" in
    */)
      log_error "internal: --output ends with '/': $output_path"
      exit 2
      ;;
  esac
  # Contract: --output must be an absolute path.
  case "$output_path" in
    /*)
      result_ref="$output_path"
      ;;
    *)
      log_error "--output must be an absolute path: $output_path"
      exit 2
      ;;
  esac
fi

if [ -z "$result_ref" ]; then
  log_error "internal: result_ref empty"
  exit 127
fi
case "$result_ref" in
  */) log_error "internal: result_ref ends with '/': $result_ref"; exit 2 ;;
esac

generate_content() {
  cat <<EOF_CONTENT
Example leaf output

Generated at (local): $(dt_now_local_iso 2>/dev/null || printf '%s' "<unknown>")
Job: ${JOB_NAME:-<unset>}
EOF_CONTENT
}

if [ "$dry_run" -eq 1 ]; then
  if [ -n "$output_path" ]; then
    log_warn "--dry-run ignores --output: $output_path"
  fi
  generate_content
  exit 0
fi

# Avoid an extra process (dirname) by using shell pattern removal.
primary_parent=${result_ref%/*}
if ! mkdir -p "$primary_parent"; then
  log_error "failed to create artifact directory: $primary_parent"
  exit 1
fi

# Write atomically and clean up temp file on failure/interruption.
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

# Success: disarm cleanup for this temp path.
tmp=""
trap - HUP INT TERM 0

###############################################################################
# Commit registration (contractual)
###############################################################################

# Leaf declares what it produced; wrapper decides whether/how to commit.
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
