#!/bin/sh
# Stage and commit files to the git repository, mirroring the legacy commit.js helper.
# Usage: commit.sh [-c context] <repo_root> <message> <file> [file...]

set -eu
PATH="/usr/local/bin:/usr/bin:/bin"

context='changes'

print_usage() {
  printf '%s\n' "Usage: $0 [-c context] <repo_root> <message> <file> [file...]" >&2
}

# Parse optional context flag.
while [ $# -gt 0 ]; do
  case $1 in
    -c|--context)
      if [ $# -lt 2 ]; then
        print_usage
        exit 1
      fi
      context=$2
      shift 2
      ;;
    --)
      shift
      break
      ;;
    -*)
      print_usage
      exit 1
      ;;
    *)
      break
      ;;
  esac
done

if [ $# -lt 3 ]; then
  print_usage
  exit 1
fi

repo_input=$1
shift
message=$1
shift

# Resolve repository root to an absolute path.
if ! repo_root=$(cd "$repo_input" 2>/dev/null && pwd -P); then
  printf '⚠️ Failed to commit %s: %s\n' "$context" "invalid repository root: $repo_input" >&2
  exit 1
fi

# Determine logging prefix for errors.
if [ "$context" = 'changes' ]; then
  prefix='⚠️ Failed to commit changes:'
else
  prefix="⚠️ Failed to commit $context:"
fi

# --- Repo hygiene / config ---
git -C "$repo_root" config --global --add safe.directory "$repo_root" 2>/dev/null || true
git -C "$repo_root" remote set-url origin /home/git/vaults/Main.git 2>/dev/null || true
git -C "$repo_root" config pull.rebase true 2>/dev/null || true

# --- Helper for portable timestamps (OpenBSD-compatible) ---
ts_utc() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

# --- Pre-sync protection for local changes (including untracked) ---
stashed=0
if [ -n "$(git -C "$repo_root" status --porcelain)" ]; then
  git -C "$repo_root" stash push -u -m "auto: pre-sync $(ts_utc)"
  stashed=1
fi

# Ensure we're on a branch (prefer master) before rebasing; avoid detached-HEAD weirdness.
current_branch=$(git -C "$repo_root" rev-parse --abbrev-ref HEAD 2>/dev/null || echo HEAD)
if [ "$current_branch" = "HEAD" ]; then
  if git -C "$repo_root" show-ref --verify --quiet refs/heads/master; then
    git -C "$repo_root" checkout master
  elif git -C "$repo_root" show-ref --verify --quiet refs/heads/main; then
    git -C "$repo_root" checkout main
  else
    git -C "$repo_root" checkout -B master || true
  fi
fi

# ---- Sync with remote safely ----
git -C "$repo_root" fetch --prune origin

upstream_branch=master
if ! git -C "$repo_root" ls-remote --heads origin master >/dev/null 2>&1; then
  if git -C "$repo_root" ls-remote --heads origin main >/dev/null 2>&1; then
    upstream_branch=main
  fi
fi

sync_ok=1
if ! git -C "$repo_root" rebase "origin/$upstream_branch"; then
  git -C "$repo_root" rebase --abort 2>/dev/null || true
  sync_ok=0
fi

# Restore stashed work (if any) back into the working tree.
if [ $stashed -eq 1 ]; then
  if ! git -C "$repo_root" stash pop --index; then
    printf '%s unable to reapply stashed work cleanly.\n' "$prefix" >&2
    printf '   The pre-sync stash is still available as stash@{0}.\n' >&2
    printf '   Resolve the conflicts manually and re-run the automation.\n' >&2
    git -C "$repo_root" reset --hard HEAD 2>/dev/null || true
    git -C "$repo_root" clean -fd 2>/dev/null || true
    exit 1
  fi
fi

# If sync failed (e.g., due to conflicts unrelated to our stash), bail gracefully.
if [ $sync_ok -ne 1 ]; then
  printf '⚠️ Failed to sync with origin/%s before commit\n' "$upstream_branch" >&2
fi

# ---- Stage each file explicitly provided to the script ----
for file in "$@"; do
  case $file in
    /*) abs_path=$file ;;
    *) abs_path="$repo_root/$file" ;;
  esac
  if ! git -C "$repo_root" add -- "$abs_path"; then
    printf '%s git add failed for %s\n' "$prefix" "$file" >&2
    exit 1
  fi
done

# ---- Commit (if there is anything staged) ----
commit_status=0
commit_output=$(git -C "$repo_root" commit -m "$message" 2>&1) || commit_status=$?

if [ "$commit_status" -ne 0 ]; then
  case $commit_output in
    *'nothing to commit'*|*'no changes added to commit'*)
      [ -n "$commit_output" ] && printf '%s\n' "$commit_output" >&2
      printf '⚠️ No changes to commit.\n' >&2
      exit 0
      ;;
    *)
      [ -n "$commit_output" ] && printf '%s\n' "$commit_output" >&2
      printf '%s %s\n' "$prefix" "$commit_output" >&2
      exit "$commit_status"
      ;;
  esac
else
  [ -n "$commit_output" ] && printf '%s\n' "$commit_output"
fi

# ---- Push with one retry on rejection ----
if ! git -C "$repo_root" push origin HEAD:"$upstream_branch"; then
  git -C "$repo_root" fetch --prune origin
  if git -C "$repo_root" rebase "origin/$upstream_branch"; then
    git -C "$repo_root" push origin HEAD:"$upstream_branch" || {
      printf '⚠️ push failed after rebase retry\n' >&2
      exit 1
    }
  else
    git -C "$repo_root" rebase --abort 2>/dev/null || true
    printf '⚠️ rebase failed during push retry\n' >&2
    exit 1
  fi
fi
