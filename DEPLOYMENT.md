# DSW Timetable API - Deployment Guide

This guide explains how to deploy the DSW Timetable API with Firestore preloading architecture on your VPS.

## Architecture Overview

The system consists of two components:

1. **Vapor API Server** (`DswAggregator`) - Serves HTTP requests from mobile app
2. **Sync Runner** (`SyncRunner`) - Periodically syncs data from university to Firestore

### Data Flow

```
University Website
       ↓
  SyncRunner (runs 2x daily via cron)
       ↓
  Firestore
       ↓
  Vapor API Server
       ↓
  Mobile App
```

## Prerequisites

1. **VPS with Docker** (you already have this)
2. **Google Cloud Project** with Firestore enabled
3. **Service Account JSON key** with Firestore permissions

## Step 1: Setup Firestore

### 1.1 Create Google Cloud Project

```bash
# Visit https://console.cloud.google.com
# Create new project or use existing one
```

### 1.2 Enable Firestore

```bash
# In Google Cloud Console:
# 1. Navigate to Firestore
# 2. Select "Native mode"
# 3. Choose europe-west3 (Frankfurt) for lowest latency to Poland
# 4. Create database
```

### 1.3 Create Service Account

```bash
# In Google Cloud Console:
# 1. Go to IAM & Admin > Service Accounts
# 2. Create Service Account
# 3. Grant roles:
#    - Cloud Datastore User
# 4. Create JSON key
# 5. Download the JSON file
```

### 1.4 Upload Service Account to VPS

```bash
# On your local machine:
scp firestore-service-account.json root@your-vps:/srv/secrets/

# On VPS:
chmod 600 /srv/secrets/firestore-service-account.json
```

## Step 2: Update Environment Variables

Edit your docker-compose.yml or environment file to add:

```yaml
services:
  vapor:
    environment:
      # ... existing vars ...

      # Backend mode: "live" or "cached"
      - DSW_BACKEND_MODE=cached

      # Firestore configuration
      - FIRESTORE_PROJECT_ID=your-project-id
      - FIRESTORE_CREDENTIALS_PATH=/run/secrets/firestore-service-account.json

    volumes:
      - /srv/secrets/firestore-service-account.json:/run/secrets/firestore-service-account.json:ro
```

## Step 3: Build Sync Runner

```bash
# On VPS, in /srv/app/vapor directory:
cd /srv/app/vapor

# Make scripts executable
chmod +x scripts/*.sh

# Build sync-runner image
./scripts/build-sync.sh
```

## Step 4: Initial Data Sync

**IMPORTANT:** Before switching to cached mode, you must run the initial sync to populate Firestore.

```bash
# Run sync manually (this will take ~2-3 hours for 1400 groups):
./scripts/run-sync.sh

# Monitor progress:
tail -f /var/log/dsw-sync/latest.log
```

### What the sync does:

1. Fetches all ~1400 groups from university
2. For each group:
   - Downloads semester schedule
   - Extracts unique teachers
   - Downloads teacher details and schedules
   - Saves to Firestore
3. Updates groups list metadata
4. Updates sync status

### Throttling:

- 150ms delay between groups (configurable via `SYNC_DELAY_GROUPS_MS`)
- 100ms delay between teachers (configurable via `SYNC_DELAY_TEACHERS_MS`)

Total runtime: ~2-3 hours depending on university server response time.

## Step 5: Setup Automated Sync

```bash
# Setup cron to run sync twice daily (3 AM and 3 PM)
./scripts/setup-cron.sh

# Verify cron is configured:
crontab -l
```

## Step 6: Switch API to Cached Mode

### 6.1 Update Environment

```bash
# Edit docker-compose.yml or .env file:
DSW_BACKEND_MODE=cached
```

### 6.2 Restart Vapor

```bash
cd /srv/app
docker-compose restart vapor
```

### 6.3 Verify

```bash
# Check logs:
docker logs -f vapor

# Should see:
# "Firestore initialized for project: your-project-id"

# Test API:
curl https://api.dsw.wtf/groups/search?q=sem
curl https://api.dsw.wtf/api/groups/123/aggregate
```

## Step 7: Monitoring

### Check Sync Logs

```bash
# Latest sync log:
cat /var/log/dsw-sync/latest.log

# All sync logs:
ls -lh /var/log/dsw-sync/

# Watch live sync:
tail -f /var/log/dsw-sync/latest.log
```

### Check Sync Status

The sync status is stored in Firestore at `/metadata/lastSync`:

```json
{
  "timestamp": "2025-01-15T03:00:00Z",
  "status": "ok",
  "totalGroups": 1400,
  "processedGroups": 1400,
  "failedGroups": 0,
  "duration": 7200.5,
  "startedAt": "2025-01-15T01:00:00Z"
}
```

### Manual Sync Trigger

