#!/bin/sh
# jobs/daily-note-snapshot.sh — Replace Obsidian embed lines in a daily note with static content.
#
# Leaf job (wrapper required)
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
# Resolve paths
###############################################################################

# shellcheck disable=SC1007
script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)
wrap="$script_dir/../engine/wrap.sh"

case "$0" in
  /*) script_path=$0 ;;
  *)  script_path=$script_dir/${0##*/} ;;
esac

script_path=$(
  # shellcheck disable=SC1007
  CDPATH= cd "$(dirname "$script_path")" && \
  d=$(pwd) && \
  printf '%s/%s\n' "$d" "${script_path##*/}"
) || {
  log_error "failed to canonicalize script path: $script_path"
  exit 127
}

###############################################################################
# Self-wrap (minimal, dumb, contract-aligned)
###############################################################################

if [ "${JOB_WRAP_ACTIVE:-0}" != "1" ]; then
  if [ ! -x "$wrap" ]; then
    log_error "leaf wrap: wrapper not found/executable: $wrap"
    exit 127
  fi
  log_info "leaf wrap: exec wrapper: $wrap"
  exec "$wrap" "$script_path" ${1+"$@"}
else
  log_debug "leaf wrap: wrapper active; executing leaf"
fi

###############################################################################
# Cadence declaration (contract-required)
###############################################################################

JOB_CADENCE=${JOB_CADENCE:-daily}
log_info "cadence=$JOB_CADENCE"

###############################################################################
# Engine libs (wrapped path only)
###############################################################################

if [ -z "${REPO_ROOT:-}" ]; then
  log_error "REPO_ROOT not set (wrapper required)"
  exit 127
