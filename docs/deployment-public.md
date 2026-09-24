# Public Deployment Requirements

This document describes the general requirements for running NRE outside the
development repository. Deployment specific paths, users, hosts, and privilege
rules belong to the operator and are not part of the public project.

The core engine targets POSIX `/bin/sh`. Ubuntu CI exercises portable shell and
tooling behavior, but that CI coverage does not establish complete Linux runtime
support or reproduce the private OpenBSD deployment.

## Requirements

* POSIX `/bin/sh`
* Git
* A writable vault directory
* A writable log directory
* Cron or another scheduler, when scheduled jobs are wanted
* `jq` for jobs that process JSON data

Copy the values from `env.example.sh` into a deployment specific environment
file and set the vault and log paths for that installation. Keep commit mode off
for a local installation unless Git persistence and its permissions have been
configured deliberately.

If a deployment enables commits, the current commit helper requires a `doas`
privilege boundary and runs Git as the configured Git user. Configure the Git
work tree, repository, user, `doas` permissions, and isolated index directory
deliberately. The private deployment maintains separate OpenBSD permission
rules. A portable privilege abstraction for other operating systems is not part
of the current runtime contract.
