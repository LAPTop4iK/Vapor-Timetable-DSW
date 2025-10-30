#!/bin/bash
# Run SyncRunner to populate PostgreSQL with fresh data

set -euo pipefail

APP_DIR="/srv/app"

echo "🔄 Starting sync runner..."
echo ""

# Load environment variables
if [ -f "$APP_DIR/.env" ]; then
    set -a
    source "$APP_DIR/.env"
    set +a
else
    echo "❌ Error: $APP_DIR/.env not found!"
    exit 1
fi

# Run SyncRunner with same network as postgres
docker run --rm \
    --network app_app-network \
    --env DATABASE_URL="postgres://${DB_USER:-vapor}:${DB_PASSWORD}@postgres:5432/${DB_NAME:-dsw_timetable}" \
    --env DSW_DEFAULT_FROM="${DSW_DEFAULT_FROM:-2025-09-06}" \
    --env DSW_DEFAULT_TO="${DSW_DEFAULT_TO:-2026-02-08}" \
    --env SYNC_DELAY_GROUPS_MS="${SYNC_DELAY_GROUPS_MS:-150}" \
    --env SYNC_DELAY_TEACHERS_MS="${SYNC_DELAY_TEACHERS_MS:-100}" \
    --env LOG_LEVEL="${LOG_LEVEL:-info}" \
    dsw-sync-runner:latest

echo ""
echo "✅ Sync completed!"
echo ""
echo "Check sync status in database:"
echo "  docker compose exec postgres psql -U ${DB_USER:-vapor} -d ${DB_NAME:-dsw_timetable} -c 'SELECT * FROM sync_status ORDER BY timestamp DESC LIMIT 5;'"
