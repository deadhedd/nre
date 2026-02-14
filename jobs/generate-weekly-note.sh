#!/bin/sh
# jobs/generate-weekly-note.sh — Generate a weekly note (contract-aligned leaf job)
#
# Leaf job (wrapper required)
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
# POSIX note: this resolves directory via cd+pwd; basename is preserved.
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

# engine/wrap.sh owns JOB_WRAP_ACTIVE; leaf does not set it.
if [ "${JOB_WRAP_ACTIVE:-0}" != "1" ]; then
  if [ ! -x "$wrap" ]; then
    log_error "leaf wrap: wrapper not found/executable: $wrap"
    exit 127
  fi
  log_info "leaf wrap: exec wrapper: $wrap"
  exec "$wrap" "$script_path" ${1+"$@"}
else
  # Wrapped execution path; informational only.
  log_debug "leaf wrap: wrapper active; executing leaf"
fi

###############################################################################
# Cadence declaration (contract-required)
###############################################################################
JOB_CADENCE=${JOB_CADENCE:-weekly}
log_info "cadence=$JOB_CADENCE"

###############################################################################
# Engine libs (wrapped path only)
###############################################################################

# Wrapper contract: REPO_ROOT is provided (absolute) once wrapped.
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

# Period helpers (days / weeks / months / quarters)
if [ ! -r "$periods_lib" ]; then
  log_error "periods lib not found/readable: $periods_lib"
  exit 127
fi
# shellcheck source=/dev/null
. "$periods_lib" || {
  log_error "failed to source periods lib: $periods_lib"
  exit 127
}

# Datetime helpers (local-time only)
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
# Argument parsing (customized for weekly note job)
###############################################################################

usage() {
  cat <<'EOF_USAGE'
Usage: generate-weekly-note.sh [--output <path>] [--outdir <name>] [--dry-run] [--force]

Options:
  --output <path>   Output file path (absolute). Overrides --outdir anchoring.
  --outdir <name>   Subdirectory inside the vault. Defaults to "Periodic Notes/Weekly Notes".
  --dry-run         Emit content to stdout instead of writing a file.
  --force           Overwrite existing files if present.
  --help            Show this message.
EOF_USAGE
}

output_path=""
dry_run=0
force=0

outdir="Periodic Notes/Weekly Notes"

while [ $# -gt 0 ]; do
  case "$1" in
    --output)
      [ $# -ge 2 ] || { printf 'ERROR: missing value for --output\n' >&2; usage >&2; exit 2; }
      output_path=$2
      shift 2
      ;;
    --outdir)
      [ $# -ge 2 ] || { printf 'ERROR: missing value for --outdir\n' >&2; usage >&2; exit 2; }
      outdir=$2
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

###############################################################################
# Compute anchor artifact path (result_ref)
###############################################################################

# Artifact root:
# - Must be provided by wrapper.
if [ -z "${VAULT_ROOT:-}" ]; then
  log_error "VAULT_ROOT not set (wrapper required)"
  exit 127
fi
artifact_root=$VAULT_ROOT

# Weekly note is always for "current week" (local), derived from periods lib.
# No stderr suppression: if libs emit anything, we want it in the log.
date_arg=$(pr_today)

# Derive week navigation tags (prev/current/next) for "today".
week_nav=$(pr_week_nav_tags_for_date "$date_arg") || {
  log_error "failed to compute week navigation tags for date: $date_arg"
  exit 2
}
set -- $week_nav
prev_week_tag=$1
iso_week_tag=$2
next_week_tag=$3
set --

# Normalize outdir (strip leading/trailing slashes)
trimmed_outdir=$outdir
while [ "${trimmed_outdir#/}" != "$trimmed_outdir" ]; do trimmed_outdir=${trimmed_outdir#/}; done
while [ "${trimmed_outdir%/}" != "$trimmed_outdir" ]; do trimmed_outdir=${trimmed_outdir%/}; done

# Compute result_ref (period-based unless --output)
if [ -z "$output_path" ]; then
  if [ -n "$trimmed_outdir" ]; then
    note_dir="$artifact_root/$trimmed_outdir"
  else
    note_dir="$artifact_root"
  fi
  result_ref="${note_dir%/}/${iso_week_tag}.md"
else
  case "$output_path" in
    */)
      log_error "internal: --output ends with '/': $output_path"
      exit 2
      ;;
  esac
  # Contract: --output must be an absolute path.
  case "$output_path" in
    /*)
      result_ref="$output_path"
      ;;
    *)
      log_error "--output must be an absolute path: $output_path"
      exit 2
      ;;
  esac
fi

if [ -z "$result_ref" ]; then
  log_error "internal: result_ref empty"
  exit 127
fi
case "$result_ref" in
  */) log_error "internal: result_ref ends with '/': $result_ref"; exit 2 ;;
esac

###############################################################################
# Helpers (template-standard; optional use by jobs)
###############################################################################

write_atomic_file() {
  _dest=$1
  _tmp_dir=${_dest%/*}
  _tmp="${_tmp_dir}/${_dest##*/}.tmp.$$"

  if ! mkdir -p "$_tmp_dir"; then
    log_error "failed to create artifact directory: $_tmp_dir"
    exit 1
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
    log_error "failed atomic write: $_dest"
    rm -f "$_tmp" 2>/dev/null || true
    exit 1
  }
}

###############################################################################
# Overwrite guards (external boundary: filesystem state)
###############################################################################

if [ -f "$result_ref" ] && [ "$force" -ne 1 ]; then
  log_error "refusing to overwrite existing file: $result_ref (use --force)"
  exit 1
fi

generate_content() {
  link_prefix=$trimmed_outdir
  if [ -n "$link_prefix" ]; then
    link_prefix="${link_prefix%/}/"
  fi

  cat <<EOF_CONTENT
# Week ${iso_week_tag}

<<[[${link_prefix}${prev_week_tag}|${prev_week_tag}]] || [[${link_prefix}${next_week_tag}|${next_week_tag}]]>>

## 🎯 Weekly Goal

**Goal:**  
\`weekly_goal:: \`

**Why it matters:**  
> One or two sentences at most.

**Definition of Done:**
- [ ] Clear outcome  
- [ ] Observable result  

---

## 📋 Weekly Checklist
(These need to be incorporated into the cascading tasks system)
- [ ] Weekly Review
- [ ] Plan Weekly Goal
- [ ] Review Calendar
- [ ] Prep Meals / Ingredients

---

## 🧩 Cascading Tasks

\`\`\`tasks
not done
tag includes due/${iso_week_tag}
\`\`\`

## Links

[[Weekly Routine]]
[[Weekly Goal Queue]]
[[Weekly Note Template]]

EOF_CONTENT
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

###############################################################################
# Write anchor artifact (atomic; contractual)
###############################################################################

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

###############################################################################
# Commit registration (contractual; multi-artifact)
###############################################################################

if [ -n "${COMMIT_LIST_FILE:-}" ]; then
  if ! printf '%s\n' "$result_ref" >>"$COMMIT_LIST_FILE" 2>/dev/null; then
    log_warn "failed to append to COMMIT_LIST_FILE: $COMMIT_LIST_FILE"
  fi
fi

###############################################################################
# Diagnostics
###############################################################################

log_info "Produced artifact: $result_ref"

exit 0
