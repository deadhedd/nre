#!/bin/sh
# Stage and commit files to the central bare repository from a dumb work tree.
# Usage: commit.sh [-c context] <work_tree_root> <message> <file> [file...]

set -eu
PATH="/usr/local/bin:/usr/bin:/bin:${PATH:-}"

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd -P)
job_wrap="$repo_root/utils/core/job-wrap.sh"
script_path="$script_dir/$(basename -- "$0")"

if [ "${JOB_WRAP_ACTIVE:-0}" != "1" ] && [ -x "$job_wrap" ]; then
  JOB_WRAP_ACTIVE=1 exec /bin/sh "$job_wrap" "$script_path" "$@"
fi

printf 'INFO %s\n' "Starting commit helper" >&2

context='changes'

print_usage() {
  printf '%s\n' "Usage: $0 [-c context] <work_tree_root> <message> <file> [file...]" >&2
  printf '%s\n' "Environment:" >&2
  printf '%s\n' "  COMMIT_BARE_REPO  Override the bare repository path (default /home/git/vaults/Main.git)" >&2
}

resolve_path() {
  input=$1
  dir_part=$(dirname "$input") || return 1
  base_part=$(basename "$input") || return 1
  if ! abs_dir=$(cd "$dir_part" 2>/dev/null && pwd -P); then
    return 1
  fi
  printf '%s/%s\n' "$abs_dir" "$base_part"
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

printf 'INFO %s\n' "Commit context: $context" >&2
printf 'INFO %s\n' "Commit message: $message" >&2

# Determine logging prefix for errors.
if [ "$context" = 'changes' ]; then
  prefix='Failed to commit changes'
else
  prefix="Failed to commit $context"
fi

# Resolve work tree root to an absolute path.
if ! work_root=$(cd "$work_input" 2>/dev/null && pwd -P); then
  printf 'WARN %s\n' "$prefix: invalid work tree root: $work_input" >&2
  exit 1
fi
printf 'INFO %s\n' "Work tree root: $work_root" >&2

# Central bare repository path (override with COMMIT_BARE_REPO).
BARE_REPO_DEFAULT='/home/git/vaults/Main.git'
bare_repo_input=${COMMIT_BARE_REPO:-$BARE_REPO_DEFAULT}

if ! BARE_REPO=$(resolve_path "$bare_repo_input"); then
  printf 'ERR  %s\n' "$prefix: invalid bare repository path: $bare_repo_input" >&2
  exit 1
fi

if [ ! -d "$BARE_REPO" ]; then
  printf 'ERR  %s\n' "$prefix: bare repository not found: $BARE_REPO" >&2
  exit 1
fi
printf 'INFO %s\n' "Bare repository: $BARE_REPO" >&2

# Convenience wrapper to run git as the git user against the bare repo + work tree
run_git() {
  doas -u git /usr/local/bin/git \
    --git-dir="$BARE_REPO" \
    --work-tree="$work_root" \
    "$@"
}

# --- Ensure the bare repo exists and is usable ---
if ! run_git rev-parse --git-dir >/dev/null 2>&1; then
  printf 'ERR  %s\n' "$prefix: bare repository not accessible at $BARE_REPO" >&2
  exit 1
fi

# ---- Stage each file explicitly provided to the script ----
for file in "$@"; do
  case $file in
    /*)   abs_path=$file ;;
    *)    abs_path="$work_root/$file" ;;
  esac

  printf 'INFO %s\n' "Staging file: $abs_path" >&2

  if ! run_git add -- "$abs_path"; then
    printf 'ERR  %s\n' "$prefix: git add failed for $file" >&2
    exit 1
  fi
done

# ---- Commit (if there is anything staged) ----
if run_git diff --cached --quiet; then
  printf 'WARN %s\n' "No changes to commit for $context." >&2
  exit 0
fi

commit_status=0
printf 'INFO %s\n' "Running git commit" >&2
commit_output=$(run_git commit -m "$message" 2>&1) || commit_status=$?

if [ "$commit_status" -ne 0 ]; then
  case $commit_output in
    *'nothing to commit'*|*'no changes added to commit'*)
      [ -n "$commit_output" ] && printf '%s\n' "$commit_output" >&2
      printf 'WARN %s\n' "No changes to commit for $context." >&2
      exit 0
      ;;
    *)
      [ -n "$commit_output" ] && printf '%s\n' "$commit_output" >&2
      printf 'ERR  %s\n' "$prefix: $commit_output" >&2
      exit "$commit_status"
      ;;
  esac
else
  [ -n "$commit_output" ] && printf '%s\n' "$commit_output"
fi

# ---- Optional: push to upstream if configured ----
if run_git remote get-url origin >/dev/null 2>&1; then
  printf 'INFO %s\n' "Pushing to origin/master" >&2
  if ! run_git push origin master; then
    printf 'WARN %s\n' "push to origin/master failed for $context (manual intervention required)." >&2
    exit 1
  fi
else
  printf 'INFO %s\n' "Remote 'origin' not configured; skipping push" >&2
fi
