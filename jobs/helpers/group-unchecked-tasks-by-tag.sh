#!/bin/sh
# jobs/helpers/group-unchecked-tasks-by-tag.sh
# Group unchecked tasks by tag from the combined task list.
#
# Leaf job (wrapper required). Emits grouped markdown to stdout only.
#
# Author: deadhedd
# License: MIT
# shellcheck shell=sh

set -eu

###############################################################################
# Logging (leaf responsibility: emit correctly-formatted messages to stderr)
###############################################################################

log_debug() { printf '%s\n' "DEBUG: $*" >&2; }
log_info()  { printf '%s\n' "INFO: $*"  >&2; }
log_warn()  { printf '%s\n' "WARN: $*"  >&2; }
log_error() { printf '%s\n' "ERROR: $*" >&2; }

###############################################################################
# Resolve paths + mandatory self-wrap
###############################################################################

# shellcheck disable=SC1007
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)

# C1 bootstrap rule: wrapper location is assumed stable *relative to this file*
# for the initial self-wrap hop only. Once wrapped, REPO_ROOT becomes truth.
wrap="$script_dir/../engine/wrap.sh"
script_path="$script_dir/$(basename "$0")"

if [ "${JOB_WRAP_ACTIVE:-0}" != "1" ]; then
  # Fail fast if wrapper isn't executable; do not run unwrapped.
  if [ ! -x "$wrap" ]; then
    log_error "Wrapper not found or not executable: $wrap"
    exit 1
  fi
  exec "$wrap" "$script_path" "$@"
fi

# Ensure common tools are found even under cron (put /usr/local/bin first)
PATH="/usr/local/bin:/usr/bin:/bin:${PATH:-}"

###############################################################################
# Inputs
###############################################################################

# Prefer wrapper-exported VAULT_ROOT; fall back to VAULT_PATH; then hard default.
vault_root="${VAULT_ROOT:-${VAULT_PATH:-/home/obsidian/vaults/Main}}"
vault_root="${vault_root%/}"

file="$vault_root/Inbox/Combined Task List.md"

log_info "cadence=ad-hoc"
log_info "Vault root: $vault_root"
log_info "Task source: $file"

if [ ! -f "$file" ]; then
  log_error "Could not find task list: $file"
  exit 1
fi

###############################################################################
# Work
###############################################################################

tmp=$(mktemp "${TMPDIR:-/tmp}/group-tasks-by-tag.XXXXXX")
cleanup() { rm -f "$tmp"; }
trap cleanup EXIT HUP INT TERM

# Build tab-separated rows: "<tag>\t<cleaned item line>"
# NOTE: stdout is primary data output only; all diagnostics go to stderr.
sed -n '/^- \[ \]/p' "$file" | while IFS= read -r line; do
  tags=$(printf '%s\n' "$line" | grep -o '#[[:alnum:]/-]*' || true)
  [ -z "$tags" ] && continue

  cleaned=$(printf '%s\n' "$line" \
    | sed 's/#[[:alnum:]/-]*//g' \
    | sed 's/[[:space:]]*$//')

  for tag in $tags; do
    printf '%s\t%s\n' "$tag" "$cleaned"
  done
done | sort >"$tmp"

TAB=$(printf '\t')
current=''

while IFS="$TAB" read -r tag item; do
  [ -z "$tag" ] && continue

  if [ "$tag" != "$current" ]; then
    [ -n "$current" ] && printf '\n'
    current="$tag"

    heading=$(printf '%s' "$tag" | cut -c2- | tr -- '-_' ' ')
    formatted=$(printf '%s\n' "$heading" \
      | awk '{for(i=1;i<=NF;i++){ $i=toupper(substr($i,1,1)) substr($i,2)} print}')

    printf '#### %s List\n' "$formatted"
  fi

  printf '%s\n' "$item"
done <"$tmp"
