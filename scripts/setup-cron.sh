#!/bin/bash
# Setup cron job to run SyncRunner daily at 3 AM

set -euo pipefail

APP_DIR="/srv/app"
CRON_TIME="${CRON_TIME:-0 3 * * *}"  # Default: 3 AM daily

echo "📅 Setting up cron job for SyncRunner"
echo ""
echo "Schedule: $CRON_TIME (cron format)"
echo ""

# Create cron job entry
CRON_ENTRY="$CRON_TIME $APP_DIR/scripts/run-sync.sh >> $APP_DIR/sync-cron.log 2>&1"

# Check if cron entry already exists
if crontab -l 2>/dev/null | grep -q "run-sync.sh"; then
    echo "⚠️  Cron job already exists. Updating..."
    # Remove old entry
    crontab -l 2>/dev/null | grep -v "run-sync.sh" | crontab -
fi

# Add new entry
(crontab -l 2>/dev/null; echo "$CRON_ENTRY") | crontab -

echo "✅ Cron job installed successfully!"
echo ""
echo "Current crontab:"
crontab -l | grep "run-sync.sh"
echo ""
echo "Logs will be written to: $APP_DIR/sync-cron.log"
echo ""
echo "To change schedule, set CRON_TIME environment variable:"
echo "  CRON_TIME='0 */6 * * *' ./scripts/setup-cron.sh  # Every 6 hours"
echo "  CRON_TIME='0 2,14 * * *' ./scripts/setup-cron.sh  # 2 AM and 2 PM"
echo ""
echo "To remove cron job:"
echo "  crontab -l | grep -v 'run-sync.sh' | crontab -"
