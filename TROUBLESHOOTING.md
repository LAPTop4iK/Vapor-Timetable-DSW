# Troubleshooting Guide

## Build Errors

### Error: `failed to execute bake: read |0: file already closed`

**Problem:** Docker BuildKit fails during image build

**Solution 1:** Use legacy Docker builder

```bash
cd /srv/app
export DOCKER_BUILDKIT=0
docker compose build vapor
```

**Solution 2:** Use alternative build script

```bash
cd /srv/app/vapor
./build-alternative.sh
```

**Solution 3:** Increase Docker resources

Edit `/etc/docker/daemon.json`:
```json
{
  "builder": {
    "gc": {
      "enabled": true,
      "defaultKeepStorage": "20GB"
    }
  }
}
```

Then restart Docker:
```bash
systemctl restart docker
```

**Solution 4:** Clean Docker cache

```bash
docker builder prune -a
docker system prune -a
```

### Error: `The "DB_PASSWORD" variable is not set`

**Problem:** `.env` file missing or DB_PASSWORD not set

**Solution:**

```bash
# Check if .env exists
ls -la /srv/app/.env

# If not, create from template
cp /srv/app/vapor/.env.production.example /srv/app/.env

# Edit and set password
nano /srv/app/.env
# Change: DB_PASSWORD=your_secure_password_here

# Verify
cat /srv/app/.env | grep DB_PASSWORD
```

### Error: `version is obsolete`

**Problem:** Old docker-compose.yml format

**Solution:** Already fixed in latest code. Just pull:

```bash
cd /srv/app
./redeploy.sh
```

### Build gets stuck at "swift package resolve"

**Problem:** Network issues or Swift package server slow

**Solution:**

```bash
# Cancel build (Ctrl+C)

# Try again (uses cached layers)
cd /srv/app
docker compose build vapor

# If still fails, clean and rebuild
docker compose build --no-cache vapor
```

### Error: `Cannot connect to the Docker daemon`

**Problem:** Docker service not running

**Solution:**

```bash
# Start Docker
systemctl start docker
systemctl enable docker

# Check status
systemctl status docker

# Check if you can run docker commands
docker ps
```

## Runtime Errors

### API not responding (502 Bad Gateway from nginx)

**Check 1:** Is vapor container running?

```bash
docker compose ps
```

**Check 2:** Check vapor logs

```bash
docker compose logs vapor --tail=50
```

**Check 3:** Check if vapor is listening

```bash
docker compose exec vapor sh -c 'nc -zv localhost 8080'
```

**Solution:** Restart vapor

```bash
docker compose restart vapor
docker compose logs -f vapor
```

### Database connection failed

**Check 1:** Is postgres running?

```bash
docker compose ps postgres
docker compose logs postgres --tail=20
```

**Check 2:** Check password in .env

```bash
cat /srv/app/.env | grep DB_PASSWORD
```

**Check 3:** Test connection from vapor

```bash
docker compose exec vapor sh -c 'nc -zv postgres 5432'
```

**Solution:** Restart both services

```bash
docker compose restart postgres vapor
```

### No data in API (404 errors)

**Check 1:** Did sync run successfully?

```bash
docker compose exec postgres psql -U vapor -d dsw_timetable -c "SELECT COUNT(*) FROM groups;"
```

**Check 2:** Check sync status

```bash
docker compose exec postgres psql -U vapor -d dsw_timetable -c "SELECT * FROM sync_status ORDER BY timestamp DESC LIMIT 1;"
```

**Solution:** Run sync

```bash
cd /srv/app
./scripts/run-sync.sh
```

### Sync fails with rate limiting

**Problem:** University server blocking too many requests

**Solution:** Increase delays in .env

```bash
nano /srv/app/.env

# Increase these values
SYNC_DELAY_GROUPS_MS=250
SYNC_DELAY_TEACHERS_MS=200

# Restart and retry
docker compose restart
./scripts/run-sync.sh
```

## Disk Space Issues

### Error: `no space left on device`

**Check disk usage:**

```bash
df -h
docker system df
```

**Clean Docker:**

```bash
# Remove unused containers
docker container prune

# Remove unused images
docker image prune -a

# Remove unused volumes (CAUTION: may delete data)
docker volume prune

# Remove everything unused
docker system prune -a --volumes
```

**Clean logs:**

```bash
# Truncate large log files
truncate -s 0 /srv/app/sync-cron.log

# Setup log rotation (create /etc/logrotate.d/dsw-sync)
cat > /etc/logrotate.d/dsw-sync << 'LOGROTATE'
/srv/app/sync-cron.log {
    daily
    rotate 7
    compress
    delaycompress
    notifempty
    missingok
}
LOGROTATE
```

