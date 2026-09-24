# Shell environment variable inventory

This inventory records environment inputs and exported context used by the
current wrapper, logger, commit helper, reporter, and release tooling. It
distinguishes wrapper defaults from direct helper defaults. Local shell
variables and test fixture variables are not configuration interfaces.

## Wrapper context and paths

| Variable | Current behavior | Validation or ownership |
| --- | --- | --- |
| `JOB_WRAP_ENV_FILE` | Optional POSIX `sh` environment file. The wrapper default is `/home/obsidian/nre-private/env.sh`. The commit helper retains its standalone fallback `/home/obsidian/obsidian-note-tools/env.sh`. | Wrapper sources it when readable. A readable file that fails to source causes wrapper exit `121`. |
| `JOB_WRAP_ACTIVE` | Wrapper recursion and logger context marker. | Wrapper exports `1`; logger components require wrapper context. |
| `REPO_ROOT` | Absolute repository root derived from the wrapper location unless already provided. | Wrapper rejects a non absolute or structurally invalid value with exit `121`. |
| `LOG_ROOT` | Wrapper default is `../logs` beside the repository, with `$REPO_ROOT/logs` as fallback. | Explicit values are preserved. Direct reporter helpers retain their documented `/home/obsidian/logs` fallback. |
| `VAULT_ROOT` | Canonical wrapper vault and artifact root. | Wrapper uses `VAULT_ROOT`, then `VAULT_PATH`, then `/home/obsidian/vaults/Main`. Consumers validate only as needed for their file operations. |
| `VAULT_PATH` | Compatibility fallback for `VAULT_ROOT`. Some older jobs also read it directly. | It is not a wrapper level alias after `VAULT_ROOT` has been chosen. |
| `COMMIT_WORK_TREE` | Commit work tree root. Default is `VAULT_ROOT`. | Used by wrapper commit orchestration and the commit helper. The selected path must contain the explicit files being committed. |
| `LOG_LIB_DIR` | General library directory. Default `$REPO_ROOT/engine/lib`. | Wrapper exports it for logger and commit components. |
| `ENGINE_LIB_DIR` | Engine logger directory. Default `$REPO_ROOT/engine`. | Wrapper exports it for logger components. |
| `COMMIT_LIB_DIR` | Commit helper directory. Default `$LOG_LIB_DIR`. | Wrapper exports it and invokes `commit.sh` from this directory. |
| `TMPDIR` | Temporary file parent. Default `/tmp` when unset. | Wrapper and helpers use it for temporary files. Unusable temporary storage triggers the documented degradation path. |
| `PATH` | The wrapper does not globally normalize it. | The commit helper and log mirror helper prepend `/usr/local/bin:/usr/bin:/bin`; individual jobs may set their own path. |
| `JOB_WRAP_SEARCH_PATH` | Leaf search path. Default `$REPO_ROOT/bin:$REPO_ROOT/jobs:$REPO_ROOT/generators:$REPO_ROOT/engine:$REPO_ROOT/utils:$REPO_ROOT/scripts`. | Wrapper searches configured directories before repository and `PATH` fallbacks. |
| `WRAP_STATUS_REPORT` | Optional status report invocation. Default `0`. | When `1`, wrapper invokes the status helper after eligible jobs. |

## Commit configuration

| Variable | Current behavior | Validation or ownership |
| --- | --- | --- |
| `COMMIT_MODE` | Default `required`. `off` disables commit orchestration. Other values enable it, with helper failures treated as warnings unless the value is `required`. | Wrapper owns the policy. No policy change is implied by this inventory. |
| `COMMIT_LIST_FILE` | Wrapper created file containing explicitly registered artifacts when commit mode is not `off` and temporary storage is available. | Exported to the leaf, filtered by the wrapper, and removed during wrapper cleanup. |
| `COMMIT_MESSAGE` | Commit message. Default `job: ${JOB_NAME}` when empty. | Wrapper supplies it to the commit helper. |
| `COMMIT_BARE_REPO` | Bare repository used by the commit helper. Default `/home/git/vaults/Main.git`. | Helper and Git validate availability through their normal failure paths. |
| `COMMIT_INDEX_DIR` | Directory for the isolated commit index. Default `$COMMIT_BARE_REPO/tmp`. | The directory must be usable by the Git user reached through `doas`. |
| `GIT_BIN` | Git executable override. Default `/usr/local/bin/git` when executable, otherwise `git`. | Commit helper requires a usable executable. |
| `GIT_USER` | User used for Git operations. Default `git`. | Commit helper validates the name and requires the `doas` boundary. |
| `ENGINE_DEBUG` | Commit helper diagnostic input. When enabled with `1` (the implementation also accepts `yes`, `true`, `on`, and their uppercase forms), it emits extra diagnostics. | Stderr only. It does not change stdout or exit semantics. |
| `LOG_INTERNAL_DEBUG` | Alternate commit helper diagnostic input with the same semantics as `ENGINE_DEBUG`. | Stderr only. It does not change stdout or exit semantics. |
| `COMMIT_GIT_INDEX_FILE` | Per attempt isolated index path selected by the commit helper. | Internal commit state. The OpenBSD deployment must preserve it across `doas`. |

