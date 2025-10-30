# DSW Timetable API - Deployment Guide

Simple deployment guide for running the DSW Timetable API with PostgreSQL on VPS.

## Architecture Overview

```
University Website
       ↓
  SyncRunner (runs 2x daily via cron)
       ↓
  PostgreSQL (on VPS)
       ↓
  Vapor API Server (on VPS)
       ↓
  Mobile App
```

## Two Modes

### Live Mode (`DSW_BACKEND_MODE=live`)
- API scrapes university site on each request
- Data always current but slower (~2-5 seconds)
- Uses in-memory cache (60s for schedule, 5h for aggregate)
- No database required

### Cached Mode (`DSW_BACKEND_MODE=cached`)
- API reads from PostgreSQL
- Fast response (~100-200ms)
- Data updated 2x daily via SyncRunner
- Requires PostgreSQL + cron

## Quick Start with Docker Compose

### 1. Clone and Configure

```bash
cd /srv/app
git clone <your-repo>
cd Vapor-Timetable-DSW

# Create .env from example
cp .env.example .env

# Edit .env and set secure password
nano .env
```

### 2. Start Services

```bash
# Start PostgreSQL + Vapor
docker-compose up -d

# Check logs
docker-compose logs -f vapor
docker-compose logs -f postgres
```

That's it! API is running at http://localhost:8080

### 3. Initial Sync (for cached mode)

```bash
# Build sync runner image
./scripts/build-sync.sh

# Run initial sync (takes ~2-3 hours for 1400 groups)
./scripts/run-sync.sh

# Monitor progress
tail -f /var/log/dsw-sync/latest.log
```

### 4. Setup Cron (optional, for cached mode)

```bash
# Setup automatic sync 2x daily (3 AM and 3 PM)
./scripts/setup-cron.sh

# Verify
crontab -l
```

## Environment Variables

### API Server (.env)

```bash
# PostgreSQL password (required)
POSTGRES_PASSWORD=your_secure_password

# Backend mode
DSW_BACKEND_MODE=cached  # or "live"

# Semester dates
DSW_DEFAULT_FROM=2025-09-06
DSW_DEFAULT_TO=2026-02-08

# Cache TTLs (seconds)
DSW_TTL_SCHEDULE_SECS=60
DSW_TTL_AGGREGATE_SECS=18000

# Sync delays (milliseconds)
SYNC_DELAY_GROUPS_MS=150
SYNC_DELAY_TEACHERS_MS=100
```

## Database Schema

PostgreSQL stores 4 tables:

- **groups** - group schedules and metadata
- **teachers** - teacher info and schedules
- **groups_list** - searchable groups list
- **sync_status** - last sync status

Migrations run automatically on startup.

## API Endpoints

All endpoints work in both live and cached modes:

### `GET /api/groups/:groupId/aggregate`
Full group info: schedule + all teachers

Query params:
- `from` - start date (YYYY-MM-DD)
- `to` - end date (YYYY-MM-DD)
- `type` - interval (0=week, 1=month, 2=semester)

Example:
```bash
curl http://localhost:8080/api/groups/123/aggregate
```

### `GET /groups/search?q=query`
Search groups by name/code/program/faculty

Example:
```bash
curl http://localhost:8080/groups/search?q=informatyka
```

### `GET /api/groups/:groupId/schedule`
Current day schedule (always live, 60s cache)

## Sync Process

SyncRunner:
1. Fetches all ~1400 groups from university
2. For each group:
   - Downloads semester schedule
   - Extracts unique teachers (~500 total)
   - Downloads teacher details
   - Saves to PostgreSQL
3. Updates groups list
4. Updates sync status

Runtime: ~2-3 hours with throttling (150ms between groups)

## Monitoring

### Check Logs

```bash
# API logs
docker logs -f dsw-vapor

# Postgres logs
docker logs -f dsw-postgres

# Sync logs
cat /var/log/dsw-sync/latest.log
ls -lh /var/log/dsw-sync/
```

### Check Sync Status

```bash
# Connect to postgres
docker exec -it dsw-postgres psql -U vapor -d dsw_timetable

# Check last sync
SELECT timestamp, status, total_groups, processed_groups, failed_groups, duration
FROM sync_status
ORDER BY timestamp DESC
LIMIT 1;

# Check data counts
SELECT COUNT(*) FROM groups;
SELECT COUNT(*) FROM teachers;
```

### Manual Sync

```bash
# Run sync anytime
./scripts/run-sync.sh
```

## Troubleshooting

### API returns 404 for groups

```bash
# 1. Check if sync completed
cat /var/log/dsw-sync/latest.log

# 2. Check database
docker exec -it dsw-postgres psql -U vapor -d dsw_timetable -c "SELECT COUNT(*) FROM groups;"

# 3. Verify backend mode
docker logs dsw-vapor | grep "Backend mode"
```

### Sync is too slow

Increase delays to avoid rate limiting:

```bash
# Edit .env
SYNC_DELAY_GROUPS_MS=200
SYNC_DELAY_TEACHERS_MS=150

# Rebuild and restart
docker-compose down
./scripts/build-sync.sh
```

### Database connection failed

```bash
# Check postgres is running
docker ps | grep postgres

# Check connection
docker exec -it dsw-postgres pg_isready -U vapor

# Restart services
docker-compose restart
```

## Backup

### Database Backup

```bash
# Backup
docker exec dsw-postgres pg_dump -U vapor dsw_timetable > backup.sql

# Restore
cat backup.sql | docker exec -i dsw-postgres psql -U vapor dsw_timetable
```

### Volume Backup

```bash
# Stop services
docker-compose down

# Backup volume
docker run --rm -v vapor-timetable-dsw_postgres_data:/data -v $(pwd):/backup alpine tar czf /backup/postgres-backup.tar.gz /data

# Restore
docker run --rm -v vapor-timetable-dsw_postgres_data:/data -v $(pwd):/backup alpine tar xzf /backup/postgres-backup.tar.gz -C /
```

## Production Checklist

- [ ] Set secure POSTGRES_PASSWORD in .env
- [ ] Configure firewall (allow 8080, block 5432 from outside)
- [ ] Setup HTTPS reverse proxy (nginx/traefik)
- [ ] Configure log rotation
- [ ] Setup monitoring (uptime, disk space)
- [ ] Schedule regular database backups
- [ ] Test sync runs successfully

## Rollback to Live Mode

If issues with cached mode:

```bash
# 1. Edit .env
DSW_BACKEND_MODE=live

# 2. Restart API
docker-compose restart vapor
```

API immediately switches to scraping university site.

## Resources

- Vapor Docs: https://docs.vapor.codes
- Fluent Docs: https://docs.vapor.codes/fluent/overview/
- PostgreSQL Docs: https://www.postgresql.org/docs/

## Support

Check logs first:
- API: `docker logs dsw-vapor`
- Database: `docker logs dsw-postgres`
- Sync: `/var/log/dsw-sync/latest.log`
