#!/bin/sh
# jobs/pull-nre-private.sh — Nightly update of nre-private (git pull --ff-only)
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

script_dir=$(CDPATH='' cd "$(dirname "$0")" && pwd)
wrap="$script_dir/../engine/wrap.sh"

case "$0" in
  /*) script_path=$0 ;;
  *)  script_path=$script_dir/${0##*/} ;;
esac

script_path=$(
  CDPATH='' cd "$(dirname "$script_path")" && \
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
  COMMIT_MODE=${COMMIT_MODE:-off}
  export COMMIT_MODE
  exec "$wrap" "$script_path" ${1+"$@"}
else
  log_debug "leaf wrap: wrapper active; executing leaf"
fi

###############################################################################
# Cadence declaration (contract-required)
###############################################################################

JOB_CADENCE=${JOB_CADENCE:-daily}
log_info "cadence=$JOB_CADENCE"

###############################################################################
# Requirements
###############################################################################

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log_error "missing required command: $1"
    exit 127
  fi
}

require_cmd git

###############################################################################
# Resolve repo dir + git bin
###############################################################################

home_dir=${HOME:-/home/obsidian}
default_repo_dir=$home_dir/nre-private

if [ -n "${PULL_REPO_DIR:-}" ]; then
  repo_dir=$PULL_REPO_DIR
  repo_dir_source='env'
elif [ -d "$default_repo_dir" ]; then
  repo_dir=$default_repo_dir
  repo_dir_source=default
else
  repo_dir=$default_repo_dir
  repo_dir_source=default-missing
fi

if [ -n "${GIT_BIN:-}" ]; then
  git_bin=$GIT_BIN
  git_bin_source='env'
else
  git_bin=$(command -v git)
  git_bin_source=path
fi

log_info "repo_dir_source=$repo_dir_source"
log_info "repo_dir=$repo_dir"
log_info "git_bin_source=$git_bin_source"
log_info "git_bin=$git_bin"

if [ ! -d "$repo_dir" ]; then
  log_error "repo dir not found: $repo_dir"
  exit 1
fi

if [ ! -x "$git_bin" ]; then
  log_error "git binary not executable: $git_bin"
  exit 1
fi

###############################################################################
# Branch selection
###############################################################################

pull_branch=${PULL_BRANCH:-master}

###############################################################################
# Pull
###############################################################################

if ! cd "$repo_dir"; then
  log_error "failed to enter repo dir: $repo_dir"
  exit 1
fi

current_branch=$("$git_bin" rev-parse --abbrev-ref HEAD 2>/dev/null) || {
  log_error "failed to determine current branch"
  exit 1
}

log_info "current_branch=$current_branch"
log_info "target_branch=$pull_branch"

if [ "$current_branch" != "$pull_branch" ]; then
  log_info "running: git checkout $pull_branch"

  git_output=$("$git_bin" checkout "$pull_branch" 2>&1) || git_rc=$?
  git_rc=${git_rc:-0}

  printf '%s\n' "$git_output" | while IFS= read -r line; do
    [ -n "$line" ] && log_info "git: $line"
  done

  if [ "$git_rc" -ne 0 ]; then
    log_error "git checkout failed: rc=$git_rc"
    exit 1
  fi
else
  log_info "already on target branch: $pull_branch"
fi

log_info "running: git pull --ff-only origin $pull_branch"

git_output=$("$git_bin" pull --ff-only origin "$pull_branch" 2>&1) || git_rc=$?
git_rc=${git_rc:-0}

printf '%s\n' "$git_output" | while IFS= read -r line; do
  [ -n "$line" ] && log_info "git: $line"
done

if [ "$git_rc" -ne 0 ]; then
  log_error "git pull failed: rc=$git_rc"
  exit 1
fi

log_info "git pull completed for branch: $pull_branch"
exit 0
