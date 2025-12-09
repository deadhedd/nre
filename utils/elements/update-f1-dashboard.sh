#!/bin/sh
# utils/elements/update-f1-dashboard.sh — ensure and refresh the Formula 1 dashboard
# Author: deadhedd
# License: MIT
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd -P)


usage() {
  cat <<'EOF_USAGE'
Usage: update-f1-dashboard.sh --dashboard-path <path> [--content-script <path>] [--dry-run]

Options:
  --dashboard-path  Target Markdown file for the Formula 1 dashboard (required).
  --content-script  Script that produces dashboard content; defaults to f1-schedule-and-standings.sh.
  --dry-run         Skip writing to disk; log intended actions.
  --help            Show this message.
EOF_USAGE
}

dashboard_path=""
dry_run=0
content_script="$script_dir/f1-schedule-and-standings.sh"

while [ $# -gt 0 ]; do
  case "$1" in
    --dashboard-path)
      dashboard_path=${2:-}
      shift 2
      ;;
    --content-script)
      content_script=${2:-}
      shift 2
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
      printf 'ERR  %s\n' "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ -z "$dashboard_path" ]; then
  printf 'ERR  %s\n' "--dashboard-path is required" >&2
  usage >&2
  exit 2
fi

ensure_dir() {
  dir=$1
  if [ "$dry_run" -eq 1 ]; then
    printf 'INFO %s\n' "Dry run: would ensure directory exists: $dir"
    return 0
  fi

  mkdir -p "$dir"
}

write_output() {
  dest=$1

  if [ "$dry_run" -eq 1 ]; then
    printf 'INFO %s\n' "Dry run: would write dashboard content to $dest"
    cat >/dev/null
    return 0
  fi

  cat >"$dest"
}

printf 'INFO %s\n' "Formula 1 dashboard note: $dashboard_path"

dashboard_dir=$(dirname -- "$dashboard_path")
ensure_dir "$dashboard_dir"

if [ ! -f "$dashboard_path" ]; then
  if [ "$dry_run" -eq 1 ]; then
    printf 'WARN %s\n' "Dry run: Formula 1 dashboard missing; would create placeholder at $dashboard_path" >&2
  else
    printf 'WARN %s\n' "Formula 1 dashboard missing; creating placeholder at $dashboard_path" >&2
    cat >"$dashboard_path" <<'EOF_F1_DASHBOARD'
# 🏎️ Formula 1
_This dashboard was created automatically. Populate it with race data or widgets for embeds._
EOF_F1_DASHBOARD
  fi
else
  printf 'INFO %s\n' "Formula 1 dashboard present: $dashboard_path"
fi

if [ "$dry_run" -eq 1 ]; then
  printf 'INFO %s\n' "Dry run: skipping Formula 1 dashboard refresh"
  exit 0
fi

if [ ! -r "$content_script" ]; then
  printf 'WARN %s\n' "Formula 1 script not found: $content_script" >&2
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  printf 'WARN %s\n' "Skipping Formula 1 refresh; jq is unavailable" >&2
  exit 0
fi

printf 'INFO %s\n' "Refreshing Formula 1 dashboard content"
if output=$(sh "$content_script" 2>/dev/null); then
  printf '%s\n' "$output" | write_output "$dashboard_path"
  printf 'INFO %s\n' "Formula 1 dashboard updated: $dashboard_path"
else
  status=$?
  printf 'WARN %s\n' "Formula 1 dashboard refresh failed with exit code $status; leaving existing content" >&2
fi
