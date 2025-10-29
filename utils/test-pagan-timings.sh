#!/bin/sh
# Verify pagan-seasons seasonal parsing handles rows missing the time token.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
SCRIPT="$SCRIPT_DIR/pagan-seasons.sh"

TMPBIN=$(mktemp -d)
trap 'rm -rf "$TMPBIN"' EXIT
SENTINEL="$TMPBIN/malicious-hit"
export SENTINEL

for cmd in curl jq pagan_malicious; do
  cat <<'STUB' > "$TMPBIN/$cmd"
#!/bin/sh
if [ "$(basename "$0")" = "pagan_malicious" ]; then
  : "${SENTINEL:?missing}"
  printf 'triggered' >"$SENTINEL"
  exit 0
fi
exit 0
STUB
  chmod +x "$TMPBIN/$cmd"

done
export PATH="$TMPBIN:$PATH"

export OFFLINE=1
export PAGAN_TIMINGS_SEASON_ROWS=$(printf '%s\n' \
  '2030 9 22 $(pagan_malicious)|Equinox' \
  '2030 3 19 |Equinox' \
  '2030 6 20 20:51|Solstice')

if ! OUTPUT=$(sh "$SCRIPT"); then
  echo "pagan-seasons.sh failed" >&2
  exit 1
fi

if ! printf '%s' "$OUTPUT" | grep -F "Summer Solstice" >/dev/null 2>&1; then
  echo "Expected fallback to Summer Solstice when first row is malformed" >&2
  exit 1
fi

if [ -e "$SENTINEL" ]; then
  echo "Command substitution from time field was executed" >&2
  exit 1
fi

printf '%s\n' "pagan-seasons.sh seasonal parsing fallback test passed"
