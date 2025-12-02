#!/bin/sh
# Summarize a sanitized monthly credit card CSV into markdown.
#
# Usage:
#   summarize-credit-card-month.sh 2025-11_nfcu-credit-card.csv
#
# Output:
#   Obsidian-ready markdown summary

set -eu

file="${1:?need sanitized credit card csv}"

month="$(basename "$file" | cut -c1-7)"

awk -F',' -v MONTH="$month" '
  NR == 1 { next }  # skip header

  {
    amount = $3
    kind   = $4
    merch  = $5

    if (kind == "purchase") {
      purchases += -amount   # amount is negative
    }

    if (kind == "payment") {
      payments += amount
    }

    # crude but effective: detect interest explicitly
    if (kind == "purchase" && merch ~ /INTEREST CHARGE/) {
      interest += -amount
    }

    net += amount
  }

  END {
    printf "## Credit Card Summary – %s\n\n", MONTH

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
' "$file"

