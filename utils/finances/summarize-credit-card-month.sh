#!/bin/sh
# Summarize a sanitized monthly credit card CSV into an Obsidian markdown file.
#
# Usage:
#   summarize-credit-card-month.sh staging/finance/sanitized/2025-11-nfcu-credit-card.csv
#
# Outputs:
#   /home/obsidian/vaults/Main/Finance/Credit Card/2025-11 Credit Card.md
#
set -eu
PATH="/usr/local/bin:/usr/bin:/bin:${PATH:-}"

log_info() { printf 'INFO %s\n' "$*"; }
log_err()  { printf 'ERR %s\n'  "$*"; }

# ---- configuration ----
BASE_DIR="/home/obsidian"
VAULT_ROOT="${VAULT_PATH:-$BASE_DIR/vaults/Main}"
FINANCE_DIR="$VAULT_ROOT/Finance/Credit Card"

# ---- input ----
csv="${1:?need sanitized credit card csv}"

month="$(basename "$csv" | cut -c1-7)"
note="$FINANCE_DIR/$month Credit Card.md"

log_info "start summarize-credit-card-month csv=$csv note=$note"

if [ ! -r "$csv" ]; then
  log_err "csv not readable: $csv"
  exit 1
fi

if [ ! -s "$csv" ]; then
  log_err "csv is empty: $csv"
  exit 1
fi

if ! awk 'NR>1 { exit 0 } END { exit NR>1 ? 0 : 1 }' "$csv" >/dev/null 2>&1; then
  log_err "csv has no data rows: $csv"
  exit 1
fi

mkdir -p "$FINANCE_DIR"

# ---- generate markdown ----
if ! awk -F',' -v MONTH="$month" '
  NR == 1 { next }  # skip header

  {
    amount = $3
    kind   = $4
    merch  = $5

    if (kind == "purchase") {
      purchases += -amount
    }

    if (kind == "payment") {
      payments += amount
    }

    if (kind == "purchase" && merch ~ /INTEREST CHARGE/) {
      interest += -amount
    }

    net += amount
  }

  END {
    printf "# Credit Card – %s\n\n", MONTH

    printf "## Monthly Summary\n\n"
    printf "- Purchases: **$%.2f**\n", purchases / 100
    printf "- Payments:  **$%.2f**\n", payments / 100

    if (interest > 0) {
      printf "- Interest:  **$%.2f**\n", interest / 100
    }

    printf "- Net Change: **$%.2f**\n\n", net / 100

    if (net > 0) {
      printf "> ✅ Balance decreased this month.\n"
    } else if (net < 0) {
      printf "> ❌ Balance increased this month.\n"
    } else {
      printf "> ⚖️ No net change.\n"
    }
  }
' "$csv" > "$note"; then
  log_err "failed to summarize csv: $csv"
  exit 1
fi

log_info "wrote summary note=$note"
