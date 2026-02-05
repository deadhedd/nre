#!/bin/sh
# Leaf job template (wrapper required)
#
# Responsibilities:
# - Perform one job
# - Produce one primary artifact
# - Declare that artifact via COMMIT_LIST_FILE (if provided)
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
# Resolve paths
###############################################################################

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd -P)

wrap="$repo_root/engine/wrap.sh"
script_path="$script_dir/$(basename "$0")"

###############################################################################
# Self-wrap (minimal, dumb, contract-aligned)
###############################################################################

# engine/wrap.sh owns JOB_WRAP_ACTIVE; leaf does not set it.
if [ "${JOB_WRAP_ACTIVE:-0}" != "1" ]; then
  if [ ! -x "$wrap" ]; then
    printf 'ERROR: leaf wrap: wrapper not found/executable: %s\n' "$wrap" >&2
    exit 127
  fi
  printf 'INFO: leaf wrap: exec wrapper: %s\n' "$wrap" >&2
  exec /bin/sh "$wrap" "$script_path" "$@"
else
  # Wrapped execution path; informational only.
  printf 'DEBUG: leaf wrap: wrapper active; executing leaf\n' >&2
fi

###############################################################################
# Argument parsing (example - customize per job)
###############################################################################

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

# Contract:
# - absolute path
# - single, obvious artifact
# - stored in `primary_result`
# Artifact root:
# - Must be provided by wrapper.
if [ -z "${VAULT_ROOT:-}" ]; then
  printf 'ERROR: VAULT_ROOT not set (wrapper required)\n' >&2
  exit 127
fi
artifact_root=$VAULT_ROOT

if [ -z "$output_path" ]; then
  ts_utc=$(date -u '+%Y-%m-%dT%H%M%SZ' 2>/dev/null || date '+%Y-%m-%dT%H%M%S')
  primary_result="$artifact_root/output/example-${ts_utc}.txt"
else
  primary_result="$output_path"
fi

generate_content() {
  cat <<EOF_CONTENT
Example leaf output

Generated at (UTC): $(date -u '+%Y-%m-%dT%H%M%SZ' 2>/dev/null || date)
Job: ${JOB_NAME:-<unset>}
EOF_CONTENT
}

if [ "$dry_run" -eq 1 ]; then
  generate_content
  exit 0
fi

mkdir -p "$(dirname "$primary_result")"
generate_content >"$primary_result"

###############################################################################
# Commit registration (contractual)
###############################################################################

# Leaf declares what it produced; wrapper decides whether/how to commit.
if [ -n "${COMMIT_LIST_FILE:-}" ]; then
  printf '%s\n' "$primary_result" >>"$COMMIT_LIST_FILE" 2>/dev/null || :
fi

###############################################################################
# Diagnostics
###############################################################################

printf 'INFO: %s\n' "Produced artifact: $primary_result" >&2

exit 0
