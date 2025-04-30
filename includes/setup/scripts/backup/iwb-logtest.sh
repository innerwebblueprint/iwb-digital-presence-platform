#!/bin/bash
# includes/setup/scripts/backup/iwb-logtest.sh

LOG_FILE="/var/log/iwb-backup.log"

# Load environment and functions
source /var/setup/scripts/setup-env.sh
MODULE="LOG TEST"

# Redirect all output of log function to console and log file
exec > >(tee -a "$LOG_FILE") 2>&1

log "This is a test of the logging module"