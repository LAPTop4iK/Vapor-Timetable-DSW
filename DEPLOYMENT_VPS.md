# DSW Timetable API - VPS Deployment Guide

Complete deployment guide for your VPS with existing nginx setup.

## Server Structure

```
/srv/app/
├── .env                        # Environment configuration (YOU MUST EDIT THIS)
├── docker-compose.yml          # Auto-copied from vapor/docker-compose.production.yml
├── redeploy.sh                 # Main deployment script
├── nginx/
│   ├── nginx.conf             # Your nginx configuration
│   └── certs/                 # SSL certificates
│       ├── fullchain.pem
│       └── privkey.pem
├── scripts/                    # Auto-copied from vapor/scripts/
│   ├── build-sync.sh          # Build SyncRunner image
│   ├── run-sync.sh            # Run manual sync
│   └── setup-cron.sh          # Setup automatic sync
└── vapor/                      # Git repository (auto-updated)
    ├── Sources/
    ├── Dockerfile              # API server image
    ├── Dockerfile.sync         # SyncRunner image
    └── docker-compose.production.yml
```

## Architecture

```
University Website
       ↓
  SyncRunner (cron: 2x daily)
       ↓
  PostgreSQL (Docker container)
       ↓
  Vapor API (Docker container)
       ↓
  Nginx (reverse proxy)
       ↓
  Mobile App
```

## Initial Setup (First Time Only)

### Step 1: Pull Latest Code

```bash
cd /srv/app
./redeploy.sh
```

