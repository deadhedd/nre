#!/bin/sh
# Stage and commit files to the central bare repository from a dumb work tree.
# Usage: commit.sh [-c context] <work_tree_root> <message> <file> [file...]

set -eu
PATH="/usr/local/bin:/usr/bin:/bin"

context='changes'

print_usage() {
  printf '%s\n' "Usage: $0 [-c context] <work_tree_root> <message> <file> [file...]" >&2
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

work_input=$1
shift
message=$1
shift

# Resolve work tree root to an absolute path.
if ! work_root=$(cd "$work_input" 2>/dev/null && pwd -P); then
  printf '⚠️ Failed to commit %s: %s\n' "$context" "invalid work tree root: $work_input" >&2
  exit 1
fi

# Central bare repository path
BARE_REPO="/home/git/vaults/Main.git"

# Determine logging prefix for errors.
if [ "$context" = 'changes' ]; then
  prefix='⚠️ Failed to commit changes:'
else
  prefix="⚠️ Failed to commit $context:"
fi

# Convenience wrapper to run git as the git user against the bare repo + work tree
run_git() {
  doas -u git /usr/local/bin/git \
    --git-dir="$BARE_REPO" \
    --work-tree="$work_root" \
    "$@"
}

# --- Ensure the bare repo exists and is usable ---
if ! run_git rev-parse --git-dir >/dev/null 2>&1; then
  printf '%s bare repository not accessible at %s\n' "$prefix" "$BARE_REPO" >&2
  exit 1
fi

# ---- Stage each file explicitly provided to the script ----
for file in "$@"; do
  case $file in
    /*)   abs_path=$file ;;
    *)    abs_path="$work_root/$file" ;;
  esac

  if ! run_git add -- "$abs_path"; then
    printf '%s git add failed for %s\n' "$prefix" "$file" >&2
    exit 1
  fi
done

# ---- Commit (if there is anything staged) ----
if run_git diff --cached --quiet; then
  printf '⚠️ No changes to commit for %s.\n' "$context" >&2
  exit 0
fi

commit_status=0
commit_output=$(run_git commit -m "$message" 2>&1) || commit_status=$?

if [ "$commit_status" -ne 0 ]; then
  case $commit_output in
    *'nothing to commit'*|*'no changes added to commit'*)
      [ -n "$commit_output" ] && printf '%s\n' "$commit_output" >&2
      printf '⚠️ No changes to commit for %s.\n' "$context" >&2
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

# ---- Optional: push to upstream if configured ----
if run_git remote get-url origin >/dev/null 2>&1; then
  if ! run_git push origin master; then
    printf '⚠️ push to origin/master failed for %s (manual intervention required).\n' "$context" >&2
    exit 1
  fi
fi
