# Shell environment variable inventory

This document summarizes the environment variable usage across all shell scripts in the repository, focusing on variables read from the environment (not locals or constants). It highlights whether each variable is required, optional overrides, or recognition-only, notes validation timing, and documents default behaviors.

## Summary
Environment variable inventory across all shell scripts (required unless noted). Defaults reflect behavior when unset.

| Variable | Role / Default | Validation |
| --- | --- | --- |
| JOB_WRAP_ACTIVE | Wrapper recursion guard; required for log sink. Default: unset triggers wrapper re-exec in leaf scripts. | Checked in log sink (hard exit) |
| VAULT_PATH | Override vault root (default `/home/obsidian/vaults/Main`). | Not validated beyond existence checks in consumers |
| PATH | Prepended with standard bins if unset. | Not validated |
| HOME | Fallback for repo/log paths. | Not validated |
| PULL_REPO_DIR | Optional override for repo location. | Presence checked; else defaults applied |
| GIT_BIN | Optional override for git binary. | Verified executable before use |
| LOG_SINK_LOADED | Guard to prevent double sourcing log sink. | Checked early |
| LOG_KEEP_COUNT | Log rotation keep count; default 10. | Range validated (numeric) during prune |
| LOG_TRUNCATE | If non-zero, truncates log on open; default 0. | Numeric check before truncation |
| LOG_INTERNAL_DEBUG / LOG_INTERNAL_DEBUG_FILE | Logger internal debugging toggle and target file; defaults off/unset. | Checked when emitting debug lines |
| JOB_NAME | Required job identifier for logging. | Required in log sink; exit if missing |
| LOG_FILE | Required timestamped log file path. | Required in log sink; exit if missing |
| LOG_LATEST | Optional latest symlink target; default `<dir>/<JOB_NAME>-latest.log`. | Initialized if unset |
| LOG_ROOT | Base log directory; defaults to `${HOME}/logs`. | Not directly validated; used to derive paths |
| LOG_INFO_STREAM / LOG_DEBUG_STREAM | Destinations for log/info streams; default stderr. | Initialized with defaults; not validated |
| DEBUG_XTRACE | Enables xtrace when non-zero. | Checked before exporting related vars |
| VAULT_ROOT / VAULT_LOG_DIR | Optional overrides for vault/log destinations. | Defaulted; not otherwise validated |
| TMPDIR | Temporary file parent; default `/tmp`. | Used for mktemp; not validated |
| LOG_DEBUG | Enables verbose sleep summary logging; default 0. | Used conditionally; not validated |
| SLEEP_TZ | Override time zone for sleep summary; default America/Los_Angeles. | Not validated |
| YESTERDAY_WAKE / TODAY_WAKE | Optional wake-time overrides for sleep summary. | Presence checked only |
| VAULT_DEFAULT / DAILY_NOTE_DIR | Override vault/daily note paths in snapshot script. | Defaulted; not validated |
| COMMIT_BARE_REPO | Optional bare repo path for commit helper; default computed. | Used directly without validation |
| JOB_WRAP_DEBUG / JOB_WRAP_ASCII_ONLY / JOB_WRAP_DEBUG_FILE | Wrapper debug controls; defaults off/ASCII-only. | Checked when emitting debug; no hard validation |
| JOB_WRAP_XTRACE / JOB_WRAP_XTRACE_FILE | Enable xtrace and target file; default derived from LOG_ROOT or /tmp. | Path ensured; no validation beyond non-empty |
| JOB_WRAP_SEARCH_PATH | Optional search directories for commands. | Iterated if set; no validation |
| JOB_WRAP_JOB_NAME | Optional override for derived job name. | Defaulted if unset |
| JOB_WRAP_DEFAULT_WORK_TREE | Optional commit work tree override; default VAULT_PATH. | Used when set; no validation |
| JOB_WRAP_DISABLE_COMMIT | Skip commit when non-empty. | Checked before commit execution |
| JOB_WRAP_DEFAULT_COMMIT_MESSAGE | Optional commit message template. | Defaulted if unset |
| JOB_WRAP_COMMIT_ON_SIGNAL / JOB_WRAP_SIG / JOB_WRAP_SHUTDOWN_DONE | Signal-handling/commit controls; defaults empty/0. | Evaluated during shutdown flow; no upfront validation |
| LOG_RUN_TS | Optional run timestamp; default generated. | Default set early; no validation |
| LOG_INTERNAL_LEVEL / LOG_ASCII_ONLY | Logger configuration; default INFO/1. | Defaulted and exported; not otherwise validated |
| PAGAN_TIMINGS_COMMON_SOURCED / TZ / LAT / LON | Celestial timing parameters; defaults LA coordinates/TZ. | Sourced defaults; no validation |
| OFFLINE | Opt-in offline mode for celestial scripts. | Checked to bypass network calls |
| PAGAN_TIMINGS_SEASON_ROWS / PAGAN_TIMINGS_SEASON_TIP | Optional seasonal overrides; defaults to blank/guidance string. | Presence checked; no validation |

### Variable details

#### JOB_WRAP_ACTIVE
- Read in leaf scripts to decide whether to re-exec through `job-wrap`; defaults to unset meaning wrapper launches the script.
- Required to be `1` when initializing the logging sink; failure exits with error.
- Not explicitly validated elsewhere.

