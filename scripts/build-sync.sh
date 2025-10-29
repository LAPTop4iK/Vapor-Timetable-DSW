#!/bin/bash
#
# Build sync-runner Docker image
#

set -e

cd "$(dirname "$0")/.."

echo "🔨 Building sync-runner Docker image..."

docker build -f Dockerfile.sync -t dsw-sync-runner:latest .

echo "✅ Sync-runner image built successfully!"
echo ""
echo "To run manually:"
echo "  ./scripts/run-sync.sh"
echo ""
echo "To setup cron:"
echo "  ./scripts/setup-cron.sh"
