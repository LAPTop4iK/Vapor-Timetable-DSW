#!/bin/bash
# Alternative build script using legacy Docker builder (without BuildKit)
# Use this if regular build fails with BuildKit errors

set -euo pipefail

APP_DIR="/srv/app"
CODE_DIR="$APP_DIR/vapor"

echo "🔨 Building with legacy Docker builder (BuildKit disabled)"
echo ""

cd "$CODE_DIR"

# Build API server
echo "Building Vapor API server..."
DOCKER_BUILDKIT=0 docker build -f Dockerfile -t vapor-api:latest .

# Build SyncRunner
echo ""
echo "Building SyncRunner..."
DOCKER_BUILDKIT=0 docker build -f Dockerfile.sync -t dsw-sync-runner:latest .

echo ""
echo "✅ Build complete!"
echo ""
echo "Now update docker-compose to use these images:"
echo "  cd $APP_DIR"
echo "  docker compose up -d"