#### VAULT_PATH
- Provides override for vault locations; defaults to `/home/obsidian/vaults/Main` when absent.
- Used for commit work-tree defaulting in wrapper.
- Not validated beyond downstream directory existence checks.

#### PATH
- Reset with standard locations prepended; falls back to existing `PATH` if set.
- No validation; optional override.

#### HOME / PULL_REPO_DIR / GIT_BIN
- `HOME` defaulted to `/home/obsidian` to resolve repo paths; optional override.
- `PULL_REPO_DIR` lets caller choose repo directory; if unset defaults cascade to two known paths.
- `GIT_BIN` allows custom git executable; resolved and then checked for executability before use (required for correctness).

#### LOG_SINK_LOADED / LOG_KEEP_COUNT / LOG_TRUNCATE / LOG_INTERNAL_DEBUG / LOG_INTERNAL_DEBUG_FILE / LOG_FD / LOG_LATEST / JOB_NAME / LOG_FILE
- Logging sink guards and knobs; defaults set on load (keep count 10, truncate 0).
- `JOB_NAME` and `LOG_FILE` are required; absence triggers immediate exit.
- `LOG_LATEST` defaulted to `<dir>/<JOB_NAME>-latest.log` if unset.
- `LOG_INTERNAL_DEBUG`/`LOG_INTERNAL_DEBUG_FILE` control internal diagnostics only.
- `LOG_FD` checked before writes; failure emits error.

#### LOG_ROOT / LOG_INFO_STREAM / LOG_DEBUG_STREAM / DEBUG_XTRACE
- `LOG_ROOT` default `${HOME}/logs`; used by wrapper and debug runner to locate debug outputs.
- Stream variables default to stderr to keep logs off stdout; optional overrides.
- `DEBUG_XTRACE` toggles xtrace export with optional file target; optional.

#### VAULT_ROOT / VAULT_LOG_DIR / TMPDIR
- Sync helper defaults `LOG_ROOT` and `VAULT_PATH` to derive log export locations; optional overrides.
- `TMPDIR` used for temporary files with mktemp fallback; optional override.

#### LOG_DEBUG / SLEEP_TZ / YESTERDAY_WAKE / TODAY_WAKE
- Sleep summary logging controlled by `LOG_DEBUG` defaulting to 0; only alters verbosity.
- `SLEEP_TZ` default America/Los_Angeles; influences time computations.
- Wake-time overrides `YESTERDAY_WAKE`/`TODAY_WAKE` if provided; otherwise computed internally.

#### VAULT_DEFAULT / DAILY_NOTE_DIR
- Snapshot script allows overriding vault root and daily note directory; defaults based on `VAULT_PATH`. No explicit validation beyond file operations.

#### COMMIT_BARE_REPO
- Commit helper accepts optional bare repo path; defaults if unset. No validation aside from git command behavior.

#### JOB_WRAP_DEBUG / JOB_WRAP_ASCII_ONLY / JOB_WRAP_DEBUG_FILE / JOB_WRAP_XTRACE / JOB_WRAP_XTRACE_FILE / JOB_WRAP_SEARCH_PATH / JOB_WRAP_JOB_NAME / JOB_WRAP_DEFAULT_WORK_TREE / JOB_WRAP_DISABLE_COMMIT / JOB_WRAP_DEFAULT_COMMIT_MESSAGE / JOB_WRAP_COMMIT_ON_SIGNAL / JOB_WRAP_SIG / JOB_WRAP_SHUTDOWN_DONE / LOG_RUN_TS / LOG_INTERNAL_LEVEL / LOG_ASCII_ONLY
- Debug and execution knobs consumed inside wrapper; all optional with sensible defaults (debug off, ASCII sanitization on, commit enabled, auto log naming).
- `JOB_WRAP_COMMIT_ON_SIGNAL` only affects post-signal commit behavior; no validation.
- `LOG_RUN_TS`, `LOG_INTERNAL_LEVEL`, `LOG_ASCII_ONLY` default set early for logging metadata.

#### PAGAN_TIMINGS_COMMON_SOURCED / TZ / LAT / LON / OFFLINE / PAGAN_TIMINGS_SEASON_ROWS / PAGAN_TIMINGS_SEASON_TIP
- Celestial timing scripts source defaults for location/timezone; optional overrides with no validation.
- `OFFLINE` short-circuits network fetches; required for offline behavior only.
- Seasonal overrides allow custom rows/tips; optional.

## Potential contract updates
- Consider documenting `JOB_WRAP_ACTIVE`, `JOB_NAME`, and `LOG_FILE` as required inputs for the logging sink and wrapper lifecycle.
- Optional operational overrides worth mentioning: `VAULT_PATH`, `LOG_ROOT`, `LOG_KEEP_COUNT`, `LOG_TRUNCATE`, `DEBUG_XTRACE`, and `JOB_WRAP_DISABLE_COMMIT`.
- Recognition-only toggles (e.g., `LOG_INTERNAL_DEBUG`, `LOG_DEBUG`, `OFFLINE`) may be candidates for consolidation or explicit CLI flags if broad usage grows.
