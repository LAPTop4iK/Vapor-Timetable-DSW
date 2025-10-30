#!/bin/bash
# Build the SyncRunner Docker image

set -euo pipefail

APP_DIR="/srv/app"
CODE_DIR="$APP_DIR/vapor"

echo "🔨 Building SyncRunner Docker image..."

cd "$CODE_DIR"
docker build -f Dockerfile.sync -t dsw-sync-runner:latest .

echo "✅ SyncRunner image built successfully!"
echo ""
echo "Run it with: $APP_DIR/scripts/run-sync.sh"
