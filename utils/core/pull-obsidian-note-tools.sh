#!/bin/sh
# utils/core/pull-obsidian-note-tools.sh — Nightly update of obsidian-note-tools
# Author: deadhedd
# License: MIT
set -eu
PATH="/usr/local/bin:/usr/bin:/bin:${PATH:-}"

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/log.sh"

LOG_JOB_NAME=${LOG_JOB_NAME:-pull-obsidian-note-tools}
log_init "$LOG_JOB_NAME"

REPO_DIR=${PULL_REPO_DIR:-${HOME:-/home/obsidian}/automation/obsidian-note-tools}

if [ -n "${GIT_BIN:-}" ]; then
  RESOLVED_GIT_BIN=$GIT_BIN
elif command -v git >/dev/null 2>&1; then
  RESOLVED_GIT_BIN=$(command -v git)
else
  RESOLVED_GIT_BIN=/usr/local/bin/git
fi

GIT_BIN=$RESOLVED_GIT_BIN

log_info "repo_dir=$REPO_DIR"
log_info "git_bin=$GIT_BIN"

if [ ! -d "$REPO_DIR" ]; then
  log_err "Repo dir not found: $REPO_DIR"
  exit 1
fi

if [ ! -x "$GIT_BIN" ]; then
  log_err "git binary not executable: $GIT_BIN"
  exit 1
fi

if ! cd "$REPO_DIR"; then
  log_err "Failed to enter repo dir: $REPO_DIR"
  exit 1
fi

log_info "Running git pull --ff-only"
if ! "$GIT_BIN" pull --ff-only; then
  log_err "git pull failed"
  exit 1
fi

log_info "git pull completed"
