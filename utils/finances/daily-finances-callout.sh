#!/bin/sh
# utils/finances/daily-finances-callout.sh — Build finances callout for daily note
# Author: deadhedd
# License: MIT
set -eu

year=${1:-}
month=${2:-}
day=${3:-}

if [ -z "$year" ] || [ -z "$month" ] || [ -z "$day" ]; then
  printf 'Usage: %s <year> <month> <day>\n' "$0" >&2
  exit 2
fi

pad2() {
  if [ "$1" -lt 10 ]; then
    printf '0%d' "$1"
  else
    printf '%d' "$1"
  fi
}

build_loan_countdown_text() {
  payoff_y=2027
  payoff_m=12
  payoff_d=20

  ty=$year
  tm=$month
  td=$day

  months_base=$(( (payoff_y - ty)*12 + (payoff_m - tm) ))

  if [ "$ty$(pad2 "$tm")$(pad2 "$td")" -gt "$payoff_y$(pad2 "$payoff_m")$(pad2 "$payoff_d")" ]; then
    months_left=0
  else
    if [ "$td" -le "$payoff_d" ]; then
      months_left=$(( months_base + 1 ))
    else
      months_left=$(( months_base ))
    fi
    [ "$months_left" -lt 0 ] && months_left=0
  fi

  np_y=$ty
  np_m=$tm
  np_d=20
  if [ "$td" -gt 20 ]; then
    if [ "$np_m" -eq 12 ]; then
      np_m=1
      np_y=$(( np_y + 1 ))
    else
      np_m=$(( np_m + 1 ))
    fi
  fi

  if [ "$np_y$(pad2 "$np_m")" -gt "$payoff_y$(pad2 "$payoff_m")" ]; then
    payments_left=0
  else
    payments_left=$(( (payoff_y - np_y)*12 + (payoff_m - np_m) + 1 ))
    [ "$payments_left" -lt 0 ] && payments_left=0
  fi

  next_payment_fmt=$(printf '%04d-%02d-%02d' "$np_y" "$np_m" 20)

  cat <<EOF_LC
### 🚗 Car Loan Payoff Countdown
| Months left | Payments left (20ths) | Next payment | Target payoff |
|-------------|-----------------------|--------------|---------------|
| ${months_left} | ${payments_left} | ${next_payment_fmt} | 2027-12-20 |
EOF_LC
}

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
