# Date Logic Inventory

This report catalogs date and time handling across the repository, including the shared helper script and locally implemented routines.

## Shared helper: `utils/core/date-period-helpers.sh`
- **Basic retrieval/formatting:** `get_current_year`, `get_prev_year`, `get_next_year`, `get_current_quarter`, `get_quarter_tag`, `get_quarter_tag_iso`, `get_today`, `get_today_utc`, `get_local_iso_timestamp`, `get_utc_run_id`, `get_utc_epoch_seconds`, and `get_current_date_parts` derive current-date fields and formatted timestamps.
- **Parsing/validation:** `parse_utc_date`, `parse_utc_time`, `is_utc_date_format`, and `is_valid_utc_date` validate input strings before computations.
- **Month tags:** `month_tag`, `get_current_month_tag`, `get_prev_month_tag`, `get_next_month_tag`, `add_months`, and `shift_utc_date_by_days` (via `get_yesterday`/`get_tomorrow`) compute YYYY-MM labels with offsets.
- **Week tags:** `weekday_name_for_index`, `weekday_for_utc_date`, `week_tag`, `get_current_week_tag`, `get_prev_week_tag`, `get_next_week_tag`, `week_tag_for_epoch`, `week_tag_for_utc_date`, and `week_nav_tags_for_utc_date` produce ISO week numbers and neighbor navigation values.
- **Epoch conversions:** `epoch_for_utc_date`, `epoch_for_utc_datetime`, `utc_date_for_epoch`, `shift_epoch_by_days`, `week_tag_for_epoch`, `month_tag_for_epoch`, `year_for_epoch`, `epoch_for_local_datetime`, and `format_epoch_local` convert between date strings, epoch seconds, and localized formats.
- **Quarter tags:** `quarter_tag_for_epoch` and `quarter_tag_for_utc_date` emit quarter labels from epoch or date inputs.

## Core scripts using local date logic
- `utils/core/log-sink.sh` – `log_sink__internal` timestamps internal debug lines with `date '+%Y-%m-%dT%H:%M:%S%z'`.
- `utils/core/log-format.sh` – `log_fmt__ts` emits an ISO-like local timestamp when `LOG_TIMESTAMP` is enabled.
- `utils/core/job-wrap.sh` – `job_wrap__now` formats debug timestamps as `%Y-%m-%dT%H:%M:%S%z`; `job_wrap__runid` builds per-run IDs with `%Y%m%dT%H%M%S`.
- `utils/core/run-with-debug.sh` – derives UTC run IDs for debug file names via `date -u +%Y%m%dT%H%M%SZ`.
- `utils/core/script-status-report.sh` – `now_local` returns `%Y-%m-%dT%H:%M:%S` (no timezone) for log and report generation metadata.
- `jobs/helpers/sync-latest-logs-to-vault.sh` – `now_local` mirrors the `%Y-%m-%dT%H:%M:%S` local timestamp for sync logging.
- `utils/core/daily-note-snapshot.sh` – defaults the target daily note path to today’s date using `date +%Y-%m-%d`.

## Other utilities with date handling
- `utils/celestial/celestial-timings-common.sh` – exposes `now_utc_s` (epoch seconds), `to_epoch_utc` (parse `YYYY-MM-DD HH:MM` into UTC epoch), and `fmt_eta` (human-readable durations).
- `utils/celestial/lunar-cycle.sh` – `format_utc_date` renders UTC dates from epoch values; the script also computes current UTC date/time for NOAA API calls and phase calculations.
- `utils/celestial/seasonal-cycle.sh` – retrieves the current UTC year via `date -u +%Y` for solstice/equinox lookups.
- `utils/sleep/summarize-daily-sleep.sh` – `timestamp_to_epoch` parses multiple timestamp formats (local/offset-aware) into epoch seconds; `epoch_to_iso` formats epoch values into UTC ISO strings.
- `utils/elements/check-yardwork-suitability.sh` – captures today’s date via `date +%Y-%m-%d` to filter hourly forecast data and select the daily note file.
- `utils/elements/f1-schedule-and-standings.sh` – provides portable helpers `to_epoch`, `from_epoch`, `add_days`, and `diff_days` to convert dates, add day offsets, and compute day deltas for race schedules.
- `utils/finances/normalize-credit-card.sh` – AWK routines assemble ISO-like posting and transaction dates from month/day components when importing CSV data.
