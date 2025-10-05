#!/bin/sh
# Stage and commit files to the git repository, mirroring the legacy commit.js helper.
# Usage: commit.sh [-c context] <repo_root> <message> <file> [file...]

set -eu

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

# Stage each file individually.
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

# Attempt to commit and provide feedback when there are no staged changes.
commit_output=$(git -C "$repo_root" commit -m "$message" 2>&1) || commit_status=$?

if [ "${commit_status-0}" -ne 0 ]; then
  case $commit_output in
    *'nothing to commit'*|*'no changes added to commit'*)
      if [ -n "$commit_output" ]; then
        printf '%s\n' "$commit_output" >&2
      fi
      printf '⚠️ No changes to commit: %s\n' "$commit_output" >&2
      exit 0
      ;;
    *)
      if [ -n "$commit_output" ]; then
        printf '%s\n' "$commit_output" >&2
      fi
      printf '%s %s\n' "$prefix" "$commit_output" >&2
      exit "${commit_status:-1}"
      ;;
  esac
fi

if [ -n "$commit_output" ]; then
  printf '%s\n' "$commit_output"
fi

