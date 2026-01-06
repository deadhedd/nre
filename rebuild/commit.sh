#!/bin/sh
# utils/core/commit.sh — stage + commit explicit files into a central bare repo (wrapper-managed)
# Author: deadhedd
# License: MIT
# shellcheck shell=sh
#
# Usage:
#   commit.sh <work_tree_root> <message> <file> [file...]
#
# Contract highlights:
# - MUST be invoked from job-wrap (JOB_WRAP_ACTIVE=1)
# - MUST stage ONLY explicitly provided files (no inference, no git add -A)
# - MUST NOT write to stdout (stdout always empty)
# - Exit codes (Appendix C.2):
#     0  commit created successfully
#     3  no changes to commit (non-failure)
#     10 operational failure (git error, invalid input, repo unavailable, misuse)
# - MUST NOT manage branches / pushing
#
# Environment overrides:
# - COMMIT_BARE_REPO  Override bare repo path (default: /home/git/vaults/Main.git)
# - GIT_BIN           Override git executable
# - GIT_USER          System user for git operations (default: git)

set -eu
PATH="/usr/local/bin:/usr/bin:/bin:${PATH:-}"

# ---------- helpers ----------

commit__usage() {
  printf '%s\n' "Usage: $(basename "$0") <work_tree_root> <message> <file> [file...]" >&2
  printf '%s\n' "Environment:" >&2
  printf '%s\n' "  COMMIT_BARE_REPO  Override bare repo path (default: /home/git/vaults/Main.git)" >&2
  printf '%s\n' "  GIT_BIN           Override git executable" >&2
  printf '%s\n' "  GIT_USER          Git system user (default: git)" >&2
}

commit__abs_path() {
  # Convert an input path to an absolute path.
  # Prints the absolute path on stdout (callers MUST capture).
  in=$1
  d=$(dirname -- "$in") || return 1
  b=$(basename -- "$in") || return 1
  abs_d=$(cd "$d" 2>/dev/null && pwd -P) || return 1
  printf '%s/%s\n' "$abs_d" "$b"
}

commit__fail() {
  msg=$1
  printf 'ERR  %s\n' "$msg" >&2
  exit 10
}

commit__warn() {
  printf 'WARN %s\n' "$1" >&2
}

commit__info() {
  printf 'INFO %s\n' "$1" >&2
}

# ---------- wrapper requirement ----------

if [ "${JOB_WRAP_ACTIVE:-0}" != "1" ]; then
  commit__fail "commit.sh must be invoked from job-wrap (JOB_WRAP_ACTIVE=1)"
fi

# ---------- parse args ----------

# Allow leading "--" for symmetry with other tools; no options are supported.
if [ "${1:-}" = "--" ]; then
  shift
fi

case ${1:-} in
  -*) commit__usage; commit__fail "unknown option: $1" ;;
esac

# Need: work_tree_root message file...
if [ $# -lt 3 ]; then
  commit__usage
  commit__fail "missing required arguments"
fi

work_input=$1
shift
message=$1
shift

[ -n "$message" ] || commit__fail "commit message must be non-empty"

# ---------- resolve work tree + repo ----------

work_root=$(cd "$work_input" 2>/dev/null && pwd -P) \
  || commit__fail "invalid work tree root: $work_input"

BARE_REPO_DEFAULT='/home/git/vaults/Main.git'
bare_repo_input=${COMMIT_BARE_REPO:-$BARE_REPO_DEFAULT}
BARE_REPO=$(commit__abs_path "$bare_repo_input") \
  || commit__fail "invalid bare repository path: $bare_repo_input"

[ -d "$BARE_REPO" ] || commit__fail "bare repository not found: $BARE_REPO"

# ---------- git binary selection ----------

if [ -n "${GIT_BIN:-}" ]; then
  GIT_BIN_RESOLVED=$GIT_BIN
elif [ -x /usr/local/bin/git ]; then
  GIT_BIN_RESOLVED=/usr/local/bin/git
else
  GIT_BIN_RESOLVED=git
fi

case $GIT_BIN_RESOLVED in
  */*)
    [ -x "$GIT_BIN_RESOLVED" ] || commit__fail "GIT_BIN is not executable: $GIT_BIN_RESOLVED"
    ;;
  *)
    command -v "$GIT_BIN_RESOLVED" >/dev/null 2>&1 \
      || commit__fail "git not found in PATH (GIT_BIN=$GIT_BIN_RESOLVED)"
    ;;
esac

# ---------- git user / privilege boundary ----------

GIT_USER_RESOLVED=${GIT_USER:-git}

case $GIT_USER_RESOLVED in
  ''|*' '*|*'\t'*)
    commit__fail "invalid GIT_USER value: '$GIT_USER_RESOLVED'"
    ;;
esac

# Hardened model: this helper MUST be invoked as a non-git user (e.g., obsidian)
# and MUST cross the privilege boundary via doas for all git operations.
current_user=$(id -un 2>/dev/null || printf '')
if [ -z "$current_user" ]; then
  commit__fail "cannot determine current user (id -un failed)"
fi

if [ "$current_user" = "$GIT_USER_RESOLVED" ]; then
  commit__fail "misuse: commit.sh must not run as '$GIT_USER_RESOLVED'; expected doas boundary"
fi

command -v doas >/dev/null 2>&1 \
  || commit__fail "doas not found; cannot execute git as '$GIT_USER_RESOLVED'"

commit__info "Work tree root: $work_root"
commit__info "Bare repository: $BARE_REPO"
commit__info "Git bin: $GIT_BIN_RESOLVED"
commit__info "Git user: $GIT_USER_RESOLVED"

commit__git() {
  doas -u "$GIT_USER_RESOLVED" "$GIT_BIN_RESOLVED" \
    --git-dir="$BARE_REPO" \
    --work-tree="$work_root" \
    "$@"
}

commit__git rev-parse --git-dir >/dev/null 2>&1 \
  || commit__fail "bare repository not accessible at $BARE_REPO"

# ---------- stage explicit inputs only (support deletions) ----------

case $work_root in
  */) work_root_prefix=$work_root ;;
  *)  work_root_prefix=$work_root/ ;;