fi
case "$REPO_ROOT" in
  /*) : ;;
  *) log_error "REPO_ROOT not absolute: $REPO_ROOT"; exit 127 ;;
esac
repo_root=$REPO_ROOT

lib_dir=$repo_root/engine/lib
datetime_lib=$lib_dir/datetime.sh

if [ ! -r "$datetime_lib" ]; then
  log_error "datetime lib not found/readable: $datetime_lib"
  exit 127
fi
# shellcheck source=/dev/null
. "$datetime_lib" || { log_error "failed to source datetime lib: $datetime_lib"; exit 127; }

###############################################################################
# Requirements
###############################################################################

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log_error "missing required command: $1"
    exit 127
  fi
}

require_cmd awk
require_cmd find
require_cmd head
require_cmd sed
require_cmd tr
require_cmd date
require_cmd mktemp
require_cmd wc
require_cmd basename
require_cmd dirname
require_cmd pwd
require_cmd cp
require_cmd mv

tmpfile() {
  mktemp "${TMPDIR:-/tmp}/daily-note-snapshot.XXXXXX" 2>/dev/null || printf '%s' "${TMPDIR:-/tmp}/daily-note-snapshot.$$"
}

emit_prefixed() {
  prefix=$1
  if [ -n "$prefix" ]; then
    sed "s/^/$prefix/"
  else
    cat
  fi
}

###############################################################################
# Args
###############################################################################

DRY_RUN=0
ALLOW_UNRESOLVED=0
ALLOW_ZERO_EMBEDS=0
embed_total=0
embed_resolved=0
embed_unresolved=0
NOTE=""

usage() {
  cat <<'EOF_USAGE' >&2
Usage: daily-note-snapshot.sh [-n|--dry-run] [--allow-unresolved] [--allow-zero-embeds] [PATH/TO/daily-note.md]

Replaces lines that are exactly an Obsidian embed: ![[...]]
- If PATH is omitted, defaults to yesterday's daily note in:
  "$VAULT_ROOT/${PERIODIC_NOTES_DIR:-Periodic Notes}/Daily Notes/YYYY-MM-DD.md"

- Override the default date with SNAPSHOT_DATE=YYYY-MM-DD

Options:
  -n, --dry-run            Write expanded note to "<note>.dryrun" (do not modify original)
  -a, --allow-unresolved   Do not fail (exit=1) if embeds are unresolved
      --allow-zero-embeds  Do not fail (exit=1) if zero embeds are found
  -h, --help               Show this help
EOF_USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    -n|--dry-run)
      DRY_RUN=1
      log_info "flag: dry run enabled"
      shift
      ;;
    -a|--allow-unresolved)
      ALLOW_UNRESOLVED=1
      shift
      ;;
    --allow-zero-embeds)
      ALLOW_ZERO_EMBEDS=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      log_error "unknown option: $1"
      usage
      exit 2
      ;;
    *)
      if [ -n "$NOTE" ]; then
        log_error "multiple note paths provided"
        usage
        exit 2
      fi
      NOTE=$1
      log_info "flag: explicit note path provided ($NOTE)"
      shift
      ;;
  esac
done

###############################################################################
# Resolve vault + note path
###############################################################################

vault_default=${VAULT_PATH:-$HOME/vaults/Main}
: "${VAULT_ROOT:=$vault_default}"

# Canonicalize VAULT_ROOT if possible (but don't require it to exist here)
case "$VAULT_ROOT" in
  /*) : ;;
  *)
    VAULT_ROOT=$(
      # shellcheck disable=SC1007
      CDPATH= cd "$VAULT_ROOT" 2>/dev/null && pwd -P
    ) || {
      log_error "failed to resolve VAULT_ROOT: $VAULT_ROOT"
      exit 10
    }
    ;;
esac

explicit_note=0
explicit_date=0

if [ -n "$NOTE" ]; then
  explicit_note=1
fi

if [ -n "${SNAPSHOT_DATE:-}" ]; then
  explicit_date=1
  case "$SNAPSHOT_DATE" in
    ????-??-??) : ;;
    *)
      log_error "SNAPSHOT_DATE must be YYYY-MM-DD: $SNAPSHOT_DATE"
      exit 2
      ;;
  esac
fi

if [ -z "$NOTE" ]; then
  PERIODIC_NOTES_DIR=${PERIODIC_NOTES_DIR:-"Periodic Notes"}
  DAILY_NOTE_DIR=${DAILY_NOTE_DIR:-"$VAULT_ROOT/$PERIODIC_NOTES_DIR/Daily Notes"}

  if [ "$explicit_date" -eq 1 ]; then
    target_date=$SNAPSHOT_DATE
    log_info "using SNAPSHOT_DATE override: $target_date"
  else
    target_date=$(dt_yesterday_local)
    log_info "no note path provided; defaulting to yesterday's date: $target_date"
  fi

  NOTE="$DAILY_NOTE_DIR/$target_date.md"
fi

log_info "resolved note argument to: $NOTE"

if [ ! -f "$NOTE" ]; then
  if [ "$explicit_note" -eq 1 ] || [ "$explicit_date" -eq 1 ]; then
    log_error "note not found: $NOTE"
    exit 1
  fi

  log_warn "default snapshot target not found; nothing to do: $NOTE"
  exit 0
fi

# Resolve NOTE to absolute canonical path
# shellcheck disable=SC1007
NOTE_DIR=$(CDPATH= cd -- "$(dirname -- "$NOTE")" && pwd -P)
NOTE_BASE=$(basename -- "$NOTE")
NOTE="$NOTE_DIR/$NOTE_BASE"

TMP="$NOTE.tmp"
BAK="$NOTE.bak"
TEST_NOTE="$NOTE.dryrun"

# Clean up temp file on exit
trap 'rm -f "$TMP"' 0 HUP INT TERM

log_info "vault root: $VAULT_ROOT"
log_info "note: $NOTE"
if [ "$DRY_RUN" -eq 1 ]; then
  log_info "mode: dry run (writing to $TEST_NOTE)"
else
  log_info "mode: replace note in place with backup $BAK"
fi

###############################################################################
# Embed expansion
###############################################################################

expand_embed() {
  link=$1
  line=$2
  prefix=${3:-}

  embed_total=$((embed_total + 1))
  log_info "processing embed: $link"

  # Strip alias: "path#heading|Alias" -> "path#heading"
  case "$link" in
    *'|'*) link_no_alias=${link%%'|'*} ;;
    *)     link_no_alias=$link ;;
  esac

  # Split into path and heading: "path#heading"
  case "$link_no_alias" in
    *'#'*)
      path=${link_no_alias%%'#'*}
      heading=${link_no_alias#*'#'}
      ;;
    *)
      path=$link_no_alias
      heading=
      ;;
  esac

  file=
  resolve_hint=

  # Directory aliases / logical prefixes. These may be provided by cron env
  # vars and are interpreted relative to VAULT_ROOT unless already absolute.
  PERIODIC_NOTES_DIR=${PERIODIC_NOTES_DIR:-"Periodic Notes"}
  SUBNOTES_DIR=${SUBNOTES_DIR:-"$PERIODIC_NOTES_DIR/Daily Notes/Subnotes"}
  DASHBOARDS_DIR=${DASHBOARDS_DIR:-"Dashboards"}
  DATA_NOTES_DIR=${DATA_NOTES_DIR:-"Data"}
  SLEEP_DATA_DIR=${SLEEP_DATA_DIR:-"$DATA_NOTES_DIR/Sleep Data"}
  SERVER_LOGS_DIR=${SERVER_LOGS_DIR:-"Server Logs"}

  qualify_dir() {
    case "$1" in
      /*) printf '%s\n' "$1" ;;
      *)  printf '%s/%s\n' "$VAULT_ROOT" "$1" ;;
    esac
  }

  PERIODIC_NOTES_DIR_ABS=$(qualify_dir "$PERIODIC_NOTES_DIR")
  SUBNOTES_DIR_ABS=$(qualify_dir "$SUBNOTES_DIR")
  DASHBOARDS_DIR_ABS=$(qualify_dir "$DASHBOARDS_DIR")
  DATA_NOTES_DIR_ABS=$(qualify_dir "$DATA_NOTES_DIR")
  SLEEP_DATA_DIR_ABS=$(qualify_dir "$SLEEP_DATA_DIR")
  SERVER_LOGS_DIR_ABS=$(qualify_dir "$SERVER_LOGS_DIR")

  normalized_path=$path
  normalized_base=

  case "$path" in
    "Periodic Notes/"*)
      normalized_base=$PERIODIC_NOTES_DIR_ABS
      normalized_path=${path#"Periodic Notes/"}
      ;;
    "Daily Notes/Subnotes/"*)
      normalized_base=$SUBNOTES_DIR_ABS
      normalized_path=${path#"Daily Notes/Subnotes/"}
      ;;
    "Subnotes/"*)
      normalized_base=$SUBNOTES_DIR_ABS
      normalized_path=${path#"Subnotes/"}
      ;;
    "Dashboards/"*)
      normalized_base=$DASHBOARDS_DIR_ABS
      normalized_path=${path#"Dashboards/"}
      ;;
    "Reference/Dashboards/"*)
      normalized_base=$DASHBOARDS_DIR_ABS
      normalized_path=${path#"Reference/Dashboards/"}
      ;;
    "Data/"*)
      normalized_base=$DATA_NOTES_DIR_ABS
      normalized_path=${path#"Data/"}
      ;;
    "Sleep Data/"*)
      normalized_base=$SLEEP_DATA_DIR_ABS
      normalized_path=${path#"Sleep Data/"}
      ;;
    "Server Logs/"*)
      normalized_base=$SERVER_LOGS_DIR_ABS
      normalized_path=${path#"Server Logs/"}
      ;;
  esac

  # Resolve path:
  # 1) Alias-normalized base (if recognized)
  # 2) Relative to the note's directory
  # 3) Relative to the vault root
  # For each, try with and without ".md".
  for base in ${normalized_base+"$normalized_base"} "$NOTE_DIR" "$VAULT_ROOT"; do
    [ -n "$base" ] || continue
    rel=$path
    [ "$base" = "$normalized_base" ] && rel=$normalized_path
    candidate=$base/$rel
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

  # If a logical prefix was recognized but direct resolution failed, attempt a
  # recursive basename search rooted under the mapped directory.
  if [ -z "$file" ] && [ -n "$normalized_base" ]; then
    leaf_name=$(basename -- "$normalized_path")
    log_info "attempting recursive search for $leaf_name under $normalized_base"
    found=$(
      find "$normalized_base" -type f \( -name "$leaf_name" -o -name "$leaf_name.md" \) -print 2>/dev/null | head -n 1 || :
    )
    if [ -n "$found" ]; then
      file=$found
      resolve_hint="recursive match under $normalized_base"
    fi
  fi

  # If path is bare name (no /), attempt a recursive search
  case "$path" in
    */*) : ;;
    *)
      if [ -z "$file" ]; then
        log_info "attempting recursive search for $path under $VAULT_ROOT"
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
    log_warn "embed not resolved (missing file?): $link"
    embed_unresolved=$((embed_unresolved + 1))
    printf '%s\n' "$line"
    return 0
  fi

  log_info "resolved embed to $file ($resolve_hint)"

  if [ -z "$heading" ]; then
    embed_resolved=$((embed_resolved + 1))
    emit_prefixed "$prefix" <"$file"
    return 0
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
          if (lvl <= section_level) exit
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
    END { if (!found) exit 1 }
  ' "$file" | emit_prefixed "$prefix"
  then
    log_warn "embed not resolved (missing heading): $link"
    embed_unresolved=$((embed_unresolved + 1))
    printf '%s\n' "$line"
    return 0
  fi

  log_info "expanded heading \"$heading\" from $file"
  embed_resolved=$((embed_resolved + 1))
  return 0
}

