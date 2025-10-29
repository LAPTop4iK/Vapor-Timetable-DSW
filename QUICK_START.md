# Быстрый старт: Миграция на Firestore

Это краткое руководство по переходу к архитектуре с Firestore. Подробные инструкции см. в [docs/](docs/).

## Что было реализовано

✅ **SyncRunner** - сборщик данных всех групп и преподавателей
✅ **Firestore интеграция** - Google Cloud Firestore как БД
✅ **Два режима работы** - live (scraping) и cached (Firestore)
✅ **Cron скрипты** - автоматическая синхронизация 2 раза в день
✅ **Docker инфраструктура** - Dockerfile.sync, docker-compose.local.yml
✅ **Документация** - полные инструкции по настройке и деплою

## Следующие шаги для деплоя

### 1. Настройте Google Firestore (15 минут)

```bash
# Откройте инструкцию:
cat docs/FIRESTORE_SETUP.md
```

Кратко:
1. Создайте проект в Google Cloud Console
2. Включите Firestore (Native mode, Europe region)
3. Создайте сервисный аккаунт с ролью "Cloud Datastore User"
4. Скачайте JSON ключ

### 2. Скопируйте ключ на VPS

```bash
# На вашей машине:
scp firestore-key.json root@vps-ip:/srv/secrets/firestore-service-account.json

# На VPS:
ssh root@vps-ip
chmod 600 /srv/secrets/firestore-service-account.json
```

### 3. Обновите код на VPS

```bash
ssh root@vps-ip
cd /srv/app/vapor
git pull origin main

# Или переключитесь на вашу ветку:
git checkout claude/vapor-firestore-sync-architecture-011CUcKUrxXKNV6Wt4Syk2ez
```

### 4. Обновите docker-compose.yml

Добавьте в `/srv/app/docker-compose.yml`:

```yaml
services:
  vapor:
    environment:
      # Переключите на cached mode
      - DSW_BACKEND_MODE=cached  # было: live

      # Firestore config
      - FIRESTORE_PROJECT_ID=your-project-id-here
      - FIRESTORE_CREDENTIALS_PATH=/run/secrets/firestore-service-account.json

    volumes:
      # Монтируйте ключ
      - /srv/secrets/firestore-service-account.json:/run/secrets/firestore-service-account.json:ro
```

### 5. Создайте docker-compose.local.yml

Скопируйте на VPS:

```bash
scp docker-compose.local.yml root@vps-ip:/srv/app/
```

Или создайте вручную по примеру из репозитория.

### 6. Запустите первую синхронизацию

```bash
cd /srv/app

# Сборка sync контейнера
docker-compose -f docker-compose.yml -f docker-compose.local.yml build dsw-sync

# Первая синхронизация (30-60 минут)
docker-compose -f docker-compose.yml -f docker-compose.local.yml run --rm dsw-sync

# Следите за прогрессом - вы увидите:
# [1/1400] [0.1%] Processing group 123: WSEI-INF-S1-1
# ...
```

### 7. Настройте cron

```bash
cd /srv/app/vapor

# Копируем скрипты
cp scripts/sync-runner.sh /srv/app/scripts/
cp scripts/setup-cron.sh /srv/app/scripts/
chmod +x /srv/app/scripts/*.sh

# Устанавливаем cron (2 раза в день: 3:00 и 15:00)
sudo bash /srv/app/scripts/setup-cron.sh

# Проверка
sudo crontab -l
```

### 8. Перезапустите API

```bash
cd /srv/app

# Пересобираем с новым кодом
docker-compose build vapor

# Перезапускаем
docker-compose restart vapor

# Проверяем логи
docker-compose logs -f vapor
```

### 9. Проверьте работу

```bash
# Поиск групп (должен быть быстрым ~100ms)
curl https://api.dsw.wtf/groups/search?q=INF

# Aggregate (должен вернуть ВСЕХ преподавателей)
curl https://api.dsw.wtf/api/groups/123/aggregate | jq '.teachers | length'

# Schedule (по-прежнему live)
curl https://api.dsw.wtf/api/groups/123/schedule?date=2025-11-01
```

## Проверка работы Firestore

1. **Firestore Console**: https://console.cloud.google.com/firestore
   - Должны быть коллекции: `groups`, `teachers`, `metadata`

2. **Логи синхронизации**:
   ```bash
   tail -f /var/log/dsw-sync.log
   ```

3. **Статус последнего синка**:
   - В Firestore: `metadata/lastSync`
   - Должен быть status: "ok"

## Откат на live mode

Если что-то пошло не так:

```bash
# В docker-compose.yml:
- DSW_BACKEND_MODE=live

# Перезапустите
docker-compose restart vapor
```

API будет работать в старом режиме (scraping на лету).

## Мониторинг

### Ручной запуск синка
```bash
sudo /srv/app/scripts/sync-runner.sh
```

### Просмотр логов
```bash
# API
docker-compose logs -f vapor

# Sync
tail -f /var/log/dsw-sync.log
```

### Проверка cron
```bash
sudo crontab -l
grep dsw /var/log/syslog
```

## Важные замечания

### Формат API НЕ изменился
Мобильное приложение продолжит работать без изменений.

### Преподаватели в aggregate
Теперь `/api/groups/:id/aggregate` возвращает **всех** преподавателей университета, а не только преподавателей конкретной группы. Это необходимо для предзагрузки данных в приложение.

### Schedule остается live
`/api/groups/:id/schedule` всегда работает в live режиме (scraping) для актуальности.

### Безопасность
- JSON ключ **никогда** не коммитится в git
- Хранится только на VPS в `/srv/secrets/`
- Права доступа: `chmod 600`

## Стоимость

Firestore free tier покрывает ваш use case:
- 1 GB хранилища (вы используете ~100-200 MB)
- 50,000 reads/day (вы используете ~5,000-10,000)
- 20,000 writes/day (вы используете ~3,000)

Установите бюджетные алерты на $5-10/месяц для контроля.

## Поддержка

- **Подробная документация**: [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md)
- **Архитектура системы**: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- **Настройка Firestore**: [docs/FIRESTORE_SETUP.md](docs/FIRESTORE_SETUP.md)

## Что дальше?

После успешного деплоя:
1. Мониторьте логи первые несколько дней
2. Проверьте что cron работает (смотрите `/var/log/dsw-sync.log`)
3. Следите за usage в Firestore Console
4. Наслаждайтесь быстрыми ответами API (100-300ms) 🚀
