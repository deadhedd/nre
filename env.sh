#!/bin/sh
# /home/obsidian/obsidian-note-tools/env.sh

###############################################################################
# Core paths
###############################################################################

VAULT_ROOT=/home/obsidian/vaults/Main

###############################################################################
# Logging
###############################################################################

LOG_ROOT=/home/obsidian/logs
LOG_INTERNAL_DEBUG=1
LOG_INTERNAL_DEBUG_FILE=/home/obsidian/logs/other/log-internal-debug.log

JOB_WRAP_DEBUG=1
JOB_WRAP_DEBUG_FILE=/home/obsidian/logs/other/job-wrap-debug.log

###############################################################################
# Wrapper behavior
###############################################################################

WRAP_STATUS_REPORT=1

###############################################################################
# Vault structure
###############################################################################

PERIODIC_NOTES_DIR='10 - Periodic Notes'
SUBNOTES_DIR='10 - Periodic Notes/Daily Notes/Subnotes'
DASHBOARDS_DIR='00 - System/Dashboards'
DATA_NOTES_DIR='00 - System/Data'
COMBINED_TASK_LIST_PATH='/home/obsidian/vaults/Main/00 - System/Data/Tasks/Combined Task List.md'
SLEEP_DATA_DIR='00 - System/Data/Sleep Data'
SERVER_LOGS_DIR='00 - System/Server Logs'

###############################################################################
# Archive retention policy
###############################################################################
# Controls how long periodic notes are kept before being archived.
# Units:
# - DAILY: days
# - WEEKLY: weeks
# - MONTHLY: months
# - QUARTERLY: quarters
# - YEARLY: years

ARCHIVE_KEEP_DAILY_DAYS=90
ARCHIVE_KEEP_WEEKLY_WEEKS=52
ARCHIVE_KEEP_MONTHLY_MONTHS=24
ARCHIVE_KEEP_QUARTERLY_QTRS=12
ARCHIVE_KEEP_YEARLY_YEARS=5

###############################################################################
# Finance account mapping (last-4 → logical account)
###############################################################################

# Replace these with your real last-4 values
FINANCE_ACCOUNT_CREDIT_CARD_LAST4="1376"
FINANCE_ACCOUNT_CHECKING_LAST4="0725"
FINANCE_ACCOUNT_MONEY_MARKET_LAST4="2213"
FINANCE_ACCOUNT_LINE_OF_CREDIT_LAST4="0725"

###############################################################################
# Export
###############################################################################

export VAULT_ROOT

export LOG_ROOT
export LOG_INTERNAL_DEBUG
export LOG_INTERNAL_DEBUG_FILE

export JOB_WRAP_DEBUG
export JOB_WRAP_DEBUG_FILE

export WRAP_STATUS_REPORT

export PERIODIC_NOTES_DIR
export SUBNOTES_DIR
export DASHBOARDS_DIR
export DATA_NOTES_DIR
export COMBINED_TASK_LIST_PATH
export SLEEP_DATA_DIR
export SERVER_LOGS_DIR

export FINANCE_ACCOUNT_CREDIT_CARD_LAST4
export FINANCE_ACCOUNT_CHECKING_LAST4
export FINANCE_ACCOUNT_MONEY_MARKET_LAST4
export FINANCE_ACCOUNT_LINE_OF_CREDIT_LAST4

export ARCHIVE_KEEP_DAILY_DAYS
export ARCHIVE_KEEP_WEEKLY_WEEKS
export ARCHIVE_KEEP_MONTHLY_MONTHS
export ARCHIVE_KEEP_QUARTERLY_QTRS
export ARCHIVE_KEEP_YEARLY_YEARS