This will:
- Pull latest code from git
- Copy `docker-compose.production.yml` → `docker-compose.yml`
- Copy `.env.production` → `.env` (only if .env doesn't exist)
- Copy `scripts/` directory
- Build and start containers

### Step 2: Configure Environment

**IMPORTANT**: Edit your environment file:

```bash
nano /srv/app/.env
```

Set your secure database password:
```bash
DB_PASSWORD=your_very_secure_password_here
```

Other important settings:
```bash
# Backend mode: cached (fast, uses DB) or live (slow, scrapes on request)
DSW_BACKEND_MODE=cached

# Semester dates (update each semester)
DSW_DEFAULT_FROM=2025-09-06
DSW_DEFAULT_TO=2026-02-08

# Sync delays (adjust if university rate-limits you)
SYNC_DELAY_GROUPS_MS=150        # 150ms between group fetches
SYNC_DELAY_TEACHERS_MS=100      # 100ms between teacher fetches
```

### Step 3: Restart with New Configuration

```bash
cd /srv/app
docker compose down
docker compose up -d
```

Check logs:
```bash
docker compose logs -f vapor
docker compose logs -f postgres
```

### Step 4: Build SyncRunner Image

```bash
cd /srv/app
./scripts/build-sync.sh
```

### Step 5: Run Initial Sync

This will populate PostgreSQL with all groups and teachers (~2-3 hours):

```bash
cd /srv/app
./scripts/run-sync.sh
```

Monitor progress:
```bash
docker compose logs -f
```

### Step 6: Setup Automatic Sync (Cron)

Setup daily sync at 3 AM:

```bash
cd /srv/app
./scripts/setup-cron.sh
```

Verify cron is installed:
```bash
crontab -l
```

Check sync logs:
```bash
tail -f /srv/app/sync-cron.log
```

### Step 7: Update Nginx Configuration (if needed)

Your existing nginx should proxy to `vapor:8080`. Verify your `/srv/app/nginx/nginx.conf` has:

```nginx
upstream vapor_backend {
    server vapor:8080;
}

server {
    listen 443 ssl http2;
    server_name your-domain.com;

    location / {
        proxy_pass http://vapor_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

If you need to update nginx:
```bash
docker compose restart nginx
```

## Regular Deployments

When you push new code to git:

```bash
cd /srv/app
./redeploy.sh
```

This will:
1. Pull latest code from git
2. Copy updated files (docker-compose, scripts)
3. Rebuild Docker images
4. Restart containers
5. Show logs

## Monitoring

### Check API Status

```bash
# API logs
docker compose logs -f vapor

# Check if API is responding
curl http://localhost:8080/api/feature-flags

# Or through nginx
curl https://your-domain.com/api/feature-flags
```

### Check Database

```bash
# Connect to PostgreSQL
docker compose exec postgres psql -U vapor -d dsw_timetable

# Check last sync status
SELECT timestamp, status, total_groups, processed_groups, failed_groups,
       ROUND(duration::numeric, 2) as duration_secs
FROM sync_status
ORDER BY timestamp DESC
LIMIT 5;

# Check data counts
SELECT
    (SELECT COUNT(*) FROM groups) as groups_count,
    (SELECT COUNT(*) FROM teachers) as teachers_count,
    (SELECT COUNT(*) FROM groups_list) as lists_count;

# Exit postgres
\q
```

### Check Sync Cron

```bash
# View cron log
tail -f /srv/app/sync-cron.log

# Check crontab
crontab -l

# Test sync manually
/srv/app/scripts/run-sync.sh
```

### Check Disk Space

```bash
# Docker volumes
docker system df

# PostgreSQL data
du -sh /var/lib/docker/volumes/app_postgres_data

# Container logs
docker compose logs --tail=100 vapor
docker compose logs --tail=100 postgres
```

## Troubleshooting

### API Not Responding

```bash
# Check if container is running
docker compose ps

# Check logs
docker compose logs vapor --tail=100

# Restart vapor
docker compose restart vapor
```

### Database Connection Failed

```bash
# Check postgres is running
docker compose ps postgres

# Check postgres logs
docker compose logs postgres

# Check connection from vapor
docker compose exec vapor sh -c 'nc -zv postgres 5432'

# Restart everything
docker compose restart
```

### No Data in API (404 errors)

```bash
# Check if sync ran successfully
docker compose exec postgres psql -U vapor -d dsw_timetable -c "SELECT COUNT(*) FROM groups;"

# If 0, run sync
./scripts/run-sync.sh

# Check sync logs
tail -f /srv/app/sync-cron.log
```

### Sync Failing

```bash
# Check SyncRunner logs from last run
docker compose logs | grep -A 50 "Sync Runner starting"

# Test sync manually with verbose output
./scripts/run-sync.sh

# If rate-limited, increase delays in .env
nano /srv/app/.env
# Change:
SYNC_DELAY_GROUPS_MS=200
SYNC_DELAY_TEACHERS_MS=150

# Restart and retry
docker compose restart
./scripts/run-sync.sh
```

### Nginx Not Working

```bash
# Check nginx logs
docker compose logs nginx

# Test nginx config
docker compose exec nginx nginx -t

# Restart nginx
docker compose restart nginx
```

## Backup

### Database Backup

```bash
# Backup PostgreSQL
docker compose exec postgres pg_dump -U vapor dsw_timetable > /srv/app/backups/db-$(date +%Y%m%d).sql

# Create backup directory
mkdir -p /srv/app/backups
```

### Automated Backup (Optional)

Add to crontab:
```bash
crontab -e

# Add line:
0 4 * * * docker compose -f /srv/app/docker-compose.yml exec -T postgres pg_dump -U vapor dsw_timetable > /srv/app/backups/db-$(date +\%Y\%m\%d).sql
```

### Restore from Backup

```bash
# Stop API
docker compose stop vapor

# Restore database
cat /srv/app/backups/db-20250130.sql | docker compose exec -T postgres psql -U vapor dsw_timetable

# Start API
docker compose start vapor
```

## Environment Variables Reference

### Required Variables (.env)

```bash
# Database (REQUIRED - must be secure)
DB_PASSWORD=your_secure_password

# Optional with defaults
DB_USER=vapor
DB_NAME=dsw_timetable
```

### Optional Variables

```bash
# Runtime
ENV=production
LOG_LEVEL=info

# Backend mode
DSW_BACKEND_MODE=cached  # or "live"

# Semester dates
DSW_DEFAULT_FROM=2025-09-06
DSW_DEFAULT_TO=2026-02-08

# Cache TTLs (seconds)
DSW_TTL_SCHEDULE_SECS=60
DSW_TTL_SEARCH_SECS=259200
DSW_TTL_AGGREGATE_SECS=18000
DSW_TTL_TEACHER_SECS=18000

# Sync delays (milliseconds)
SYNC_DELAY_GROUPS_MS=150
SYNC_DELAY_TEACHERS_MS=100

# Feature flags (JSON)
DSW_FEATURE_FLAGS_JSON={"show_ads":true,"show_debug_menu":false}
DSW_FEATURE_FLAGS_VERSION=1.0.1
```

## Performance Tuning

### For Faster Sync (use with caution)

```bash
# Reduce delays (may trigger rate limiting)
SYNC_DELAY_GROUPS_MS=100
SYNC_DELAY_TEACHERS_MS=50
```

### For Avoiding Rate Limits

```bash
# Increase delays
SYNC_DELAY_GROUPS_MS=200
SYNC_DELAY_TEACHERS_MS=150
```

### Change Sync Schedule

```bash
# Run sync every 6 hours instead of daily
CRON_TIME='0 */6 * * *' ./scripts/setup-cron.sh

# Run sync at 2 AM and 2 PM
CRON_TIME='0 2,14 * * *' ./scripts/setup-cron.sh

# Run sync every day at 3 AM (default)
./scripts/setup-cron.sh
```

## API Endpoints

### Health Check
```bash
GET /api/feature-flags
```

### Get Group Schedule with Teachers
```bash
GET /api/groups/:groupId/aggregate?from=2025-09-06&to=2026-02-08&type=3
```

### Search Groups
```bash
GET /groups/search?q=informatyka
```

### Get Today's Schedule
```bash
GET /api/groups/:groupId/schedule
```

## Production Checklist

Before going live:

- [ ] Set secure DB_PASSWORD in /srv/app/.env
- [ ] Run initial sync successfully
- [ ] Setup cron for automatic sync
- [ ] Configure nginx for your domain
- [ ] Test HTTPS works
- [ ] Setup database backups
- [ ] Configure log rotation
- [ ] Monitor disk space
- [ ] Test API endpoints
- [ ] Test mobile app connection

## Quick Commands Reference

```bash
# Deploy latest code
cd /srv/app && ./redeploy.sh

# View logs
docker compose logs -f vapor
docker compose logs -f postgres

# Restart services
docker compose restart

# Run manual sync
/srv/app/scripts/run-sync.sh

# Check database
docker compose exec postgres psql -U vapor -d dsw_timetable

# Backup database
docker compose exec postgres pg_dump -U vapor dsw_timetable > backup.sql

# Check disk space
docker system df
```

## Getting Help

1. Check logs: `docker compose logs -f`
2. Check database: `docker compose exec postgres psql -U vapor -d dsw_timetable`
3. Check sync logs: `tail -f /srv/app/sync-cron.log`
4. Test API: `curl http://localhost:8080/api/feature-flags`