esac

for file in "$@"; do
  case $file in
    '') commit__fail "empty file path argument" ;;
  esac

  # Resolve the user-supplied argument to an absolute path for boundary checks.
  # Note: for deletion support, the file may not exist, so we cannot rely on cd(dirname) always working.
  case $file in
    /*) abs_candidate=$file ;;
    *)  abs_candidate=$work_root_prefix$file ;;
  esac

  # Normalize without requiring the file to exist:
  # - If the parent directory exists, canonicalize it via pwd -P
  # - Otherwise, keep the raw joined path (boundary check uses work_root_prefix on the raw join)
  cand_dir=$(dirname -- "$abs_candidate") || commit__fail "cannot parse path: $file"
  cand_base=$(basename -- "$abs_candidate") || commit__fail "cannot parse path: $file"

  if abs_dir=$(cd "$cand_dir" 2>/dev/null && pwd -P); then
    abs_path=$abs_dir/$cand_base
  else
    abs_path=$abs_candidate
  fi

  # Enforce boundary: must be within the work tree (or equal to it).
  case $abs_path in
    "$work_root_prefix"*) : ;;
    "$work_root")          : ;;
    *) commit__fail "refusing to stage path outside work tree: $file ($abs_path)" ;;
  esac

  # Reject directories to prevent staging implicit sets of files.
  # If the directory exists, this is definitely misuse. If it doesn't exist, treat as deletion/missing file candidate.
  if [ -d "$abs_path" ]; then
    commit__fail "refusing to stage a directory (must be an explicit file): $file"
  fi

  rel_path=${abs_path#"$work_root_prefix"}
  [ "$rel_path" != "$abs_path" ] \
    || commit__fail "internal error deriving relative path for $file"

  # Stage explicit file path, supporting deletions:
  # - If the file exists now -> add it
  # - If it does not exist -> remove it from the index if tracked (and stage that removal)
  if [ -e "$abs_path" ]; then
    commit__info "Staging file: $rel_path"
    commit__git add -- "$rel_path" >/dev/null 2>&1 \
      || commit__fail "git add failed for $file"
  else
    # Only stage a deletion if the path is currently tracked.
    if commit__git ls-files --error-unmatch -- "$rel_path" >/dev/null 2>&1; then
      commit__info "Staging deletion: $rel_path"
      commit__git rm --cached --ignore-unmatch -- "$rel_path" >/dev/null 2>&1 \
        || commit__fail "git rm --cached failed for $file"
    else
      commit__warn "Skipping missing untracked path (nothing to stage): $rel_path"
    fi
  fi
done

# ---------- commit if anything staged ----------

if commit__git diff --cached --quiet >/dev/null 2>&1; then
  commit__warn "No changes to commit."
  exit 3
fi

commit__info "Running git commit"
commit_status=0
commit_output=$(
  commit__git commit -m "$message" 2>&1
) || commit_status=$?

if [ "$commit_status" -eq 0 ]; then
  [ -n "$commit_output" ] && printf '%s\n' "$commit_output" >&2
  exit 0
fi

case $commit_output in
  *'nothing to commit'*|*'no changes added to commit'*)
    [ -n "$commit_output" ] && printf '%s\n' "$commit_output" >&2
    commit__warn "No changes to commit."
    exit 3
    ;;
  *)
    [ -n "$commit_output" ] && printf '%s\n' "$commit_output" >&2
    commit__fail "git commit failed"
    ;;
esac
