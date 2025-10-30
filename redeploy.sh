#!/bin/bash
set -euo pipefail

APP_DIR="/srv/app"
CODE_DIR="$APP_DIR/vapor"

echo ">>> [1/5] Pull latest code"
cd "$CODE_DIR"
git fetch --all
git reset --hard origin/main

echo ">>> [2/5] Copy configuration files from repo to app directory"

# Check if .env exists and has DB_PASSWORD set
if [ ! -f "$APP_DIR/.env" ]; then
    echo "  ❌ ERROR: $APP_DIR/.env not found!"
    echo "  Create it from template:"
    echo "    cp $CODE_DIR/.env.production.example $APP_DIR/.env"
    echo "    nano $APP_DIR/.env  # Set DB_PASSWORD"
    exit 1
fi

if ! grep -q "DB_PASSWORD=.\+" "$APP_DIR/.env" 2>/dev/null; then
    echo "  ⚠️  WARNING: DB_PASSWORD not set in $APP_DIR/.env"
    echo "  Please edit $APP_DIR/.env and set a secure password"
    read -p "  Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Copy docker-compose if it was updated in repo
if [ -f "$CODE_DIR/docker-compose.production.yml" ]; then
    echo "  - Updating docker-compose.yml"
    cp "$CODE_DIR/docker-compose.production.yml" "$APP_DIR/docker-compose.yml"
fi

# Copy .env.production.example as template (but don't overwrite existing .env)
if [ -f "$CODE_DIR/.env.production.example" ] && [ ! -f "$APP_DIR/.env" ]; then
    echo "  - Creating .env from template (first time only)"
    cp "$CODE_DIR/.env.production.example" "$APP_DIR/.env"
    echo "  ⚠️  IMPORTANT: Edit $APP_DIR/.env and set your database password!"
elif [ -f "$CODE_DIR/.env.production.example" ]; then
    echo "  - .env already exists, not overwriting"
    echo "  - You can check .env.production.example for new variables"
fi

# Copy scripts directory
if [ -d "$CODE_DIR/scripts" ]; then
    echo "  - Updating scripts directory"
    rm -rf "$APP_DIR/scripts"
    cp -r "$CODE_DIR/scripts" "$APP_DIR/scripts"
    chmod +x "$APP_DIR/scripts"/*.sh
    chmod +x "$APP_DIR/vapor"/*.sh
fi

echo ">>> [3/5] Build docker images"
cd "$APP_DIR"

# Try building with legacy builder if BuildKit fails
echo "  - Building vapor image..."
if ! docker compose build vapor 2>&1; then
    echo "  ⚠️  BuildKit failed, trying with legacy builder..."
    DOCKER_BUILDKIT=0 docker compose build vapor
fi

echo ">>> [4/5] Restart containers"
docker compose up -d

echo ">>> [5/5] Status"
docker compose ps
echo ""
echo "Recent vapor logs:"
docker compose logs vapor --tail 30
echo ""
echo "Recent postgres logs:"
docker compose logs postgres --tail 10

echo ""
echo "✅ Deployment complete!"
echo ""
echo "Next steps:"
echo "  1. Check logs: docker compose logs -f vapor"
echo "  2. Run initial sync: ./scripts/run-sync.sh"
echo "  3. Setup cron for automatic sync: ./scripts/setup-cron.sh"
