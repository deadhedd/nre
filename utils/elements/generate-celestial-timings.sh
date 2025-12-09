#!/bin/sh
# Assemble the celestial timings section (moon + seasonal tables).
# Author: deadhedd
# License: MIT
set -eu


script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
utils_dir=$(dirname -- "$script_dir")
celestial_dir="$utils_dir/celestial"

lunar_cycle_script="$celestial_dir/lunar-cycle.sh"
seasonal_cycle_script="$celestial_dir/seasonal-cycle.sh"

celestial_header="### 🌌 Celestial Timings"

moon_rows=$(cat <<'EOF'
<tr>
  <td>🌓 First Quarter</td>
  <td>n/a</td>
  <td>🌕 Full Moon</td>
  <td>6d 23h 20m (~7.0 days)</td>
</tr>
<tr class="moon-tip-row">
  <td colspan="4"><strong>Tip:</strong> Push through friction: fix blockers, make the hard call.</td>
</tr>
EOF
)

season_rows=$(cat <<'EOF'
<tr>
  <td>❄️ Winter Solstice</td>
  <td>Dec 21, 2025 · 07:03 AM PST</td>
  <td>23d 6h 52m</td>
</tr>
<tr class="season-tip-row">
  <td colspan="3"><strong>Tip:</strong> _(seasonal guidance TBD)_</td>
</tr>
EOF
)

if [ -r "$lunar_cycle_script" ]; then
  printf 'INFO %s\n' "Gathering lunar cycle data"
  if output=$(sh "$lunar_cycle_script"); then
    printf 'INFO %s\n' "Lunar cycle data retrieved"
    moon_rows=$output
  else
    status=$?
    printf 'WARN %s\n' "Lunar cycle script failed with exit code $status, using fallback text" >&2
  fi
else
  printf 'WARN %s\n' "Lunar cycle script not found at $lunar_cycle_script, using fallback text" >&2
fi

if [ -r "$seasonal_cycle_script" ]; then
  printf 'INFO %s\n' "Gathering seasonal cycle data"
  if output=$(sh "$seasonal_cycle_script"); then
    printf 'INFO %s\n' "Seasonal cycle data retrieved"
    season_rows=$output
  else
    status=$?
    printf 'WARN %s\n' "Seasonal cycle script failed with exit code $status, using fallback text" >&2
  fi
else
  printf 'WARN %s\n' "Seasonal cycle script not found at $seasonal_cycle_script, using fallback text" >&2
fi

cat <<EOF
$celestial_header
<table class="moon-table">
  <thead>
    <tr>
      <th>Moon Phase</th>
      <th>Illumination</th>
      <th>Next Phase</th>
      <th>Time Until</th>
    </tr>
  </thead>
  <tbody>
$moon_rows
  </tbody>
</table>

<table class="season-table">
  <thead>
    <tr>
      <th>Event</th>
      <th>Date &amp; Time</th>
      <th>Time Until</th>
    </tr>
  </thead>
  <tbody>
$season_rows
  </tbody>
</table>
EOF
