# Руководство по деплою DSW Timetable на VPS

## Предварительные требования

- VPS в Польше (OVH или аналог)
- Ubuntu 20.04+ или Debian 11+
- Docker и docker-compose установлены
- Домен настроен (api.dsw.wtf)
- SSL сертификат (Let's Encrypt)
- Google Firestore настроен (см. FIRESTORE_SETUP.md)

## Архитектура

```
┌─────────────────────────────────────────────────────┐
│                     VPS (Poland)                     │
│                                                       │
│  ┌────────────┐  ┌──────────────┐  ┌─────────────┐ │
│  │   nginx    │→│ DswAggregator│  │ SyncRunner  │ │
│  │   (SSL)    │  │   (Vapor)    │  │   (cron)    │ │
│  └────────────┘  └──────────────┘  └─────────────┘ │
│        ↓                ↓                   ↓         │
│   Port 443         Port 8080         Manual/Cron    │
│                         ↓                   ↓         │
│                    ┌────────────────────────┐        │
│                    │   Firestore (Google)   │        │
│                    └────────────────────────┘        │
└─────────────────────────────────────────────────────┘
```

## Структура на VPS

```
/srv/app/
├── docker-compose.yml          # Основная конфигурация
├── docker-compose.local.yml    # Локальные расширения (sync)
├── nginx/
│   ├── nginx.conf
│   └── certs/
│       ├── fullchain.pem
│       └── privkey.pem
├── scripts/
│   ├── sync-runner.sh          # Wrapper для cron
│   └── setup-cron.sh           # Установка cron job
└── vapor/                       # Git repository

/srv/secrets/
└── firestore-service-account.json  # Ключ Firestore (НЕ в git!)

/var/log/
└── dsw-sync.log                # Логи синхронизации
```

## Шаг 1: Подготовка VPS

```bash
# Подключитесь к VPS
ssh root@your-vps-ip

# Обновите систему
apt update && apt upgrade -y

# Установите Docker
curl -fsSL https://get.docker.com | sh

# Установите docker-compose
apt install docker-compose -y

# Создайте директории
mkdir -p /srv/app
mkdir -p /srv/secrets
chmod 700 /srv/secrets
```

## Шаг 2: Клонирование репозитория

```bash
cd /srv/app

# Клонируйте репозиторий
git clone https://github.com/yourusername/Vapor-Timetable-DSW.git vapor

# Или если уже есть, обновите
cd vapor
git pull origin main
```

## Шаг 3: Настройка Firestore

Следуйте инструкциям в [FIRESTORE_SETUP.md](./FIRESTORE_SETUP.md) для:
1. Создания Google Cloud проекта
2. Настройки Firestore
3. Создания сервисного аккаунта
4. Копирования ключа на VPS

## Шаг 4: Конфигурация docker-compose

Создайте `/srv/app/docker-compose.yml`:

```yaml
version: '3.8'

services:
  vapor:
    build:
      context: ./vapor
      dockerfile: Dockerfile
    container_name: vapor
    restart: unless-stopped
    expose:
      - "8080"
    environment:
      # Runtime mode
      - ENV=production

      # Default semester boundaries
      - DSW_DEFAULT_FROM=2025-09-06
      - DSW_DEFAULT_TO=2026-02-08
      - DSW_DEFAULT_INTERVAL=semester

      # Backend mode: 'live' or 'cached'
      # Use 'cached' to read from Firestore instead of scraping
      - DSW_BACKEND_MODE=cached

      # Mock mode (for testing)
      - DSW_ENABLE_MOCK=0

      # Firestore configuration
      - FIRESTORE_PROJECT_ID=your-project-id
      - FIRESTORE_CREDENTIALS_PATH=/run/secrets/firestore-service-account.json

      # Feature flags
      - DSW_FEATURE_FLAGS_JSON={"show_ads":true,"show_debug_menu":false}
      - DSW_FEATURE_FLAGS_VERSION=1.0.1

    volumes:
      - /srv/secrets/firestore-service-account.json:/run/secrets/firestore-service-account.json:ro

  nginx:
    image: nginx:stable
    container_name: nginx
    restart: unless-stopped
    depends_on:
      - vapor
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/certs:/etc/nginx/certs:ro
      - /var/www/html:/var/www/html:ro
```

Создайте `/srv/app/docker-compose.local.yml` для sync runner:

```yaml
version: '3.8'

services:
  dsw-sync:
    build:
      context: ./vapor
      dockerfile: Dockerfile.sync
    container_name: dsw-sync
    environment:
      - FIRESTORE_PROJECT_ID=your-project-id
      - FIRESTORE_CREDENTIALS_PATH=/run/secrets/firestore-service-account.json
      - DSW_DEFAULT_FROM=2025-09-06
      - DSW_DEFAULT_TO=2026-02-08
      - DSW_DEFAULT_INTERVAL=semester
    volumes:
      - /srv/secrets/firestore-service-account.json:/run/secrets/firestore-service-account.json:ro
    profiles:
      - manual
```

## Шаг 5: Настройка nginx

Nginx конфигурация уже должна быть на месте из вашего текущего деплоя. Никаких изменений не требуется.

## Шаг 6: Сборка и запуск

```bash
cd /srv/app

# Сборка образов
docker-compose build

# Запуск основного API сервера
docker-compose up -d

# Проверка логов
docker-compose logs -f vapor
```

## Шаг 7: Первая синхронизация

Запустите первую синхронизацию вручную:

```bash
cd /srv/app

# Сборка sync образа
docker-compose -f docker-compose.yml -f docker-compose.local.yml build dsw-sync

# Запуск синхронизации (займет ~30-60 минут)
docker-compose -f docker-compose.yml -f docker-compose.local.yml run --rm dsw-sync
```

Следите за логами. Вы должны увидеть:
```
═══════════════════════════════════════════════════════════════
  DSW Timetable Sync Runner
  Firestore Data Preloading Script
═══════════════════════════════════════════════════════════════
[INFO] Configuration loaded
[INFO] Firestore service initialized
[INFO] Fetching list of all groups...
[INFO] Found 1400 groups
[INFO] Processing groups...
[1/1400] [0.1%] Processing group 123: WSEI-INF-S1-1
...
```

## Шаг 8: Настройка cron

После успешной первой синхронизации настройте автоматический запуск:

```bash
cd /srv/app/vapor

# Копируем скрипты на место
cp scripts/sync-runner.sh /srv/app/scripts/
cp scripts/setup-cron.sh /srv/app/scripts/

# Делаем исполняемыми
chmod +x /srv/app/scripts/*.sh

# Устанавливаем cron job (2 раза в день: 3:00 и 15:00)
sudo bash /srv/app/scripts/setup-cron.sh
```

Проверка:
```bash
# Посмотреть установленные cron jobs
sudo crontab -l

# Запустить синхронизацию вручную
sudo /srv/app/scripts/sync-runner.sh

# Посмотреть логи
tail -f /var/log/dsw-sync.log
```

## Шаг 9: Переключение на режим Firestore

После успешной синхронизации переключите API на чтение из Firestore:

1. Отредактируйте `/srv/app/docker-compose.yml`:
```yaml
- DSW_BACKEND_MODE=cached  # было: live
```

2. Перезапустите API:
```bash
cd /srv/app
docker-compose restart vapor
```

3. Проверьте API:
```bash
# Поиск групп
curl https://api.dsw.wtf/groups/search?q=INF

# Агрегированные данные группы
curl https://api.dsw.wtf/api/groups/123/aggregate

# Расписание на день (по-прежнему live)
curl https://api.dsw.wtf/api/groups/123/schedule?date=2025-11-01
```

## Обслуживание

### Просмотр логов

```bash
# API логи
docker-compose logs -f vapor

# Sync логи
tail -f /var/log/dsw-sync.log

# nginx логи
docker-compose logs -f nginx
```

### Ручной запуск синхронизации

```bash
sudo /srv/app/scripts/sync-runner.sh
```

### Обновление кода

```bash
cd /srv/app/vapor
git pull origin main

cd /srv/app
docker-compose build
docker-compose restart vapor

# Пересобрать sync runner (если изменился)
docker-compose -f docker-compose.yml -f docker-compose.local.yml build dsw-sync
```

### Мониторинг

1. **Логи синхронизации**: `/var/log/dsw-sync.log`
2. **Firestore Console**: https://console.cloud.google.com/firestore
3. **API health check**: `curl https://api.dsw.wtf/groups/search`

### Rollback на live mode

Если что-то пошло не так, можно вернуться к live scraping:

```bash
# Отредактируйте docker-compose.yml
- DSW_BACKEND_MODE=live

# Перезапустите
docker-compose restart vapor
```

## Диагностика проблем

### Firestore authentication failed

```
[ERROR] Failed to initialize Firestore service: ...
```

Проверьте:
- Файл `/srv/secrets/firestore-service-account.json` существует
- Права доступа: `chmod 600 /srv/secrets/firestore-service-account.json`
- JSON валидный
- Project ID правильный

### Sync занимает слишком много времени

Нормальное время синхронизации: 30-60 минут для ~1400 групп.

Если дольше:
- Проверьте сетевое соединение с университетским сайтом
- Проверьте логи на ошибки
- Возможно университетский сайт блокирует запросы (слишком быстрые)

### API возвращает 404 для группы

Возможные причины:
- Группа еще не синхронизирована
- Синхронизация провалилась для этой группы
- Group ID неправильный

Проверьте:
- `/var/log/dsw-sync.log` - были ли ошибки?
- Firestore Console - есть ли документ `groups/{groupId}`?

## Безопасность

1. **Firestore ключ**:
   - Хранится только в `/srv/secrets/`
   - Никогда не коммитится в git
   - Права доступа: `chmod 600`

2. **Docker volumes**:
   - Монтируется read-only (`:ro`)
   - Не логируется в docker logs

3. **Cron**:
   - Логи пишутся с временными метками
   - Блокировка повторного запуска (lock file)

## Резервное копирование

Firestore автоматически реплицируется Google. Дополнительные бэкапы не требуются для данных, которые можно пересобрать через sync.

Но можно настроить экспорт:
```bash
# Установить gcloud CLI на VPS
# Настроить автоматический экспорт в Cloud Storage
```

См. [Firestore Export](https://cloud.google.com/firestore/docs/manage-data/export-import)
