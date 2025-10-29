#!/bin/bash
#
# Setup cron job for DSW sync
# Run this script once on the VPS to configure cron
#

set -e

CRON_USER="root"
SCRIPT_PATH="/srv/app/vapor/scripts/run-sync.sh"

# Ensure script is executable
chmod +x "$SCRIPT_PATH"

# Create cron job (runs at 3 AM and 3 PM daily)
CRON_SCHEDULE="0 3,15 * * *"
CRON_COMMAND="$SCRIPT_PATH"

# Add cron job if it doesn't exist
(crontab -u "$CRON_USER" -l 2>/dev/null | grep -v "$SCRIPT_PATH"; echo "$CRON_SCHEDULE $CRON_COMMAND") | crontab -u "$CRON_USER" -

echo "✅ Cron job configured successfully!"
echo "Schedule: $CRON_SCHEDULE (3 AM and 3 PM daily)"
echo "Command: $CRON_COMMAND"
echo ""
echo "Current crontab for $CRON_USER:"
crontab -u "$CRON_USER" -l
