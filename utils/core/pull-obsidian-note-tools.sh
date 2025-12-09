#!/bin/sh
# utils/core/pull-obsidian-note-tools.sh — Nightly update of obsidian-note-tools
# Author: deadhedd
# License: MIT
set -eu
PATH="/usr/local/bin:/usr/bin:/bin:${PATH:-}"

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd -P)
JOB_WRAP="$REPO_ROOT/utils/core/job-wrap.sh"
SCRIPT_PATH="$SCRIPT_DIR/$(basename -- "$0")"


if [ "${JOB_WRAP_ACTIVE:-0}" != "1" ] && [ -x "$JOB_WRAP" ]; then
  JOB_WRAP_ACTIVE=1 exec /bin/sh "$JOB_WRAP" "$SCRIPT_PATH" "$@"
fi

HOME_DIR=${HOME:-/home/obsidian}
DEFAULT_REPO_DIR=$HOME_DIR/obsidian-note-tools
FALLBACK_REPO_DIR=$HOME_DIR/automation/obsidian-note-tools

if [ -n "${PULL_REPO_DIR:-}" ]; then
  REPO_DIR=$PULL_REPO_DIR
  REPO_DIR_SOURCE=env
elif [ -d "$DEFAULT_REPO_DIR" ]; then
  REPO_DIR=$DEFAULT_REPO_DIR
  REPO_DIR_SOURCE=default
elif [ -d "$FALLBACK_REPO_DIR" ]; then
  REPO_DIR=$FALLBACK_REPO_DIR
  REPO_DIR_SOURCE=fallback
else
  REPO_DIR=$DEFAULT_REPO_DIR
  REPO_DIR_SOURCE=default-missing
fi

if [ -n "${GIT_BIN:-}" ]; then
  RESOLVED_GIT_BIN=$GIT_BIN
elif command -v git >/dev/null 2>&1; then
  RESOLVED_GIT_BIN=$(command -v git)
else
  RESOLVED_GIT_BIN=/usr/local/bin/git
fi

GIT_BIN=$RESOLVED_GIT_BIN

printf 'INFO %s\n' "repo_dir_source=$REPO_DIR_SOURCE"
printf 'INFO %s\n' "repo_dir=$REPO_DIR"
printf 'INFO %s\n' "git_bin=$GIT_BIN"

if [ ! -d "$REPO_DIR" ]; then
  printf 'ERR  %s\n' "Repo dir not found: $REPO_DIR" >&2
  exit 1
fi

if [ ! -x "$GIT_BIN" ]; then
  printf 'ERR  %s\n' "git binary not executable: $GIT_BIN" >&2
  exit 1
fi

if ! cd "$REPO_DIR"; then
  printf 'ERR  %s\n' "Failed to enter repo dir: $REPO_DIR" >&2
  exit 1
fi

printf 'INFO %s\n' "Running git pull --ff-only"
if ! "$GIT_BIN" pull --ff-only; then
  printf 'ERR  %s\n' "git pull failed" >&2
  exit 1
fi

printf 'INFO %s\n' "git pull completed"
