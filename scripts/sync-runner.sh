#!/bin/bash
#
# sync-runner.sh
# Wrapper script for running the Firestore sync from cron
# Logs to /var/log/dsw-sync.log
#

set -euo pipefail

LOG_FILE="/var/log/dsw-sync.log"
LOCK_FILE="/var/run/dsw-sync.lock"

# Function to log with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Check if another sync is running
if [ -f "$LOCK_FILE" ]; then
    PID=$(cat "$LOCK_FILE")
    if ps -p "$PID" > /dev/null 2>&1; then
        log "ERROR: Another sync is already running (PID: $PID)"
        exit 1
    else
        log "WARNING: Stale lock file found, removing..."
        rm -f "$LOCK_FILE"
    fi
fi

# Create lock file
echo $$ > "$LOCK_FILE"

# Cleanup function
cleanup() {
    rm -f "$LOCK_FILE"
}
trap cleanup EXIT

log "=========================================="
log "Starting DSW Firestore sync"
log "=========================================="

# Run the sync using docker-compose
cd /srv/app || exit 1

# Pull latest code (optional, uncomment if you want to auto-update)
# git pull origin main

# Rebuild sync container if needed
docker-compose build dsw-sync

# Run the sync
if docker-compose run --rm dsw-sync; then
    log "Sync completed successfully"
    EXIT_CODE=0
else
    log "Sync failed with exit code $?"
    EXIT_CODE=1
fi

log "=========================================="
log "Sync finished"
log "=========================================="

exit $EXIT_CODE
