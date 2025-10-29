#!/bin/bash
#
# DSW Timetable Sync Script
# Runs SyncRunner to preload data into Firestore
#
# Usage: ./dsw-sync.sh
#

set -e

# Configuration
PROJECT_DIR="/srv/dsw-timetable"
COMPOSE_FILE="$PROJECT_DIR/docker-compose.prod.yml"
SYNC_CONTAINER="dsw-sync-runner"
LOG_FILE="/var/log/dsw-sync-cron.log"

# Colors for terminal output (optional)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo "[$(date -Iseconds)] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date -Iseconds)] ERROR: $1${NC}" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[$(date -Iseconds)] SUCCESS: $1${NC}" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[$(date -Iseconds)] WARNING: $1${NC}" | tee -a "$LOG_FILE"
}

# Check if running as root (required for docker compose)
if [ "$EUID" -ne 0 ]; then
    log_error "This script must be run as root (for docker compose access)"
    exit 1
fi

# Check if project directory exists
if [ ! -d "$PROJECT_DIR" ]; then
    log_error "Project directory not found: $PROJECT_DIR"
    exit 1
fi

# Check if docker-compose file exists
if [ ! -f "$COMPOSE_FILE" ]; then
    log_error "Docker compose file not found: $COMPOSE_FILE"
    exit 1
fi

# Change to project directory
cd "$PROJECT_DIR" || exit 1

log "═══════════════════════════════════════════════════════════════"
log "Starting DSW Timetable Sync"
log "═══════════════════════════════════════════════════════════════"

# Check if Firestore credentials exist
if [ ! -f "/srv/secrets/firestore-service-account.json" ]; then
    log_error "Firestore service account credentials not found"
    exit 1
fi

# Check if sync container is already running
if docker ps | grep -q "$SYNC_CONTAINER"; then
    log_warning "Sync container is already running. Skipping this run."
    exit 0
fi

# Run sync container
log "Running sync container..."
if docker compose -f "$COMPOSE_FILE" run --rm "$SYNC_CONTAINER" 2>&1 | tee -a "$LOG_FILE"; then
    EXIT_CODE=${PIPESTATUS[0]}
else
    EXIT_CODE=$?
fi

# Check exit code
if [ $EXIT_CODE -eq 0 ]; then
    log_success "Sync completed successfully"
elif [ $EXIT_CODE -eq 1 ]; then
    log_warning "Sync completed with partial errors (some groups/teachers failed)"
else
    log_error "Sync failed with exit code $EXIT_CODE"
fi

log "═══════════════════════════════════════════════════════════════"

exit $EXIT_CODE
