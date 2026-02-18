#!/bin/sh
# (helper) sync-latest-logs-to-vault.sh — Mirror *-latest.log as Markdown notes in the Obsidian vault
#
# Helper executable (NOT a leaf job):
# - Invoked by script-status-report.sh (wrapped leaf) or other wrapped jobs.
# - stdout: empty by default; optionally emits list of written files.
# - stderr: diagnostics only.
# - No wrapper, no commit registration, no anchor artifact.
#
# Author: deadhedd
# License: MIT
# shellcheck shell=sh

set -eu
PATH="/usr/local/bin:/usr/bin:/bin:${PATH:-}"

###############################################################################
# Logging (stderr only)
###############################################################################
log_debug() { printf '%s\n' "DEBUG: sync-latest-logs: $*" >&2; }
log_info()  { printf '%s\n' "INFO: sync-latest-logs: $*"  >&2; }
log_warn()  { printf '%s\n' "WARN: sync-latest-logs: $*"  >&2; }
log_error() { printf '%s\n' "ERROR: sync-latest-logs: $*" >&2; }

###############################################################################
# Helpers
###############################################################################
die() { log_error "$*"; exit 1; }

###############################################################################
# Resolve paths (repo-local helper; do not require wrapper env)
###############################################################################
script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)

###############################################################################
# Engine libs (repo-relative)
###############################################################################
repo_root=$(
  CDPATH= cd "$script_dir/../.." 2>/dev/null && pwd
) || die "failed to resolve repo root from script location"

lib_dir=$repo_root/engine/lib
datetime_lib=$lib_dir/datetime.sh
periods_lib=$lib_dir/periods.sh

[ -r "$datetime_lib" ] || die "datetime lib not found/readable: $datetime_lib"
# shellcheck source=/dev/null
. "$datetime_lib" || die "failed to source datetime lib: $datetime_lib"

[ -r "$periods_lib" ] || die "periods lib not found/readable: $periods_lib"
# shellcheck source=/dev/null
. "$periods_lib" || die "failed to source periods lib: $periods_lib"

###############################################################################
# Argument parsing
###############################################################################
usage() {
  cat <<'EOF'
Usage: sync-latest-logs-to-vault.sh [--log-root <path>] [--vault-log-dir <path>] [--emit-written-list]

Options:
  --log-root <path>       Log root directory containing *-latest.log
                          Default: ${LOG_ROOT:-/home/obsidian/logs}
  --vault-log-dir <path>  Destination root for markdown mirrors inside the vault
                          Default: <VAULT_ROOT>/Server Logs/Latest Logs
  --emit-written-list     Emit one destination path per written .md file to stdout
                          (stdout is otherwise empty)
  --help                  Show this help
EOF
}

emit_written=0
log_root="${LOG_ROOT:-/home/obsidian/logs}"
vault_log_dir=""

while [ $# -gt 0 ]; do
  case "$1" in
    --log-root)
      [ $# -ge 2 ] || { usage >&2; die "missing value for --log-root"; }
      log_root=$2
      shift 2
      ;;
    --vault-log-dir)
      [ $# -ge 2 ] || { usage >&2; die "missing value for --vault-log-dir"; }
      vault_log_dir=$2
      shift 2
      ;;
    --emit-written-list)
      emit_written=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage >&2
      die "unknown argument: $1"
      ;;
  esac
done

###############################################################################
# Defaults that depend on VAULT_ROOT
###############################################################################
if [ -z "$vault_log_dir" ]; then
  [ -n "${VAULT_ROOT:-}" ] || die "VAULT_ROOT not set (required unless --vault-log-dir is provided)"
  vault_log_dir="${VAULT_ROOT%/}/Server Logs/Latest Logs"
fi

case "$log_root" in
  /*) : ;;
  *) die "--log-root must be an absolute path: $log_root" ;;
esac
case "$vault_log_dir" in
  /*) : ;;
  *) die "--vault-log-dir must be an absolute path: $vault_log_dir" ;;
esac

###############################################################################
# Atomic write helper (temp-in-destination-dir; matches daily generator style)
###############################################################################
write_atomic_file() {
  _dest=$1
  _dir=${_dest%/*}
  _tmp="${_dir}/.${_dest##*/}.tmp.$$"

  if ! mkdir -p "$_dir"; then
    return 1
  fi

  (
    trap 'rm -f "$_tmp"' HUP INT TERM 0
    if ! cat >"$_tmp"; then
      exit 1
    fi
    if ! mv "$_tmp" "$_dest"; then
      exit 1
    fi
    trap - HUP INT TERM 0
    exit 0
  ) || {
    rm -f "$_tmp" 2>/dev/null || true
    return 1
  }
}

###############################################################################
# Enumerate and mirror
###############################################################################
if [ ! -d "$log_root" ]; then
  log_warn "Log root not found: $log_root (nothing to sync)"
  exit 0
fi

###############################################################################
# Enumerate logs
###############################################################################
found=0
written=0
failed=0
skipped_missing=0
skipped_unreadable=0

list_file=$(mktemp "${TMPDIR:-/tmp}/sync-latest-logs.list.XXXXXX") || die "mktemp failed"
trap 'rm -f "$list_file"' EXIT INT TERM HUP

find "$log_root" -name '*-latest.log' 2>/dev/null >"$list_file" || true

run_iso=$(dt_now_local_iso 2>/dev/null || true)
[ -n "$run_iso" ] || run_iso="(unknown)"

###############################################################################
# Write loop (.md per log)
###############################################################################
while IFS= read -r link || [ -n "$link" ]; do
  [ -n "$link" ] || continue
  found=$((found + 1))

  if [ ! -e "$link" ]; then
    skipped_missing=$((skipped_missing + 1))
    continue
  fi

  if [ ! -r "$link" ]; then
    skipped_unreadable=$((skipped_unreadable + 1))
    continue
  fi

  rel=${link#${log_root%/}/}
  case "$rel" in
    *.log) md_rel=${rel%".log"}.md ;;
    *)     md_rel=$rel.md ;;
  esac

  dest="${vault_log_dir%/}/$md_rel"

  mkdir -p "${dest%/*}" || { failed=$((failed + 1)); continue; }

  if write_atomic_file "$dest" <<EOF
# Latest Log: ${rel##*/}

- Source: $link
- Captured: $run_iso

\`\`\`
$(cat "$link" 2>/dev/null || true)
\`\`\`
EOF
  then
    written=$((written + 1))
    if [ "$emit_written" -eq 1 ]; then
      printf '%s\n' "$dest"
    fi
  else
    failed=$((failed + 1))
  fi
done <"$list_file"

###############################################################################
# Exit
###############################################################################
log_info "sync-latest-logs: found=$found written=$written failed=$failed skipped_missing=$skipped_missing skipped_unreadable=$skipped_unreadable"

[ "$failed" -eq 0 ] || exit 1
exit 0
