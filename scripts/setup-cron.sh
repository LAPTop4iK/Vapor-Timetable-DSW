#!/bin/bash
#
# setup-cron.sh
# Sets up cron job for DSW Firestore sync on VPS
# Run this once after deployment: sudo bash scripts/setup-cron.sh
#

set -euo pipefail

CRON_USER="root"
SYNC_SCRIPT="/srv/app/scripts/sync-runner.sh"
LOG_FILE="/var/log/dsw-sync.log"

echo "Setting up DSW Firestore sync cron job..."

# Create log file if it doesn't exist
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"

# Ensure sync script is executable
chmod +x "$SYNC_SCRIPT"

# Add cron job (runs twice a day: at 3:00 AM and 3:00 PM)
CRON_LINE="0 3,15 * * * $SYNC_SCRIPT >> $LOG_FILE 2>&1"

# Check if cron job already exists
if crontab -u "$CRON_USER" -l 2>/dev/null | grep -q "$SYNC_SCRIPT"; then
    echo "Cron job already exists, updating..."
    # Remove old entry
    crontab -u "$CRON_USER" -l | grep -v "$SYNC_SCRIPT" | crontab -u "$CRON_USER" -
fi

# Add new cron job
(crontab -u "$CRON_USER" -l 2>/dev/null || echo ""; echo "$CRON_LINE") | crontab -u "$CRON_USER" -

echo "Cron job installed successfully!"
echo "Schedule: Twice daily at 3:00 AM and 3:00 PM (Europe/Warsaw time)"
echo "Logs: $LOG_FILE"
echo ""
echo "To view current cron jobs: sudo crontab -l"
echo "To view sync logs: tail -f $LOG_FILE"
echo "To run sync manually: sudo $SYNC_SCRIPT"
