#!/bin/bash
#
# Script to run the sync process
# This should be called by cron
#

set -e

# Configuration
LOG_DIR="/var/log/dsw-sync"
LOG_FILE="$LOG_DIR/sync-$(date +%Y%m%d-%H%M%S).log"
LATEST_LOG="$LOG_DIR/latest.log"
DOCKER_IMAGE="dsw-sync-runner:latest"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Log start
echo "========================================" | tee -a "$LATEST_LOG"
echo "DSW Sync started at $(date)" | tee -a "$LATEST_LOG"
echo "========================================" | tee -a "$LATEST_LOG"

# Run sync in Docker container
docker run --rm \
    --name dsw-sync-runner \
    --network app_default \
    -e FIRESTORE_PROJECT_ID="${FIRESTORE_PROJECT_ID}" \
    -e FIRESTORE_CREDENTIALS_PATH="/run/secrets/firestore-service-account.json" \
    -e DSW_DEFAULT_FROM="${DSW_DEFAULT_FROM:-2025-09-06}" \
    -e DSW_DEFAULT_TO="${DSW_DEFAULT_TO:-2026-02-08}" \
    -e SYNC_DELAY_GROUPS_MS="${SYNC_DELAY_GROUPS_MS:-150}" \
    -e SYNC_DELAY_TEACHERS_MS="${SYNC_DELAY_TEACHERS_MS:-100}" \
    -v /srv/secrets/firestore-service-account.json:/run/secrets/firestore-service-account.json:ro \
    "$DOCKER_IMAGE" 2>&1 | tee -a "$LOG_FILE" | tee "$LATEST_LOG"

EXIT_CODE=${PIPESTATUS[0]}

# Log completion
echo "========================================" | tee -a "$LATEST_LOG"
echo "DSW Sync finished at $(date) with exit code $EXIT_CODE" | tee -a "$LATEST_LOG"
echo "========================================" | tee -a "$LATEST_LOG"

# Keep only last 30 log files
cd "$LOG_DIR"
ls -t sync-*.log | tail -n +31 | xargs -r rm

exit $EXIT_CODE
