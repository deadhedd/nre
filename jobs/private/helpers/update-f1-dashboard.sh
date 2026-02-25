#!/bin/sh
# update-f1-dashboard.sh — ensure and refresh the Formula 1 dashboard
#
# Helper script (NOT wrapped). Intended to be called by a wrapped job.
# Stdout: unused (quiet). Stderr: diagnostics only (INFO/WARN/ERROR).
#
# Author: deadhedd
# License: MIT
# shellcheck shell=sh

set -eu

###############################################################################
# Logging (emit correctly-formatted messages to stderr)
###############################################################################

log_debug() { printf '%s\n' "DEBUG: $*" >&2; }
log_info()  { printf '%s\n' "INFO: $*"  >&2; }
log_warn()  { printf '%s\n' "WARN: $*"  >&2; }
log_error() { printf '%s\n' "ERROR: $*" >&2; }

###############################################################################
# Resolve paths (no self-wrap)
###############################################################################

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd -P)

# Cron-safe PATH
PATH="/usr/local/bin:/usr/bin:/bin:${PATH:-}"

###############################################################################
# CLI parsing
###############################################################################

usage() {
  cat <<'EOF_USAGE'
Usage: update-f1-dashboard.sh --dashboard-path <path> [--content-script <path>] [--dry-run]

Options:
  --dashboard-path  Target Markdown file for the Formula 1 dashboard (required).
  --content-script  Script that produces dashboard content; defaults to f1-schedule-and-standings.sh.
  --dry-run         Skip writing to disk; log intended actions.
  --help            Show this message.
EOF_USAGE
}

dashboard_path=""
dry_run=0
content_script="$script_dir/f1-schedule-and-standings.sh"

while [ $# -gt 0 ]; do
  case "$1" in
    --dashboard-path)
      dashboard_path=${2:-}
      shift 2
      ;;
    --content-script)
      content_script=${2:-}
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
      log_error "Unknown option: $1"
      usage >&2
      exit 2
      ;;
  esac
done

if [ -z "$dashboard_path" ]; then
  log_error "--dashboard-path is required"
  usage >&2
  exit 2
fi

###############################################################################
# Helpers
###############################################################################

ensure_dir() {
  dir=$1
  if [ "$dry_run" -eq 1 ]; then
    log_info "Dry run: would ensure directory exists: $dir"
    return 0
  fi
  mkdir -p "$dir"
}

write_output() {
  dest=$1
  if [ "$dry_run" -eq 1 ]; then
    log_info "Dry run: would write dashboard content to $dest"
    cat >/dev/null
    return 0
  fi
  cat >"$dest"
}

###############################################################################
# Main
###############################################################################

log_info "Formula 1 dashboard note: $dashboard_path"

dashboard_dir=$(dirname -- "$dashboard_path")
ensure_dir "$dashboard_dir"

if [ ! -f "$dashboard_path" ]; then
  if [ "$dry_run" -eq 1 ]; then
    log_warn "Dry run: dashboard missing; would create placeholder at $dashboard_path"
  else
    log_warn "Dashboard missing; creating placeholder at $dashboard_path"
    cat >"$dashboard_path" <<'EOF_F1_DASHBOARD'
# 🏎️ Formula 1
_This dashboard was created automatically. Populate it with race data or widgets for embeds._
EOF_F1_DASHBOARD
  fi
else
  log_info "Dashboard present: $dashboard_path"
fi

if [ "$dry_run" -eq 1 ]; then
  log_info "Dry run: skipping dashboard refresh"
  exit 0
fi

if [ ! -r "$content_script" ]; then
  log_warn "Content script not found: $content_script"
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  log_warn "Skipping refresh; jq is unavailable"
  exit 0
fi

log_info "Refreshing Formula 1 dashboard content"
# NOTE: do NOT redirect stderr; preserve producer diagnostics.
if output=$(sh "$content_script"); then
  printf '%s\n' "$output" | write_output "$dashboard_path"
  log_info "Dashboard updated: $dashboard_path"
else
  status=$?
  log_warn "Dashboard refresh failed with exit code $status; leaving existing content"
fi
