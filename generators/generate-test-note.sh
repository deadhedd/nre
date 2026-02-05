#!/bin/sh
# Generate a small test note in the vault to validate wrapper/logging/commit end-to-end.

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd -P)

new_wrap="$repo_root/engine/wrap.sh"
legacy_wrap="$repo_root/utils/core/job-wrap.sh"

script_path="$script_dir/$(basename "$0")"

# Self-wrap: leaf does NOT source logging libs; wrapper coordinates logging.
# IMPORTANT: engine/wrap.sh owns JOB_WRAP_ACTIVE; do not set it here.
if [ "${JOB_WRAP_ACTIVE:-0}" != "1" ]; then
  if [ -x "$new_wrap" ]; then
    printf 'INFO: leaf wrap: exec new wrapper: %s\n' "$new_wrap" >&2
    exec /bin/sh "$new_wrap" "$script_path" "$@"
  fi
  if [ -x "$legacy_wrap" ]; then
    printf 'INFO: leaf wrap: exec legacy wrapper: %s\n' "$legacy_wrap" >&2
    JOB_WRAP_ACTIVE=1 exec /bin/sh "$legacy_wrap" "$script_path" "$@"
  fi
  printf 'WARN: leaf wrap: no wrapper found/executable; continuing unwrapped\n' >&2
else
  printf 'DEBUG: leaf wrap: already wrapped; continuing\n' >&2
fi

usage() {
  cat <<'EOF_USAGE'
Usage: generate-test-note.sh [--vault <path>] [--outdir <name>] [--name <title>] [--force] [--dry-run]

Options:
  --vault <path>    Vault root where the note should be created.
                    Defaults to $VAULT_PATH or /home/obsidian/vaults/Main.
  --outdir <name>   Subdirectory inside the vault. Defaults to "Scratch/Test Notes".
  --name <title>    Base note title (without extension). Defaults to "Wrapper Test".
  --force           Overwrite if the note already exists.
  --dry-run         Print note contents to stdout instead of writing a file.
  --help            Show this message.
EOF_USAGE
}

vault_path=${VAULT_PATH:-/home/obsidian/vaults/Main}
outdir="Scratch/Test Notes"
base_name="Wrapper Test"
force=0
dry_run=0

while [ $# -gt 0 ]; do
  case "$1" in
    --vault)
      [ $# -ge 2 ] || { printf 'ERROR: %s\n' "Missing value for --vault" >&2; usage >&2; exit 2; }
      vault_path=$2
      shift 2
      ;;
    --outdir)
      [ $# -ge 2 ] || { printf 'ERROR: %s\n' "Missing value for --outdir" >&2; usage >&2; exit 2; }
      outdir=$2
      shift 2
      ;;
    --name)
      [ $# -ge 2 ] || { printf 'ERROR: %s\n' "Missing value for --name" >&2; usage >&2; exit 2; }
      base_name=$2
      shift 2
      ;;
    --force)
      force=1
      shift
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
      printf 'ERROR: %s\n' "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

vault_root=${vault_path%/}

trimmed_outdir=$outdir
while [ "${trimmed_outdir#/}" != "$trimmed_outdir" ]; do trimmed_outdir=${trimmed_outdir#/}; done
while [ "${trimmed_outdir%/}" != "$trimmed_outdir" ]; do trimmed_outdir=${trimmed_outdir%/}; done

if [ -n "$trimmed_outdir" ]; then
  note_dir="$vault_root/$trimmed_outdir"
else
  note_dir="$vault_root"
fi

ts_utc=$(date -u '+%Y-%m-%dT%H%M%SZ' 2>/dev/null || date '+%Y-%m-%dT%H%M%S')
safe_base=$(printf '%s' "$base_name" | tr -c 'A-Za-z0-9._ -' '_' | tr ' ' '_')
note_path="${note_dir%/}/${safe_base}-${ts_utc}.md"

if [ "$dry_run" -ne 1 ]; then
  mkdir -p "$note_dir"
fi

if [ -f "$note_path" ] && [ "$force" -ne 1 ]; then
  printf 'ERROR: %s\n' "Refusing to overwrite existing file: $note_path" >&2
  printf 'ERROR: %s\n' "Re-run with --force to overwrite." >&2
  exit 1
fi

write_note() {
  cat <<EOF_NOTE
# $base_name

This is a small test note generated to validate:
- leaf self-wrap
- wrapper logging/capture
- optional commit helper

Generated at (UTC): $ts_utc
Host: $(hostname 2>/dev/null || printf unknown)
Job: ${JOB_NAME:-<unset>}
Log file: ${LOG_FILE:-<unset>}

EOF_NOTE
}

if [ "$dry_run" -eq 1 ]; then
  write_note
  exit 0
fi

write_note >"$note_path"

# Register the artifact when the commit list file is provided.
# Contract: leaf declares commit targets by appending paths to COMMIT_LIST_FILE.
# Leaf does not care whether it's wrapped; absence of COMMIT_LIST_FILE simply
# means there's nowhere to write (e.g., unwrapped run or commit disabled).
if [ -n "${COMMIT_LIST_FILE:-}" ]; then
  # Best-effort: never fail note generation due to commit registration issues.
  # note_path is absolute by construction; keep one path per line.
  printf '%s\n' "$note_path" >>"$COMMIT_LIST_FILE" 2>/dev/null || :
fi

# Diagnostics go to stderr with level prefix (wrapper captures stderr).
printf 'INFO: %s\n' "Wrote test note: $note_path" >&2
