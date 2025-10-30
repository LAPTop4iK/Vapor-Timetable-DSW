# Quick Start Guide for VPS Deployment

## Your Server Setup

```
/srv/app/
├── .env                    ← Edit this with your DB password
├── docker-compose.yml      ← Auto-copied from vapor/
├── redeploy.sh             ← Main deployment script
├── nginx/                  ← Your existing nginx
├── scripts/                ← Auto-copied from vapor/
└── vapor/                  ← Git repository
```

## First Time Setup

### 1. Deploy Code

```bash
cd /srv/app
./redeploy.sh
```

This will automatically:
- Pull latest code
- Copy `vapor/docker-compose.production.yml` → `docker-compose.yml`
- Copy `vapor/.env.production.example` → `.env` (first time only)
- Copy `vapor/scripts/` → `scripts/`
- Build and start containers

### 2. Configure Database Password

**IMPORTANT:** Set your secure password:

```bash
nano /srv/app/.env
```

Change this line:
```bash
DB_PASSWORD=your_secure_password_here
```

Then restart:
```bash
cd /srv/app
docker compose restart
```

### 3. Build SyncRunner

```bash
cd /srv/app
./scripts/build-sync.sh
```

### 4. Run Initial Sync

This populates PostgreSQL with data (~2-3 hours):

```bash
cd /srv/app
./scripts/run-sync.sh
```

### 5. Setup Automatic Sync

Daily sync at 3 AM:

```bash
cd /srv/app
./scripts/setup-cron.sh
```

## Done! 🎉

Your API is now running:
- **Internal**: http://vapor:8080
- **Through nginx**: https://your-domain.com

## Regular Updates

When you push new code:

```bash
cd /srv/app
./redeploy.sh
```

## Quick Commands

```bash
# View logs
docker compose logs -f vapor

# Restart services
docker compose restart

# Check database
docker compose exec postgres psql -U vapor -d dsw_timetable

# Manual sync
./scripts/run-sync.sh

# Check sync status
SELECT * FROM sync_status ORDER BY timestamp DESC LIMIT 1;
```

## Files Explained

| File in Repository | Copied To | Purpose |
|-------------------|-----------|---------|
| `docker-compose.production.yml` | `/srv/app/docker-compose.yml` | Defines vapor + postgres + nginx |
| `.env.production.example` | `/srv/app/.env` | Environment configuration |
| `scripts/build-sync.sh` | `/srv/app/scripts/` | Builds SyncRunner image |
| `scripts/run-sync.sh` | `/srv/app/scripts/` | Runs manual sync |
| `scripts/setup-cron.sh` | `/srv/app/scripts/` | Sets up automatic sync |
| `Dockerfile` | Used in vapor/ | Builds API server |
| `Dockerfile.sync` | Used in vapor/ | Builds SyncRunner |

## Troubleshooting

### API not responding
```bash
docker compose logs vapor
docker compose restart vapor
```

### No data (404 errors)
```bash
# Check if sync ran
docker compose exec postgres psql -U vapor -d dsw_timetable -c "SELECT COUNT(*) FROM groups;"

# If 0, run sync
./scripts/run-sync.sh
```

### Database connection failed
```bash
# Check password in .env
cat /srv/app/.env | grep DB_PASSWORD

# Restart everything
docker compose restart
```

## Need Help?

Read the full guide: `DEPLOYMENT_VPS.md`