```bash
# Run sync manually anytime:
./scripts/run-sync.sh

# Or via Docker directly:
docker run --rm \
    -e FIRESTORE_PROJECT_ID=your-project-id \
    -e FIRESTORE_CREDENTIALS_PATH=/run/secrets/firestore-service-account.json \
    -v /srv/secrets/firestore-service-account.json:/run/secrets/firestore-service-account.json:ro \
    dsw-sync-runner:latest
```

## Firestore Collections Structure

```
/groups/{groupId}
  - groupId: Int
  - from: String
  - to: String
  - intervalType: Int
  - groupSchedule: [ScheduleEvent]
  - teacherIds: [Int]
  - groupInfo: { code, name, tracks, program, faculty }
  - fetchedAt: String

/teachers/{teacherId}
  - id: Int
  - name: String
  - title: String
  - department: String
  - email: String
  - phone: String
  - aboutHTML: String
  - schedule: [ScheduleEvent]
  - fetchedAt: String

/metadata/groupsList
  - groups: [GroupInfo]
  - updatedAt: String

/metadata/lastSync
  - timestamp: String
  - status: String ("ok" | "error" | "in_progress")
  - totalGroups: Int
  - processedGroups: Int
  - failedGroups: Int
  - errorMessage: String?
  - duration: Double
  - startedAt: String
```

## API Endpoints

All endpoints maintain the same response format as before:

### `GET /api/groups/:groupId/aggregate`

**Before (live mode):** Scrapes university site on each request
**After (cached mode):** Reads from Firestore

Returns:
- Group schedule
- **ALL teachers** (not just from this group)
- Group metadata

### `GET /groups/search?q=query`

**Before (live mode):** Searches university site
**After (cached mode):** Filters Firestore groups list

### `GET /api/groups/:groupId/schedule`

**Always live** - fetches current day schedule from university
Uses in-memory cache (TTL: 60 seconds)

## Environment Variables Reference

### Vapor API Server

```bash
# Runtime mode
ENV=production

# Backend mode
DSW_BACKEND_MODE=live          # or "cached"

# Default semester dates
DSW_DEFAULT_FROM=2025-09-06
DSW_DEFAULT_TO=2026-02-08
DSW_DEFAULT_INTERVAL=semester   # week / month / semester

# Cache TTLs (seconds)
DSW_TTL_SCHEDULE_SECS=60
DSW_TTL_SEARCH_SECS=259200
DSW_TTL_AGGREGATE_SECS=18000
DSW_TTL_TEACHER_SECS=18000

# Firestore
FIRESTORE_PROJECT_ID=your-project-id
FIRESTORE_CREDENTIALS_PATH=/run/secrets/firestore-service-account.json
```

### Sync Runner

```bash
# Firestore (required)
FIRESTORE_PROJECT_ID=your-project-id
FIRESTORE_CREDENTIALS_PATH=/run/secrets/firestore-service-account.json

# Semester dates
DSW_DEFAULT_FROM=2025-09-06
DSW_DEFAULT_TO=2026-02-08

# Throttling (milliseconds)
SYNC_DELAY_GROUPS_MS=150
SYNC_DELAY_TEACHERS_MS=100
```

## Troubleshooting

### Sync fails with "403 Forbidden"

- Check service account has correct permissions
- Verify `FIRESTORE_PROJECT_ID` matches your GCP project
- Ensure JSON key file is readable

### Sync is too slow

Increase delays to avoid rate limiting:
```bash
SYNC_DELAY_GROUPS_MS=200
SYNC_DELAY_TEACHERS_MS=150
```

### API returns 404 for groups

- Ensure initial sync completed successfully
- Check `/metadata/lastSync` in Firestore
- Verify `DSW_BACKEND_MODE=cached`

### Mobile app shows old data

- Check last sync timestamp
- Verify cron is running: `systemctl status cron`
- Check sync logs: `cat /var/log/dsw-sync/latest.log`

## Rollback to Live Mode

If you need to rollback to scraping live:

```bash
# 1. Update environment:
DSW_BACKEND_MODE=live

# 2. Restart Vapor:
docker-compose restart vapor
```

API will immediately switch back to scraping university site on each request.

## Costs Estimate

### Firestore (Native Mode)

For ~1400 groups + ~500 teachers:

- **Storage:** ~50MB = $0.01/month
- **Reads:** ~10,000/day = $0.40/month
- **Writes:** 2 syncs/day × 2000 docs = $0.20/month

**Total:** ~$0.60/month (well within free tier: $0.60/month free)

### Network

VPS in Poland → Firestore in Frankfurt: minimal latency (~10-20ms)

## Support

For issues or questions:
- Check logs: `/var/log/dsw-sync/`
- Review Firestore console: https://console.cloud.google.com/firestore
- Verify cron: `crontab -l`
