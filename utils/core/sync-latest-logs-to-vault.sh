#!/bin/sh
# sync-latest-logs-to-vault.sh — Mirror *-latest.log as Markdown notes in the Obsidian vault
# Author: deadhedd
#
# Multi-artifact job: writes one .md file per *-latest.log.
set -eu
PATH="/usr/local/bin:/usr/bin:/bin:${PATH:-}"

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd -P)
job_wrap="$repo_root/utils/core/job-wrap.sh"
script_path="$script_dir/$(basename -- "$0")"

if [ "${JOB_WRAP_ACTIVE:-0}" != "1" ] && [ -x "$job_wrap" ]; then
  JOB_WRAP_ACTIVE=1 exec /bin/sh "$job_wrap" "$script_path" "$@"
fi

now_local() {
  date '+%Y-%m-%dT%H:%M:%S'
}

log_msg() {
  printf '%s %s\n' "$(now_local)" "$*" >&2
}

write_atomic_file() {
  target=$1
  tmp=$(mktemp "${TMPDIR:-/tmp}/sync-latest-logs-write.XXXXXX") || return 1

  if ! cat >"$tmp"; then
    rm -f -- "$tmp" 2>/dev/null || true
    return 1
  fi

  if ! mv -- "$tmp" "$target" 2>/dev/null; then
    rm -f -- "$tmp" 2>/dev/null || true
    return 1
  fi

  return 0
}

LOG_ROOT=${LOG_ROOT:-/home/obsidian/logs}
vault_root=${VAULT_PATH:-/home/obsidian/vaults/Main}
VAULT_LOG_DIR=${VAULT_LOG_DIR:-"${vault_root%/}/Server Logs/Latest Logs"}

log_msg "Starting sync-latest-logs-to-vault"
log_msg "LOG_ROOT=$LOG_ROOT"
log_msg "VAULT_LOG_DIR=$VAULT_LOG_DIR"

if [ ! -d "$LOG_ROOT" ]; then
  log_msg "Log root not found: $LOG_ROOT"
  exit 0
fi

if ! mkdir -p -- "$VAULT_LOG_DIR" 2>/dev/null; then
  log_msg "Failed to create vault log directory: $VAULT_LOG_DIR"
  exit 1
fi

found=0
written=0
failed=0
skipped_missing=0
skipped_unreadable=0

list_file=$(mktemp "${TMPDIR:-/tmp}/sync-latest-logs.XXXXXX") || exit 1
trap 'rm -f -- "$list_file" 2>/dev/null || true' EXIT INT HUP TERM

find "$LOG_ROOT" -name '*-latest.log' 2>/dev/null >"$list_file" || true

while IFS= read -r link || [ -n "$link" ]; do
  [ -n "$link" ] || continue
  found=$((found + 1))

  if [ ! -e "$link" ]; then
    skipped_missing=$((skipped_missing + 1))
    log_msg "Skipping missing link: $link"
    continue
  fi

  if [ ! -r "$link" ]; then
    skipped_unreadable=$((skipped_unreadable + 1))
    log_msg "Skipping unreadable link: $link"
    continue
  fi

  case "$link" in
    "${LOG_ROOT%/}/"*)
      rel=${link#${LOG_ROOT%/}/}
      ;;
    *)
      rel=$(basename -- "$link")
      ;;
  esac

  case "$rel" in
    *.log) md_rel=${rel%".log"}.md ;;
    *) md_rel=$rel.md ;;
  esac

  dest="$VAULT_LOG_DIR/$md_rel"
  dest_dir=${dest%/*}

  if [ ! -d "$dest_dir" ] && ! mkdir -p -- "$dest_dir" 2>/dev/null; then
    failed=$((failed + 1))
    log_msg "Failed to create destination dir: $dest_dir"
    continue
  fi

  run_iso=$(now_local)
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
    log_msg "Wrote $link -> $dest"
  else
    failed=$((failed + 1))
    log_msg "Write failed: $link -> $dest"
  fi

done <"$list_file"

log_msg "Summary: found=$found written=$written failed=$failed skipped_missing=$skipped_missing skipped_unreadable=$skipped_unreadable"

[ "$failed" -eq 0 ] || exit 1
exit 0
