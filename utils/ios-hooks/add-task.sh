#!/bin/sh
# add_task.sh — append a task line to Combined Task List.md

set -eu

# Absolute vault root (adjust if your server stores this differently)
vault_root="/home/obsidian/vaults/Main"

inbox_dir="$vault_root/Inbox"
task_file="$inbox_dir/Combined Task List.md"

# Ensure the directory exists
if [ ! -d "$inbox_dir" ]; then
    mkdir -p "$inbox_dir"
fi

# Ensure the file exists
if [ ! -f "$task_file" ]; then
    : > "$task_file"   # create empty file
fi

# Check for input
if [ "$#" -eq 0 ]; then
    echo "ERROR: No task text provided." >&2
    exit 1
fi

# Combine all args into one string exactly as received
task_line="$*"

# Ensure it's not empty after trimming
# shellcheck disable=SC2001
task_clean=$(printf "%s" "$task_line" | sed 's/^[[:space:]]\+//; s/[[:space:]]\+$//')

if [ -z "$task_clean" ]; then
    echo "ERROR: Empty task text." >&2
    exit 1
fi

# Append with a newline
printf "%s\n" "$task_clean" >> "$task_file"

echo "OK: Task appended."

