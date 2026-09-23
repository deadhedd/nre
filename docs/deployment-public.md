# Public Deployment Requirements

This document describes the general requirements for running NRE outside the
development repository. Deployment specific paths, users, hosts, and privilege
rules belong to the operator and are not part of the public project.

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

If a deployment enables commits, configure its Git work tree, repository, user,
and privilege boundary according to the host operating system. NRE does not
assume a particular host, user, repository path, or privilege tool.
