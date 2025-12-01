#!/bin/sh
# Normalize raw Chase credit-card CSV export into a canonical, signed-amount CSV.
#
# Directory layout assumed:
#   BASE_DIR=/home/obsidian
#   RAW:      $BASE_DIR/inbox/finance/raw
#   SANITIZED:$BASE_DIR/staging/finance/sanitized
#
# Usage examples:
#   # 1) Input as basename (looked up in RAW), output as basename (written to SANITIZED):
#   normalize-credit-card.sh \
#     2025-03-01_chase_credit_txns_2025-02-01_to_2025-02-28.csv \
#     2025-02_chase_credit.csv
#
#   # 2) Full paths (no directory magic, exact control):
#   normalize-credit-card.sh \
#     /home/obsidian/inbox/finance/raw/2025-03-01_chase_credit_txns_2025-02-01_to_2025-02-28.csv \
#     /home/obsidian/staging/finance/sanitized/2025-02_chase_credit.csv
#
# Output columns (normalized):
#   date,posted,amount_cents,kind,merchant,category,card,source
#
# Notes:
#   - amount_cents is signed: purchases (Debit) are negative, payments (Credit) are positive.
#   - kind is "purchase" or "payment".
#   - source is literal "credit-card".

set -eu

BASE_DIR="/home/obsidian"
RAW_DIR="$BASE_DIR/inbox/finance/raw"
SANITIZED_DIR="$BASE_DIR/staging/finance/sanitized"

in_arg="${1:?need input csv (basename or full path)}"
out_arg="${2:?need output sanitized filename (basename or full path)}"

# Resolve input path
case "$in_arg" in
  /*) in="$in_arg" ;;
  *)  in="$RAW_DIR/$in_arg" ;;
esac

# Resolve output path
case "$out_arg" in
  /*) out="$out_arg" ;;
  *)  out="$SANITIZED_DIR/$out_arg" ;;
esac

tmp="$(mktemp)"

# We don’t bother stripping BOM; we skip header row entirely in awk,
# so any BOM lives only on that header line.
cp "$in" "$tmp"

{
  # Header for normalized file
  printf '%s\n' "date,posted,amount_cents,kind,merchant,category,card,source"

  awk -F',' '
    NR == 1 { next }  # skip original header line

    {
      posting   = $1   # Posting Date (MM/DD/YYYY)
      trans     = $2   # Transaction Date (MM/DD/YYYY)
      amount    = $3   # e.g. 21.79
      indicator = $4   # "Debit" or "Credit"
      type      = $5   # "Purchase" or "Payment"
      desc      = $11  # Description
      category  = $12  # Category
      card      = $14  # Card Ending

      # Convert MM/DD/YYYY -> YYYY-MM-DD for transaction date
      n = split(trans, td, "/")
      if (n == 3) {
        tdate = td[3] "-" sprintf("%02d", td[1]) "-" sprintf("%02d", td[2])
      } else {
        tdate = trans
      }

      # Convert MM/DD/YYYY -> YYYY-MM-DD for posting date
      n = split(posting, pd, "/")
      if (n == 3) {
        pdate = pd[3] "-" sprintf("%02d", pd[1]) "-" sprintf("%02d", pd[2])
      } else {
        pdate = posting
      }

      # Debit  = money spent    -> negative
      # Credit = payment/refund -> positive
      sign = (indicator == "Debit") ? -1 : 1

      # Convert to signed integer cents
      amount_num = amount + 0
      cents = int((amount_num * 100) + 0.5) * sign

      # Map type to kind
      kind = (type == "Payment") ? "payment" : "purchase"

      # Escape embedded double quotes for CSV (defensive)
      gsub(/"/, "\"\"", desc)
      gsub(/"/, "\"\"", category)

      printf "%s,%s,%d,%s,\"%s\",\"%s\",%s,credit-card\n",
             tdate, pdate, cents, kind, desc, category, card
    }
  ' "$tmp"
} > "$out"

rm -f "$tmp"
