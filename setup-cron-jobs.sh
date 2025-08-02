#!/bin/sh
# Configure and install cron jobs for obsidian-note-tools.

set -e

CONFIG_DIR="$HOME/.config/obsidian-note-tools"
CONFIG_FILE="$CONFIG_DIR/cron-config.json"
DRY_RUN=0

# Parse arguments
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      ;;
    *)
      echo "Usage: $0 [--dry-run]" >&2
      exit 1
      ;;
  esac
  shift
done

mkdir -p "$CONFIG_DIR"

# Load existing config if present
if [ -f "$CONFIG_FILE" ]; then
  if jq empty "$CONFIG_FILE" >/dev/null 2>&1; then
    EXISTING_CONFIG=$(cat "$CONFIG_FILE")
  else
    echo "Warning: ignoring invalid config file at $CONFIG_FILE" >&2
    EXISTING_CONFIG='[]'
  fi
else
  EXISTING_CONFIG='[]'
fi

# Helper to get config for a script
get_config() {
  script="$1"
  echo "$EXISTING_CONFIG" | jq -c --arg script "$script" '.[] | select(.script == $script)'
}

# Validate cron expression using crontab -n if available
validate_cron() {
  expr="$1"
  if command -v crontab >/dev/null 2>&1; then
    if crontab -n /dev/null 2>/dev/null; then
      tmp=$(mktemp)
      printf '%s echo test\n' "$expr" > "$tmp"
      if ! crontab -n "$tmp" >/dev/null 2>&1; then
        rm -f "$tmp"
        echo "Invalid cron expression." >&2
        return 1
      fi
      rm -f "$tmp"
    fi
  else
    echo "Warning: crontab command not found; skipping validation." >&2
  fi
  return 0
}

# Discover scripts
SCRIPT_CANDIDATES=""
for dir in . ./scripts; do
  if [ -d "$dir" ]; then
    find "$dir" -maxdepth 1 -type f -name '*.sh' 2>/dev/null
  fi
done | sort -u > /tmp/obsidian_scripts.list

SCRIPT_CANDIDATES=$(cat /tmp/obsidian_scripts.list)
rm -f /tmp/obsidian_scripts.list

# Selection loop
SELECTED_SCRIPTS=""
while :; do
  i=1
  echo "Available scripts:" >&2
  for s in $SCRIPT_CANDIDATES; do
    echo "  $i) $s" >&2
    i=$((i+1))
  done
  echo "  m) Enter path manually" >&2
  echo "  q) Done" >&2
  printf 'Select script: ' >&2
  read ans || exit 1
  [ -z "$ans" ] && break
  case "$ans" in
    q|Q)
      break
      ;;
    m|M)
      printf 'Enter full path: ' >&2
      read manual || exit 1
      if [ -n "$manual" ]; then
        if [ -z "$SELECTED_SCRIPTS" ]; then
          SELECTED_SCRIPTS="$manual"
        else
          SELECTED_SCRIPTS="$SELECTED_SCRIPTS\n$manual"
        fi
      fi

      ;;
    *)
      idx=1
      chosen=""
      for s in $SCRIPT_CANDIDATES; do
        if [ "$idx" = "$ans" ]; then
          chosen="$s"
          break
        fi
        idx=$((idx+1))
      done
      if [ -n "$chosen" ]; then
        if [ -z "$SELECTED_SCRIPTS" ]; then
          SELECTED_SCRIPTS="$chosen"
        else
          SELECTED_SCRIPTS="$SELECTED_SCRIPTS\n$chosen"
        fi
      else
        echo "Invalid selection." >&2
      fi
      ;;
  esac
done

# Remove leading newlines
SELECTED_SCRIPTS=$(printf '%s' "$SELECTED_SCRIPTS" | sed '/^$/d')

# Configuration for each selected script
JOB_SCRIPTS=""
JOB_SCHEDULES=""
JOB_ENABLED=""

