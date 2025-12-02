#!/bin/sh
# Summarize a sanitized monthly credit card CSV into an Obsidian markdown file
# and commit it using commit.sh.
#
# Usage:
#   summarize-credit-card-month.sh staging/finance/sanitized/2025-11-nfcu-credit-card.csv
#
# Outputs:
#   /home/obsidian/vaults/Main/Finance/Credit Card/2025-11 Credit Card.md
#
# Commit context:
#   context = finance
#   message = "Update credit card summary for YYYY-MM"

set -eu
PATH="/usr/local/bin:/usr/bin:/bin:${PATH:-}"

# ---- configuration ----
BASE_DIR="/home/obsidian"
VAULT_ROOT="${VAULT_PATH:-$BASE_DIR/vaults/Main}"
FINANCE_DIR="$VAULT_ROOT/Finance/Credit Card"

COMMIT_HELPER="/home/obsidian/commit.sh"  # adjust if needed
COMMIT_CONTEXT="finance"

# ---- input ----
csv="${1:?need sanitized credit card csv}"

month="$(basename "$csv" | cut -c1-7)"
note="$FINANCE_DIR/$month Credit Card.md"

mkdir -p "$FINANCE_DIR"

# ---- generate markdown ----
awk -F',' -v MONTH="$month" '
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
' "$csv" > "$note"

# ---- commit ----
if [ -x "$COMMIT_HELPER" ]; then
  "$COMMIT_HELPER" \
    -c "$COMMIT_CONTEXT" \
    "$VAULT_ROOT" \
    "Update credit card summary for $month" \
    "$note" \
  || printf 'WARN commit helper failed; file was written but not committed.\n' >&2
else
  printf 'WARN commit helper not found or not executable at %s\n' "$COMMIT_HELPER" >&2
fi
