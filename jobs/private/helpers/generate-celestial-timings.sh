#!/bin/sh
# Assemble the celestial timings section (moon + seasonal tables).
# Author: deadhedd
# License: MIT
set -eu

###############################################################################
# Logging (diagnostics to stderr; stdout reserved for assembled content)
###############################################################################
log_debug() { printf '%s\n' "DEBUG: $*" >&2; }
log_info()  { printf '%s\n' "INFO: $*"  >&2; }
log_warn()  { printf '%s\n' "WARN: $*"  >&2; }
log_error() { printf '%s\n' "ERROR: $*" >&2; }

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
jobs_dir=$(CDPATH= cd -- "$script_dir/.." && pwd -P)
helpers_dir="$jobs_dir/helpers"

lunar_cycle_script="$helpers_dir/lunar-cycle.sh"
seasonal_cycle_script="$helpers_dir/seasonal-cycle.sh"

celestial_header="### 🌌 Celestial Timings"

failure=0

moon_rows=$(cat <<'EOF_MOON'
<tr>
  <td>🌓 First Quarter</td>
  <td>n/a</td>
  <td>🌕 Full Moon</td>
  <td>6d 23h 20m (~7.0 days)</td>
</tr>
<tr class="moon-tip-row">
  <td colspan="4"><strong>Tip:</strong> Push through friction: fix blockers, make the hard call.</td>
</tr>
EOF_MOON
)

season_rows=$(cat <<'EOF_SEASON'
<tr>
  <td>❄️ Winter Solstice</td>
  <td>Dec 21, 2025 · 07:03 AM PST</td>
  <td>23d 6h 52m</td>
</tr>
<tr class="season-tip-row">
  <td colspan="3"><strong>Tip:</strong> _(seasonal guidance TBD)_</td>
</tr>
EOF_SEASON
)

if [ -r "$lunar_cycle_script" ]; then
  log_info "Gathering lunar cycle data"
  if output=$(sh "$lunar_cycle_script"); then
    log_info "Lunar cycle data retrieved"
    moon_rows=$output
  else
    status=$?
    log_error "Lunar cycle script failed with exit code $status, using fallback text"
    failure=1
  fi
else
  log_error "Lunar cycle script not found at $lunar_cycle_script, using fallback text"
  failure=1
fi

if [ -r "$seasonal_cycle_script" ]; then
  log_info "Gathering seasonal cycle data"
  if output=$(sh "$seasonal_cycle_script"); then
    log_info "Seasonal cycle data retrieved"
    season_rows=$output
  else
    status=$?
    log_error "Seasonal cycle script failed with exit code $status, using fallback text"
    failure=1
  fi
else
  log_error "Seasonal cycle script not found at $seasonal_cycle_script, using fallback text"
  failure=1
fi

cat <<EOF_OUT
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
EOF_OUT

if [ "$failure" -ne 0 ]; then
  exit 1
fi
