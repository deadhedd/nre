#!/bin/sh
# Copy these values into a deployment specific environment file.
# This example is safe for local use and contains no host or account details.

VAULT_ROOT=/path/to/your/vault
LOG_ROOT=/path/to/your/logs
WRAP_STATUS_REPORT=1
COMMIT_MODE=off

export VAULT_ROOT
export LOG_ROOT
export WRAP_STATUS_REPORT
export COMMIT_MODE
