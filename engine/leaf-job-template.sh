#!/bin/sh
# leaf-job-template.sh
#
# Leaf job template (contract-first, trust-the-system).
#
# - If not already wrapped, exec job-wrap.
# - Assumes job-wrap exports LOG_LIB_DIR and (optionally) COMMIT_LIST_FILE.
# - stdout is allowed for job output (this is a leaf).
# - stderr is for logs (via log.sh).
# - No fallbacks. If the system is broken, it should fail.

set -eu

###############################################################################
# Wrapper handoff
###############################################################################

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd -P)
job_wrap="$repo_root/engine/job-wrap.sh"
script_path="$script_dir/$(basename -- "$0")"

if [ "${JOB_WRAP_ACTIVE:-0}" != "1" ] && [ -x "$job_wrap" ]; then
  exec /bin/sh "$job_wrap" "$script_path" "$@"
fi

###############################################################################
# Logging + commit wiring (trust the system)
###############################################################################

# shellcheck disable=SC1090
. "${LOG_LIB_DIR%/}/log.sh"

commit_add() {
  [ -n "${COMMIT_LIST_FILE:-}" ] || return 0
  printf '%s\n' "$1" >>"$COMMIT_LIST_FILE"
}

###############################################################################
# CLI parsing (minimal)
###############################################################################

usage() {
  cat >&2 <<'EOF'
Usage: leaf-job-template.sh [--help]
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    *) log_error "Unknown option: $1"; usage; exit 2 ;;
  esac
done

###############################################################################
# Main job
###############################################################################

main() {
  log_info "Starting"

  # --- Your work here -------------------------------------------------------
  # Example: create a file (commit-managed), and emit a result to stdout.

  out_dir="${OUT_DIR:-$repo_root/out}"
  out_file="$out_dir/example.txt"

  mkdir -p "$out_dir"
  printf '%s\n' "example content" >"$out_file"
  commit_add "$out_file"

  # Leaf job output (stdout):
  printf '%s\n' "OK: wrote $out_file"
  # --------------------------------------------------------------------------

  log_info "Done"
}

main