for script in $(printf '%s' "$SELECTED_SCRIPTS" | sed '/^$/d'); do
  if [ ! -f "$script" ]; then
    echo "Skipping missing script: $script" >&2
    continue
  fi
  if [ ! -x "$script" ]; then
    printf '%s is not executable. Make executable? (y/N): ' "$script" >&2
    read make_exe
    case "$make_exe" in
      y|Y)
        chmod +x "$script" || continue
        ;;
      *)
        echo "Skipping $script" >&2
        continue
        ;;
    esac
  fi

  config=$(get_config "$script")
  current_schedule=$(echo "$config" | jq -r '.schedule // ""' 2>/dev/null)
  current_enabled=$(echo "$config" | jq -r '.enabled // true' 2>/dev/null)

  echo "Configuring $script" >&2
  if [ "$current_enabled" = "false" ]; then
    echo "Currently disabled." >&2
  fi
  if [ -n "$current_schedule" ]; then
    echo "Current schedule: $current_schedule" >&2
  fi

  printf 'Choose schedule: [1] daily, [2] hourly, [3] weekly, [4] custom, [d] disable: ' >&2
  read choice

  enabled=true
  case "$choice" in
    1)
      printf 'Run at (HH:MM, 24h): ' >&2
      read time
      hour=${time%:*}
      minute=${time#*:}
      schedule="$minute $hour * * *"
      ;;
    2)
      printf 'Minute of hour (0-59): ' >&2
      read minute
      schedule="$minute * * * *"
      ;;
    3)
      printf 'Day of week (0-6, 0=Sun): ' >&2
      read dow
      printf 'Time (HH:MM): ' >&2
      read time
      hour=${time%:*}
      minute=${time#*:}
      schedule="$minute $hour * * $dow"
      ;;
    4)
      printf 'Enter cron expression: ' >&2
      read schedule
      ;;
    d|D)
      enabled=false
      schedule="$current_schedule"
      ;;
    *)
      if [ -n "$current_schedule" ]; then
        schedule="$current_schedule"
        enabled="$current_enabled"
      else
        echo "No schedule provided; skipping." >&2
        continue
      fi
      ;;
  esac

  if [ "$enabled" = "true" ]; then
    if ! validate_cron "$schedule"; then
      echo "Skipping $script due to invalid schedule." >&2
      continue
    fi
  fi

  if [ -z "$JOB_SCRIPTS" ]; then
    JOB_SCRIPTS="$script"
    JOB_SCHEDULES="$schedule"
    JOB_ENABLED="$enabled"
  else
    JOB_SCRIPTS="$JOB_SCRIPTS\n$script"
    JOB_SCHEDULES="$JOB_SCHEDULES\n$schedule"
    JOB_ENABLED="$JOB_ENABLED\n$enabled"
  fi
done

# Build preview and config
printf '\nProposed cron jobs:\n'
i=1
config_json=""

for script in $(printf '%s' "$JOB_SCRIPTS" | sed '/^$/d'); do
  schedule=$(printf '%s' "$JOB_SCHEDULES" | sed -n "${i}p")
  enabled=$(printf '%s' "$JOB_ENABLED" | sed -n "${i}p")
  printf '  %s %s -> %s\n' "$schedule" "$script" "$enabled"
  entry=$(jq -nc --arg s "$script" --arg sch "$schedule" --argjson en "$enabled" '{script:$s,schedule:$sch,enabled:$en}')
  config_json="$config_json$entry,"
  i=$((i+1))
done

config_json="[$(printf '%s' "$config_json" | sed 's/,$//')]"

# Save config
printf '%s\n' "$config_json" > "$CONFIG_FILE"

echo "Configuration written to $CONFIG_FILE" >&2

# Prepare crontab lines
CRONTAB_LINES=""
i=1
for script in $(printf '%s' "$JOB_SCRIPTS" | sed '/^$/d'); do
  schedule=$(printf '%s' "$JOB_SCHEDULES" | sed -n "${i}p")
  enabled=$(printf '%s' "$JOB_ENABLED" | sed -n "${i}p")
  name=$(basename "$script")
  if [ "$enabled" = "true" ]; then
    CRONTAB_LINES="$CRONTAB_LINES\n$schedule $script # obsidian-note-tools:$name"
  fi
  i=$((i+1))
done
CRONTAB_LINES=$(printf '%s' "$CRONTAB_LINES" | sed '/^$/d')

# Display preview
printf '\n%s\n' "$CRONTAB_LINES"

if [ "$DRY_RUN" -eq 1 ]; then
  echo "Dry run: not installing crontab." >&2
  exit 0
fi

if command -v crontab >/dev/null 2>&1; then
  existing=$(crontab -l 2>/dev/null || true)
  filtered=$(printf '%s\n' "$existing" | sed '/# obsidian-note-tools:/d')
  tmp=$(mktemp)
  printf '%s\n' "$filtered" > "$tmp"
  if [ -n "$CRONTAB_LINES" ]; then
    printf '%s\n' "$CRONTAB_LINES" >> "$tmp"
  fi
  crontab "$tmp"
  rm -f "$tmp"
  echo "Crontab updated." >&2
else
  echo "crontab command not found; cannot install cron jobs." >&2
fi