## Network Issues

### Cannot reach API from outside

**Check 1:** Is nginx running?

```bash
docker compose ps nginx
```

**Check 2:** Check nginx config

```bash
docker compose exec nginx nginx -t
```

**Check 3:** Check firewall

```bash
# Check if port 443 is open
netstat -tulpn | grep :443

# Check iptables
iptables -L -n
```

**Check 4:** Check nginx logs

```bash
docker compose logs nginx --tail=50
```

### SSL certificate errors

**Check certificate files:**

```bash
ls -la /srv/app/nginx/certs/
```

**Test certificate:**

```bash
openssl x509 -in /srv/app/nginx/certs/fullchain.pem -text -noout
```

**Renew Let's Encrypt certificate:**

```bash
certbot renew
# Copy new certs to /srv/app/nginx/certs/
docker compose restart nginx
```

## Performance Issues

### API slow (>1s response time)

**Check 1:** Backend mode

```bash
docker compose exec vapor sh -c 'env | grep DSW_BACKEND_MODE'
```

Should be `cached` for fast responses.

**Check 2:** Check database

```bash
# Check if data exists
docker compose exec postgres psql -U vapor -d dsw_timetable -c "SELECT COUNT(*) FROM groups;"

# Check last sync
docker compose exec postgres psql -U vapor -d dsw_timetable -c "SELECT timestamp FROM sync_status ORDER BY timestamp DESC LIMIT 1;"
```

**Solution:** Switch to cached mode

```bash
nano /srv/app/.env
# Set: DSW_BACKEND_MODE=cached

docker compose restart vapor
```

### High memory usage

**Check memory:**

```bash
docker stats --no-stream
```

**Solution:** Limit container memory

Edit `/srv/app/docker-compose.yml`:

```yaml
services:
  vapor:
    # ... existing config ...
    deploy:
      resources:
        limits:
          memory: 1G
        reservations:
          memory: 512M
```

Then restart:

```bash
docker compose up -d
```

## Cron Issues

### Sync not running automatically

**Check crontab:**

```bash
crontab -l
```

**Check cron logs:**

```bash
tail -f /srv/app/sync-cron.log
```

**Check if cron service is running:**

```bash
systemctl status cron
```

**Solution:** Reinstall cron job

```bash
cd /srv/app
./scripts/setup-cron.sh
```

## Emergency Rollback

### Switch to live mode immediately

If cached mode has issues, switch to live scraping:

```bash
# 1. Edit .env
nano /srv/app/.env
# Change: DSW_BACKEND_MODE=live

# 2. Restart vapor only (don't need postgres for live mode)
docker compose restart vapor

# 3. Verify
curl http://localhost:8080/api/feature-flags
```

### Restore from backup

```bash
# Stop API
docker compose stop vapor

# Restore database
cat /srv/app/backups/db-20250130.sql | \
  docker compose exec -T postgres psql -U vapor dsw_timetable

# Start API
docker compose start vapor
```

## Getting More Help

### Collect diagnostic information

```bash
# Create diagnostic report
cat > /tmp/dsw-diagnostics.txt << DIAG
=== Docker Status ===
$(docker compose ps)

=== Vapor Logs (last 50 lines) ===
$(docker compose logs vapor --tail=50)

=== Postgres Logs (last 20 lines) ===
$(docker compose logs postgres --tail=20)

=== Environment ===
$(cat /srv/app/.env | grep -v PASSWORD)

=== Disk Space ===
$(df -h)

=== Docker Disk Usage ===
$(docker system df)

=== Sync Status ===
$(docker compose exec -T postgres psql -U vapor -d dsw_timetable -c "SELECT * FROM sync_status ORDER BY timestamp DESC LIMIT 3;")

=== Groups Count ===
$(docker compose exec -T postgres psql -U vapor -d dsw_timetable -c "SELECT COUNT(*) FROM groups;")
DIAG

cat /tmp/dsw-diagnostics.txt
```

### Useful commands

```bash
# Full restart
docker compose down && docker compose up -d

# Rebuild everything from scratch
docker compose down -v
docker compose build --no-cache
docker compose up -d

# Check what's consuming disk
du -sh /var/lib/docker/volumes/*
docker system df -v

# Watch logs in real-time
docker compose logs -f vapor postgres

# Execute SQL query
docker compose exec postgres psql -U vapor -d dsw_timetable -c "YOUR_QUERY_HERE"
```
