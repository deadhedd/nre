# Deployment Requirements

This document records deployment requirements for the current private
installation. It is operational documentation, not a setup script.

Authoritative runtime behavior is still defined in `docs/CONTRACT.md`.

## Target Environment

Known deployment target:

* Host: `daemon`
* OS: OpenBSD
* Repository path: `/home/obsidian/nre-private`
* Runtime users include: `obsidian`, `git`
* Git binary path: `/usr/local/bin/git`

The commit helper defaults to:

* bare repository: `/home/git/vaults/Main.git`
* Git user: `git`

## doas.conf

The deployment requires these `doas.conf` permissions:

```text
permit persist obsidian as root
permit nopass obsidian as git cmd /usr/local/bin/git
permit nopass git as obsidian cmd /usr/local/bin/git
permit nopass jobs as obsidian cmd /home/obsidian/nre-private/jobs/private/import-job-notes.sh
permit nopass jobs as obsidian cmd /home/obsidian/nre-private/jobs/private/import-application-pdfs.sh
```

The isolated commit index requirement makes the plain `obsidian` as `git`
Git rule insufficient by itself. For commit helper use, `doas` must preserve
`GIT_INDEX_FILE` when `obsidian` runs `/usr/local/bin/git` as `git`.

On OpenBSD, that rule should include `setenv { GIT_INDEX_FILE }`:

```text
permit nopass setenv { GIT_INDEX_FILE } obsidian as git cmd /usr/local/bin/git
```

Keep the other required rules unchanged unless the contract or code changes.

Check the configuration syntax on the target host:

```sh
doas -C /etc/doas.conf
```

## Isolated Commit Index

`engine/lib/commit.sh` sets `GIT_INDEX_FILE` before crossing the `doas`
boundary:

```text
$BARE_REPO/tmp/commit-index.<job>.<pid>
```

With default commit settings, this resolves under:

```text
/home/git/vaults/Main.git/tmp/
```

The bare repository must have a repo-local temporary index directory writable by
the `git` user. The expected directory is:

```text
$BARE_REPO/tmp
```

The helper verifies both requirements at runtime:

* `GIT_INDEX_FILE` survives the `doas` boundary.
* `git read-tree HEAD` can initialize the isolated index in `$BARE_REPO/tmp`.

Useful checks on the target host:

```sh
BARE_REPO=${COMMIT_BARE_REPO:-/home/git/vaults/Main.git}
WORK_TREE=${COMMIT_WORK_TREE:-/home/obsidian/vaults/Main}
JOB_NAME=deployment-check
GIT_INDEX_FILE="$BARE_REPO/tmp/commit-index.$JOB_NAME.$$"
export GIT_INDEX_FILE

doas -u git /usr/local/bin/git \
  --git-dir="$BARE_REPO" \
  --work-tree="$WORK_TREE" \
  rev-parse --git-path index
```

The command should print the same path as `$GIT_INDEX_FILE`.

Inspect the repo-local index directory on the target host:

```sh
BARE_REPO=${COMMIT_BARE_REPO:-/home/git/vaults/Main.git}

ls -ld "$BARE_REPO/tmp"
```

An end-to-end initialization check verifies that the directory is usable by the
`git` process reached through the documented `doas` boundary:

```sh
BARE_REPO=${COMMIT_BARE_REPO:-/home/git/vaults/Main.git}
WORK_TREE=${COMMIT_WORK_TREE:-/home/obsidian/vaults/Main}
JOB_NAME=deployment-check
GIT_INDEX_FILE="$BARE_REPO/tmp/commit-index.$JOB_NAME.$$"
export GIT_INDEX_FILE

doas -u git /usr/local/bin/git \
  --git-dir="$BARE_REPO" \
  --work-tree="$WORK_TREE" \
  read-tree HEAD

rm -f "$GIT_INDEX_FILE"
```
