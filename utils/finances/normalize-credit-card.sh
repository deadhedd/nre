#!/bin/sh
# Normalize raw credit-card CSV export into a canonical, signed-amount CSV.
# Usage:
#   normalize-credit-card.sh raw.csv [output.csv]
#
# Output columns:
#   date,posted,amount_cents,kind,merchant,category,card,source

set -eu

in="${1:?need input csv}"
out="${2:-credit-card.normalized.csv}"

tmp="$(mktemp)"

# Strip UTF-8 BOM if present on first line
# (your file has one on "Posting Date")
# The octal codes 357 273 277 are the BOM bytes.
sed '1s/^\xEF\xBB\xBF//' "$in" > "$tmp"

{
  # Header
  printf '%s\n' "date,posted,amount_cents,kind,merchant,category,card,source"

  awk -F',' '
    NR == 1 { next }  # skip original header

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

      # Determine sign from Credit/Debit
      # Debit  = money spent  -> negative
      # Credit = payment/refund -> positive
      sign = (indicator == "Debit") ? -1 : 1

      # Convert to cents as signed integer
      # Add 0.5 for rounding to nearest cent
      amount_num = amount + 0
      cents = int((amount_num * 100) + 0.5) * sign

      # Map type to kind
      kind = (type == "Payment") ? "payment" : "purchase"

      # Escape embedded double quotes for CSV
      gsub(/"/, "\"\"", desc)
      gsub(/"/, "\"\"", category)

      # Print normalized line
      printf "%s,%s,%d,%s,\"%s\",\"%s\",%s,credit-card\n",
             tdate, pdate, cents, kind, desc, category, card
    }
  ' "$tmp"
} > "$out"

rm -f "$tmp"

