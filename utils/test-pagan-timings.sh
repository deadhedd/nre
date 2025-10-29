#!/bin/sh
# Verify pagan-timings seasonal parsing handles rows missing the time token.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
SCRIPT="$SCRIPT_DIR/pagan-timings.sh"

TMPBIN=$(mktemp -d)
trap 'rm -rf "$TMPBIN"' EXIT
for cmd in curl jq bc; do
  cat <<'STUB' > "$TMPBIN/$cmd"
#!/bin/sh
exit 0
STUB
  chmod +x "$TMPBIN/$cmd"

done
export PATH="$TMPBIN:$PATH"

export OFFLINE=1
export PAGAN_TIMINGS_SEASON_ROWS=$(printf '%s\n' \
  '2030 3 19 |Equinox' \
  '2030 6 20 20:51|Solstice')

if ! OUTPUT=$(sh "$SCRIPT"); then
  echo "pagan-timings.sh failed" >&2
  exit 1
fi

if ! printf '%s' "$OUTPUT" | grep -F "Summer Solstice" >/dev/null 2>&1; then
  echo "Expected fallback to Summer Solstice when first row is malformed" >&2
  exit 1
fi

printf '%s\n' "pagan-timings.sh seasonal parsing fallback test passed"
