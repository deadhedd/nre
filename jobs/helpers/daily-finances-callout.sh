#!/bin/sh
# lib/finances/daily-finances-callout.sh — Build finances callout for daily note
#
# Stdout: markdown callout (primary data)
# Stderr: diagnostics only (DEBUG/INFO/WARN/ERROR)
#
# Author: deadhedd
# License: MIT
# shellcheck shell=sh

set -eu

###############################################################################
# Logging (template-aligned; stderr only)
###############################################################################

log_debug() { printf '%s\n' "DEBUG: $*" >&2; }
log_info()  { printf '%s\n' "INFO: $*"  >&2; }
log_warn()  { printf '%s\n' "WARN: $*"  >&2; }
log_error() { printf '%s\n' "ERROR: $*" >&2; }

###############################################################################
# Environment hardening (cron-safe, deterministic)
###############################################################################

PATH=/usr/local/bin:/usr/bin:/bin
export PATH
LC_ALL=C
LANG=C
export LC_ALL LANG

###############################################################################
# Args
###############################################################################

year=${1:-}
month=${2:-}
day=${3:-}

usage() {
  log_error "Usage: $0 <year> <month> <day>"
}

if [ -z "$year" ] || [ -z "$month" ] || [ -z "$day" ]; then
  usage
  exit 2
fi

# Normalize numeric inputs (avoid octal issues with leading zeros)
if ! ty=$(printf '%d' "$year" 2>/dev/null); then
  usage
  exit 2
fi
if ! tm=$(printf '%d' "$month" 2>/dev/null); then
  usage
  exit 2
fi
if ! td=$(printf '%d' "$day" 2>/dev/null); then
  usage
  exit 2
fi

log_debug "Input date normalized: y=$ty m=$tm d=$td"

###############################################################################
# Helpers
###############################################################################

pad2() {
  if [ "$1" -lt 10 ]; then
    printf '0%d' "$1"
  else
    printf '%d' "$1"
  fi
}

ymd_key() {
  printf '%04d%02d%02d' "$1" "$2" "$3"
}

ym_key() {
  printf '%04d%02d' "$1" "$2"
}

###############################################################################
# Loan countdown builder
###############################################################################

build_loan_countdown_text() {
  # ---- Tunables ----
  payoff_y=2027
  payoff_m=12
  payoff_d=20

  log_debug "Loan payoff target: ${payoff_y}-${payoff_m}-${payoff_d}"

  months_base=$(( (payoff_y - ty) * 12 + (payoff_m - tm) ))

  today_key=$(ymd_key "$ty" "$tm" "$td")
  payoff_key=$(ymd_key "$payoff_y" "$payoff_m" "$payoff_d")

  if [ "$today_key" -gt "$payoff_key" ]; then
    months_left=0
  else
    if [ "$td" -le "$payoff_d" ]; then
      months_left=$(( months_base + 1 ))
    else
      months_left=$(( months_base ))
    fi
    [ "$months_left" -lt 0 ] && months_left=0
  fi

  # Next payment = next 20th on/after today
  np_y=$ty
  np_m=$tm
  if [ "$td" -gt 20 ]; then
    if [ "$np_m" -eq 12 ]; then
      np_m=1
      np_y=$(( np_y + 1 ))
    else
      np_m=$(( np_m + 1 ))
    fi
  fi

  if [ "$(ym_key "$np_y" "$np_m")" -gt "$(ym_key "$payoff_y" "$payoff_m")" ]; then
    payments_left=0
  else
    payments_left=$(( (payoff_y - np_y) * 12 + (payoff_m - np_m) + 1 ))
    [ "$payments_left" -lt 0 ] && payments_left=0
  fi

  next_payment_fmt=$(printf '%04d-%02d-%02d' "$np_y" "$np_m" 20)

  log_debug "Computed months_left=$months_left payments_left=$payments_left next=$next_payment_fmt"

  cat <<EOF_LC
### 🚗 Car Loan Payoff Countdown
| Months left | Payments left (20ths) | Next payment | Target payoff |
|-------------|-----------------------|--------------|---------------|
| ${months_left} | ${payments_left} | ${next_payment_fmt} | 2027-12-20 |
EOF_LC
}

###############################################################################
# Main
###############################################################################

log_info "Building daily finances callout"

loan_countdown_text=$(build_loan_countdown_text)

cat <<EOF
> [!abstract]+ 💰 Finances
> (this section should be an embed, but we need to configure a source note first)
>
$(printf '%s\n' "$loan_countdown_text" | sed 's/^/> /')
>
> ### 💳 Credit Card Payoff Countdown
> (sample data)
>
> | Months left | Payments left (20ths) | Next payment | Target payoff |
> |-------------|-----------------------|--------------|---------------|
> | 18 | 18 | 2026-03-20 | 2027-06-20 |
EOF

log_info "Finances callout generation complete"