###############################################################################
# Process note
###############################################################################

: >"$TMP"

# Only replaces lines that are exactly an embed: ![[...]]
while IFS= read -r line; do
  trimmed=$(printf '%s' "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')

  # Extract any leading blockquote prefix (">", "> >", etc.)
  quote_prefix=$(printf '%s\n' "$trimmed" | sed -n 's/^\(\(>[[:space:]]*\)*\).*/\1/p')

  # Remove the quote prefix from the line
  stripped=${trimmed#"$quote_prefix"}

  # Remove optional heading markers (### etc)
  stripped=$(printf '%s\n' "$stripped" | sed 's/^#[#]*[[:space:]]*//')

  case "$stripped" in
    '![['*']]' )
      link=${stripped#'![['}
      link=${link%']]'}
      expand_embed "$link" "$line" "$quote_prefix" >>"$TMP"
      ;;
    * )
      printf '%s\n' "$line" >>"$TMP"
      ;;
  esac
done <"$NOTE"

log_info "embeds processed: $embed_total (resolved: $embed_resolved, unresolved: $embed_unresolved)"

###############################################################################
# Append completed tasks for the day
###############################################################################

# Snapshot date is already resolved earlier as target_date
snapshot_date=$target_date

# Resolve Combined Task List path
DATA_NOTES_DIR=${DATA_NOTES_DIR:-"00 - System/Data"}
combined_task_list="$VAULT_ROOT/$DATA_NOTES_DIR/Tasks/Combined Task List.md"

if [ -f "$combined_task_list" ]; then
  log_info "collecting completed tasks for $snapshot_date from $combined_task_list"

  completed_tmp=$(tmpfile)

  # Extract completed tasks matching the snapshot date
  awk -v d="$snapshot_date" '
    /^\- \[x\]/ && index($0, d) { print }
  ' "$combined_task_list" >"$completed_tmp"

  count=$(wc -l <"$completed_tmp" | tr -d ' ')

  {
    printf '\n## Completed Today\n\n'
    if [ "$count" -eq 0 ]; then
      printf '%s\n' "- No completed tasks recorded for this day."
    else
      cat "$completed_tmp"
    fi
    printf '\n'
  } >>"$TMP"

  rm -f "$completed_tmp"
else
  log_warn "combined task list not found: $combined_task_list"
fi

if [ "$embed_total" -eq 0 ]; then
  if [ "$ALLOW_ZERO_EMBEDS" -eq 1 ]; then
    log_warn "zero embeds found in note; leaving note unchanged: $NOTE"
    rm -f "$TMP"
    exit 0
  fi

  log_error "zero embeds found in note; refusing to report success: $NOTE"
  rm -f "$TMP"
  exit 1
fi

if [ "$DRY_RUN" -eq 1 ]; then
  mv "$TMP" "$TEST_NOTE"
  log_info "dry run: wrote expanded note to $TEST_NOTE"
  if [ -n "${COMMIT_LIST_FILE:-}" ]; then
    printf '%s\n' "$TEST_NOTE" >>"$COMMIT_LIST_FILE"
    log_debug "declared artifact: $TEST_NOTE"
  fi
else
  cp "$NOTE" "$BAK"
  mv "$TMP" "$NOTE"
  log_info "replaced $NOTE (backup at $BAK)"
  if [ -n "${COMMIT_LIST_FILE:-}" ]; then
    printf '%s\n' "$NOTE" >>"$COMMIT_LIST_FILE"
    printf '%s\n' "$BAK"  >>"$COMMIT_LIST_FILE"
    log_debug "declared artifacts: $NOTE, $BAK"
  fi
fi

if [ "$embed_unresolved" -gt 0 ] && [ "$ALLOW_UNRESOLVED" -eq 0 ]; then
  log_error "unresolved embeds detected: $embed_unresolved of $embed_total"
  exit 1
fi

exit 0
