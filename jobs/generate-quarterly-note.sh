#!/bin/sh
# Generate a quarterly note markdown file based on the legacy Node implementation.
#
# Leaf job (wrapper required).
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
JOB_CADENCE=${JOB_CADENCE:-quarterly}
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
# Argument parsing (template scaffold; customized for quarterly notes)
###############################################################################

usage() {
  cat <<'EOF_USAGE'
Usage: generate-quarterly-note.sh [--output <path>] [--outdir <name>] [--dry-run] [--force]

Options:
  --output <path>   Absolute output file path (overrides --outdir default path).
  --outdir <name>   Subdirectory inside the vault. Defaults to "Periodic Notes/Quarterly Notes".
  --dry-run         Emit content to stdout instead of writing a file.
  --force           Overwrite existing files if present.
  --help            Show this message.
EOF_USAGE
}

output_path=""
dry_run=0
force=0

# Job-specific defaults
outdir="Periodic Notes/Quarterly Notes"

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

if [ -z "${VAULT_ROOT:-}" ]; then
  log_error "VAULT_ROOT not set (wrapper required)"
  exit 127
fi
artifact_root=$VAULT_ROOT

# Normalize outdir (trim leading/trailing slashes)
trimmed_outdir=$outdir
while [ "${trimmed_outdir#/}" != "$trimmed_outdir" ]; do trimmed_outdir=${trimmed_outdir#/}; done
while [ "${trimmed_outdir%/}" != "$trimmed_outdir" ]; do trimmed_outdir=${trimmed_outdir%/}; done

# Determine quarter tag (YYYY-Qn) for *current local quarter*.
tag=$(pr_quarter_tag_iso 2>/dev/null || printf '%s' "")
if [ -z "$tag" ]; then
  log_error "failed to determine current quarter (pr_quarter_tag_iso)"
  exit 127
fi

target_year=${tag%%-*}
target_quarter=${tag#*-Q}

# Basic quarter sanity
case "$target_quarter" in
  1|2|3|4) : ;;
  *) log_error "quarter must be between 1 and 4: Q$target_quarter"; exit 2 ;;
esac

# Compute prev/next quarter tags (simple quarter arithmetic)
prev_year=$target_year
prev_quarter=$((target_quarter - 1))
if [ "$prev_quarter" -lt 1 ]; then
  prev_quarter=4
  prev_year=$((target_year - 1))
fi

next_year=$target_year
next_quarter=$((target_quarter + 1))
if [ "$next_quarter" -gt 4 ]; then
  next_quarter=1
  next_year=$((target_year + 1))
fi

prev_tag="${prev_year}-Q${prev_quarter}"
next_tag="${next_year}-Q${next_quarter}"

prev_link="Q${prev_quarter} ${prev_year}"
next_link="Q${next_quarter} ${next_year}"

if [ -z "$output_path" ]; then
  # Default location inside vault
  if [ -n "$trimmed_outdir" ]; then
    result_ref="${artifact_root%/}/$trimmed_outdir/${tag}.md"
  else
    result_ref="${artifact_root%/}/${tag}.md"
  fi
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

# Atomic write helper for additional artifacts (and usable for result_ref if desired).
# Usage:
#   write_atomic_file "/absolute/path/to/file" <<'EOF'
#   content...
#   EOF
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

# Link targets should be vault-relative paths (no ".md" required in Obsidian)
if [ -n "$trimmed_outdir" ]; then
  link_prefix=$trimmed_outdir
else
  link_prefix=""
fi

generate_content() {
  if [ -n "$link_prefix" ]; then
    prev_target="${link_prefix%/}/${prev_tag}"
    next_target="${link_prefix%/}/${next_tag}"
  else
    prev_target="${prev_tag}"
    next_target="${next_tag}"
  fi

  cat <<EOF_NOTE
# ${tag}

- [[${prev_target}|${prev_link}]]
- [[${next_target}|${next_link}]]

## Cascading Tasks

\`\`\`tasks
not done
tag includes due/${tag}
\`\`\`

## Quarterly Checklist

-  Review yearly goals
-  Set quarterly priorities
-  Review financial plan
-  Plan major home or work projects
-  Schedule any needed health checkups
-  Clean out unnecessary files or papers

## Major Goals

## Key Projects

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

###############################################################################
# Write anchor artifact (atomic; contractual)
###############################################################################

# Use the template-standard atomic writer.
write_atomic_file "$result_ref" <<EOF_NOTE
$(generate_content)
EOF_NOTE

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
