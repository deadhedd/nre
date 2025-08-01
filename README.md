# Obsidian Note Tools

This repository contains shell scripts that help automate common tasks in an
[Obsidian](https://obsidian.md/) vault.

## `generate_daily_note.sh`

`generate_daily_note.sh` creates a Markdown file for today's date in your vault.
The script is provided as a template—edit the vault paths and note sections to
match your own workflow.

### Usage

```sh
export VAULT_PATH=/path/to/your/obsidian/vault
./generate_daily_note.sh
```

By default the note is placed inside `Daily Notes` within the specified vault.
Optional helper scripts in the `utils/` directory will be used if present to
populate sections such as a day plan or weekly goal.
