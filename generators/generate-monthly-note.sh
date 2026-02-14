#!/bin/sh
# jobs/generate-monthly-note.sh
# Generate a monthly note markdown file equivalent to the legacy Node script.
#
# Leaf job (wrapper required).
#
# Version: 1.0
# Status: contract-aligned (leaf template)
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
script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)

# C1 bootstrap rule: wrapper location is assumed stable *relative to this file*
# for the initial self-wrap hop only. Once wrapped, REPO_ROOT (exported by the
# wrapper) becomes the source of truth for repo-relative paths.
wrap="$script_dir/../engine/wrap.sh"

# Prefer passing an absolute script path to the wrapper for sturdiness.
case "$0" in
  /*) script_path=$0 ;;
  *)  script_path=$script_dir/${0##*/} ;;
esac

# Canonicalize the final script path to avoid surprises (symlinks/cwd oddities).
script_path=$(
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
JOB_CADENCE=monthly
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
periods_lib=$lib_dir/periods.sh
datetime_lib=$lib_dir/datetime.sh

if [ ! -r "$periods_lib" ]; then
  log_error "periods lib not found/readable: $periods_lib"
  exit 127
fi
# shellcheck source=/dev/null
. "$periods_lib" || {
  log_error "failed to source periods lib: $periods_lib"
  exit 127
}

if [ ! -r "$datetime_lib" ]; then
  log_error "datetime lib not found/readable: $datetime_lib"
  exit 127
fi
# shellcheck source=/dev/null
. "$datetime_lib" || {
  log_error "failed to source datetime lib: $datetime_lib"
  exit 127
}

###############################################################################
# Argument parsing (template baseline; customize minimally)
###############################################################################
usage() {
  cat <<'EOF_USAGE'
Usage: generate-monthly-note.sh [--output <path>] [--dry-run] [--force]

Options:
  --output <path>   Output file path (absolute). If omitted, defaults to:
                    $VAULT_ROOT/Periodic Notes/Monthly Notes/YYYY-MM.md
  --dry-run         Emit content to stdout instead of writing a file.
  --force           Overwrite existing files if present.
  --help            Show this message.
EOF_USAGE
}

output_path=""
dry_run=0
force=0

while [ $# -gt 0 ]; do
  case "$1" in
    --output)
      [ $# -ge 2 ] || { printf 'ERROR: missing value for --output\n' >&2; usage >&2; exit 2; }
      output_path=$2
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
      printf 'ERROR: unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

###############################################################################
# Job logic
###############################################################################

# Contract: artifact root must be provided by wrapper.
if [ -z "${VAULT_ROOT:-}" ]; then
  log_error "VAULT_ROOT not set (wrapper required)"
  exit 127
fi
artifact_root=$VAULT_ROOT

# Compute current/prev/next month tags via periods.sh
month_tag=$(pr_month_tag_current) || { log_error "failed to compute current month tag"; exit 1; }
prev_tag=$(pr_month_tag_prev) || { log_error "failed to compute prev month tag"; exit 1; }
next_tag=$(pr_month_tag_next) || { log_error "failed to compute next month tag"; exit 1; }

# Derive year + month number (for title)
today=$(dt_today_local) || { log_error "failed to compute dt_today_local"; exit 1; }
set -- $(dt_date_parts "$today") || { log_error "failed to compute dt_date_parts: $today"; exit 1; }
year=$1
month=$2

month_name_en() {
  case "$1" in
    01) printf 'January' ;;
    02) printf 'February' ;;
    03) printf 'March' ;;
    04) printf 'April' ;;
    05) printf 'May' ;;
    06) printf 'June' ;;
    07) printf 'July' ;;
    08) printf 'August' ;;
    09) printf 'September' ;;
    10) printf 'October' ;;
    11) printf 'November' ;;
    12) printf 'December' ;;
    *)  printf '%s' "$1" ;;
  esac
}

month_name=$(month_name_en "$month")

# Compute result_ref
if [ -z "$output_path" ]; then
  result_ref="$artifact_root/Periodic Notes/Monthly Notes/${month_tag}.md"
else
  case "$output_path" in
    */)
      log_error "internal: --output ends with '/': $output_path"
      exit 2
      ;;
  esac
  case "$output_path" in
    /*) result_ref="$output_path" ;;
    *)  log_error "--output must be an absolute path: $output_path"; exit 2 ;;
  esac
fi

if [ -f "$result_ref" ] && [ "$force" -ne 1 ]; then
  log_error "refusing to overwrite existing file: $result_ref (use --force)"
  exit 1
fi

generate_content() {
  cat <<EOF_NOTE
# ${month_name} ${year}

- [[Periodic Notes/Monthly Notes/${prev_tag}|${prev_tag}]]
- [[Periodic Notes/Monthly Notes/${next_tag}|${next_tag}]]

## Cascading Tasks

\`\`\`tasks
not done
tag includes due/${month_tag}
\`\`\`

## Monthly Checklist

-  Check home maintenance tasks
-  Plan major goals for next month
- [ ] Clean out the fridge
- [ ] Order Johnie's inhaler
- [ ] Finance review

## budget

### Regular expenses:
##### Essentials:
- Garbage: 70 (Feb, May, Aug, Nov)
- Internet: 45 (Monthly)
- Electricity: 120-300 (Monthly)
- Car Payment: 616 (monthly)
- Car insurance 1750 (Jul, Nov)
**Total**: 781-2781
##### Non-essentials:
- Chatgpt: 22 (Monthly)
- YT Premium: 25 (Monthly)
- Audible 18 (Bi-monthly (odd))
- Patreon: 4 (Monthly)
- Apple Music: 11 (Monthly)
- Fitbod: 80 (Yearly (Oct))
- itunes match: 25 (Yearly (Jun))
- F1TV: 85 (Jul)
**Total**: 62-227

##### **Total Regular Expenses:
- 843-3008
##### Income:
(~1400 expected)
- (###)
##### Expenses:
- (###)
##### Net:
- (###)

## Goals

## Review

- What went well:

- What didn’t:

- Lessons learned:

## Notes
EOF_NOTE
}

if [ "$dry_run" -eq 1 ]; then
  if [ -n "$output_path" ]; then
    log_warn "--dry-run ignores --output: $output_path"
  fi
  if [ "$force" -eq 1 ]; then
    log_warn "--dry-run ignores --force"
  fi
  generate_content
  exit 0
fi

# Write anchor artifact atomically (template pattern)
primary_parent=${result_ref%/*}
if ! mkdir -p "$primary_parent"; then
  log_error "failed to create artifact directory: $primary_parent"
  exit 1
fi

tmp="${primary_parent}/${result_ref##*/}.tmp.$$"
cleanup_tmp() {
  [ -n "${tmp:-}" ] && [ -f "$tmp" ] && rm -f "$tmp"
}
trap cleanup_tmp HUP INT TERM 0

if ! generate_content >"$tmp"; then
  log_error "failed to write temp artifact: $tmp"
  exit 1
fi
if ! mv "$tmp" "$result_ref"; then
  log_error "failed to finalize artifact (mv): $tmp -> $result_ref"
  exit 1
fi

tmp=""
trap - HUP INT TERM 0

# Commit registration (contractual)
if [ -n "${COMMIT_LIST_FILE:-}" ]; then
  if ! printf '%s\n' "$result_ref" >>"$COMMIT_LIST_FILE" 2>/dev/null; then
    log_warn "failed to append to COMMIT_LIST_FILE: $COMMIT_LIST_FILE"
  fi
fi

log_info "Produced artifact: $result_ref"
exit 0
