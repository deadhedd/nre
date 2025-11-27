#!/bin/sh
# utils/core/daily-note-snapshot.sh — Replace Obsidian embed lines in a daily note with static content.
# Author: deadhedd
# License: MIT
set -eu
PATH="/usr/local/bin:/usr/bin:/bin:${PATH:-}"
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
commit_helper="$script_dir/commit.sh"
log_helper="$script_dir/log.sh"

. "$log_helper"

# Set this to your vault root or override via environment.
VAULT_DEFAULT=${VAULT_PATH:-/home/obsidian/vaults/Main}
: "${VAULT_ROOT:=$VAULT_DEFAULT}"

DRY_RUN=0
embed_total=0
embed_resolved=0
embed_unresolved=0

print_usage() {
  printf 'Usage: %s [-n|--dry-run] PATH/TO/daily-note.md\n' "$0" >&2
}

# Option parsing (very simple: optional first arg -n/--dry-run)
case "${1-}" in
  -n|--dry-run)
    DRY_RUN=1
    shift
    ;;
  "")
    print_usage
    exit 1
    ;;
esac

if [ "$#" -ne 1 ]; then
  print_usage
  exit 1
fi

NOTE=$1

if [ ! -f "$NOTE" ]; then
  log_err "note not found: $NOTE"
  exit 1
fi

# Resolve to an absolute path for downstream helpers.
NOTE_DIR=$(CDPATH= cd -- "$(dirname -- "$NOTE")" && pwd -P)
NOTE_BASE=$(basename -- "$NOTE")
NOTE="$NOTE_DIR/$NOTE_BASE"

TMP=$NOTE.tmp
BAK=$NOTE.bak
TEST_NOTE=$NOTE.dryrun

# Clean up temp file on exit or common signals (0 is the POSIX "EXIT" pseudo-signal)
trap 'rm -f "$TMP"' 0 HUP INT TERM

log_info "Vault root: $VAULT_ROOT"
log_info "Note: $NOTE"
if [ "$DRY_RUN" -eq 1 ]; then
  log_info "Mode: dry run (writing to $TEST_NOTE)"
else
  log_info "Mode: replace note in place with backup $BAK"
fi

expand_embed() {
  link=$1
  line=$2

  embed_total=$((embed_total + 1))
  log_info "Processing embed: $link"

  # Strip alias part: "path#heading|Alias" -> "path#heading"
  case "$link" in
    *'|'*)
      link_no_alias=${link%%'|'*}
      log_info "Alias stripped: $link_no_alias"
      ;;
    *)
      link_no_alias=$link
      ;;
  esac

  # Split into path and heading: "path#heading"
  case "$link_no_alias" in
    *'#'*)
      path=${link_no_alias%%'#'*}
      heading=${link_no_alias#*'#'}
      log_info "Parsed path: $path (heading: $heading)"
      ;;
    *)
      path=$link_no_alias
      heading=
      log_info "Parsed path: $path (full file)"
      ;;
  esac

  file=
  resolve_hint=

  # Resolve path:
  # 1) Relative to the note's directory
  # 2) Relative to the vault root
  # For each, try with and without ".md".
  for base in "$NOTE_DIR" "$VAULT_ROOT"; do
    candidate=$base/$path
    if [ -f "$candidate" ]; then
      file=$candidate
      resolve_hint="direct match under $base"
      break
    elif [ -f "$candidate.md" ]; then
      file=$candidate.md
      resolve_hint="direct .md match under $base"
      break
    fi
  done

  case "$path" in
    */*)
      ;;
    *)
      if [ -z "$file" ]; then
        found=$(
          find "$VAULT_ROOT" -type f \( -name "$path" -o -name "$path.md" \) -print 2>/dev/null | head -n 1 || :
        )
        if [ -n "$found" ]; then
          file=$found
          resolve_hint="recursive match under $VAULT_ROOT"
        fi
      fi
      ;;
  esac

  if [ -z "$file" ]; then
    # Cannot resolve, leave embed as-is
    log_warn "embed not resolved (missing file?): $link"
    embed_unresolved=$((embed_unresolved + 1))
    printf '%s\n' "$line"
    return
  fi

  log_info "Resolved embed to $file ($resolve_hint)"

  if [ -z "$heading" ]; then
    # Whole file
    log_info "Expanding entire file for embed"
    embed_resolved=$((embed_resolved + 1))
    cat "$file"
    return
  fi

  # Heading section only
  if ! awk -v h="$heading" '
  function heading_level(s,    i,c) {
      c = 0
      for (i = 1; i <= length(s); i++) {
          if (substr(s, i, 1) == "#") c++
          else break
      }
      return c
  }
  BEGIN {
      in_section = 0
      section_level = 0
      found = 0
  }
  {
      if (in_section) {
          if ($0 ~ /^#+[[:space:]]/) {
              lvl = heading_level($0)
              if (lvl <= section_level) {
                  exit
              }
          }
          print
          next
      }

      if ($0 ~ /^#+[[:space:]]/) {
          text = $0
          sub(/^#+[[:space:]]*/, "", text)
          if (text == h) {
              in_section = 1
              section_level = heading_level($0)
              print
              found = 1
          }
      }
  }
  END {
      if (!found) exit 1
  }
  ' "$file"
  then
    # Heading not found: leave embed as-is
    log_warn "embed not resolved (missing heading): $link"
    embed_unresolved=$((embed_unresolved + 1))
    printf '%s\n' "$line"
  else
    log_info "Expanded heading \"$heading\" from $file"
    embed_resolved=$((embed_resolved + 1))
  fi
}

# Create temp file
: > "$TMP"

# Process note line by line
# Only replaces lines that are exactly an embed: ![[...]]
while IFS= read -r line; do
  case "$line" in
    '![['*']]' )
      link=${line#'![['}
      link=${link%']]'}
      expand_embed "$link" "$line" >> "$TMP"
      ;;
    * )
      printf '%s\n' "$line" >> "$TMP"
      ;;
  esac
done < "$NOTE"

log_info "Embeds processed: $embed_total (resolved: $embed_resolved, unresolved: $embed_unresolved)"

if [ "$DRY_RUN" -eq 1 ]; then
  # Dry run: keep original note; write result to NOTE.dryrun
  mv "$TMP" "$TEST_NOTE"
  log_info "Dry run: wrote expanded note to $TEST_NOTE"
else
  # Backup and replace original note
  cp "$NOTE" "$BAK"
  mv "$TMP" "$NOTE"
  log_info "Replaced $NOTE (backup at $BAK)"

  if [ -x "$commit_helper" ]; then
    if ! "$commit_helper" "$VAULT_ROOT" "daily snapshot: $NOTE_BASE" "$NOTE"; then
      log_warn "commit helper failed for $NOTE"
    fi
  else
    log_warn "commit helper not found: $commit_helper"
  fi
fi