## Logger context and controls

| Variable | Current behavior | Validation or ownership |
| --- | --- | --- |
| `JOB_NAME` | Derived job identifier used in log names and commit defaults. | Logger requires a valid non empty name. |
| `LOG_BUCKET` | Log subdirectory selected by the wrapper or logger caller. | Used by the log sink when constructing paths. |
| `LOG_FILE` | Generated per run log path, `${LOG_ROOT}/${LOG_BUCKET}/${JOB_NAME}-YYYY-MM-DD-HHMMSS.log`. | Sink creates and exports it after validating the logger context. It is not a required input. |
| `LOG_MIN_LEVEL` | Minimum logger level supplied by the wrapper or caller. | Logger validates the level and returns its documented status. |
| `LOG_KEEP_COUNT` | Retention count. The wrapper defaults it to `10`; direct sink use defaults to disabled pruning when it is unset or empty. `0` also disables pruning. | The sink accepts non negative integers; positive values keep that many recent per run logs. |
| `JOB_WRAP_DEBUG` | Wrapper diagnostic input. When `1`, it enables DEBUG minimum level and healthy mode boundary diagnostics. | Debug output remains separate from primary stdout. |

The sink generates the latest log pointer internally at
`${LOG_ROOT}/${LOG_BUCKET}/${JOB_NAME}-latest.log`; it does not consume a
`LOG_LATEST` input. The current implementation also does not consume
`LOG_TRUNCATE`, `LOG_INTERNAL_DEBUG_FILE`, or `JOB_WRAP_DEBUG_FILE`; these are
not supported logger configuration variables.

## Job specific inputs

These variables are used by particular jobs rather than by the wrapper contract.
Their defaults remain job specific.

| Variable | Current behavior |
| --- | --- |
| `PULL_REPO_DIR` | Optional repository location override for the private pull job. |
| `HOME` | Used as a fallback by selected legacy or private jobs. It is not a repository wide path default. |
| `SLEEP_TZ` | Time zone override for sleep processing. Default `America/Los_Angeles`. |
| `YESTERDAY_WAKE` and `TODAY_WAKE` | Optional wake time overrides for sleep processing. |
| `SNAPSHOT_DATE` | Optional date override for daily note snapshotting. |
| `PERIODIC_NOTES_DIR`, `SUBNOTES_DIR`, `DASHBOARDS_DIR`, `DATA_NOTES_DIR`, `SLEEP_DATA_DIR`, and `SERVER_LOGS_DIR` | Vault subdirectory overrides supplied by the private environment file. |
| `ARCHIVE_KEEP_DAILY_DAYS`, `ARCHIVE_KEEP_WEEKLY_WEEKS`, `ARCHIVE_KEEP_MONTHLY_MONTHS`, `ARCHIVE_KEEP_QUARTERLY_QTRS`, and `ARCHIVE_KEEP_YEARLY_YEARS` | Archive retention settings supplied by the private environment file. |
| `TZ`, `LAT`, `LON`, `OFFLINE`, `PAGAN_TIMINGS_SEASON_ROWS`, and `PAGAN_TIMINGS_SEASON_TIP` | Celestial timing inputs and offline behavior. |

## Release tooling inputs

| Variable | Current behavior |
| --- | --- |
| `SOURCE_REF` | Git source reference for public export when no `--source-ref` argument is supplied. Default `master`. |
| `PUBLIC_REPO_URL` | Destination URL for normal public release mode. Required for publishing, not for validation only. |
| `PUBLIC_REPO_REF` | Destination branch. Default `master`. |

The current contract leaves wrapper PATH and locale normalization, reporter
policy, and commit mode policy as open decisions. This inventory describes the
current behavior and does not resolve those decisions.
