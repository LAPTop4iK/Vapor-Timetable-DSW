# Firestore Migration Guide

Краткое руководство по миграции DSW Timetable API на архитектуру с Firestore.

## Что изменилось?

### До миграции:
- Все данные скрейпятся с университетского сайта при каждом запросе
- `/api/groups/:id/aggregate` - скрейпит группу + всех преподавателей группы
- `/groups/search` - скрейпит список групп
- `/api/groups/:id/schedule` - скрейпит расписание за период

### После миграции:

**Live mode (DSW_BACKEND_MODE=live):**
- Поведение не изменилось, работает как раньше
- Рекомендуется для начального периода

**Cached mode (DSW_BACKEND_MODE=cached):**
- `/api/groups/:id/aggregate` - читает из Firestore, возвращает **ВСЕХ** преподавателей университета
- `/groups/search` - читает из Firestore
- `/api/groups/:id/schedule` - **всё ещё скрейпит** университетский сайт, но только за один день (today или ?date=YYYY-MM-DD) с кешем 60 секунд

**Новый компонент: SyncRunner**
- Запускается 2 раза в день через cron
- Обходит все ~1400 групп
- Собирает расписания и преподавателей
- Сохраняет в Firestore
- Длительность: ~15-30 минут

---

## Быстрый старт

### 1. Настройка Firestore

```bash
# 1. Создать проект в Google Cloud Console
# 2. Включить Firestore API (Native mode)
# 3. Создать Service Account с ролью "Cloud Datastore User"
# 4. Скачать JSON ключ
# 5. Загрузить на VPS:

scp firestore-service-account.json user@api.dsw.wtf:/tmp/
ssh user@api.dsw.wtf
sudo mkdir -p /srv/secrets
sudo mv /tmp/firestore-service-account.json /srv/secrets/
sudo chmod 600 /srv/secrets/firestore-service-account.json
```

### 2. Сборка и запуск

```bash
cd /srv/dsw-timetable

# Собрать образы
docker compose -f docker-compose.prod.yml build

# Запустить в live режиме (без Firestore)
docker compose -f docker-compose.prod.yml up -d vapor nginx

# Проверить что работает
curl http://localhost:8080/groups/search?q=inf
```

### 3. Первый sync

```bash
# Установить cron скрипт
sudo cp scripts/dsw-sync.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/dsw-sync.sh

# Запустить первый sync вручную (займёт 15-30 минут!)
sudo /usr/local/bin/dsw-sync.sh

# Мониторить прогресс
tail -f logs/*.log
```

### 4. Настройка cron

```bash
# Установить cron job
sudo cp scripts/dsw-sync.cron /etc/cron.d/dsw-sync
sudo chmod 644 /etc/cron.d/dsw-sync
sudo systemctl restart cron
```

### 5. Переключение на Firestore режим

```bash
# Остановить Vapor
docker compose -f docker-compose.prod.yml stop vapor

# Изменить режим
nano docker-compose.prod.yml
# Найти: DSW_BACKEND_MODE=live
# Изменить на: DSW_BACKEND_MODE=cached

# Перезапустить
docker compose -f docker-compose.prod.yml up -d vapor

# Проверить
docker logs vapor -f
# Должно быть: "Firestore service initialized in cached mode"
```

### 6. Тестирование

```bash
# Проверить aggregate (должен вернуть ВСЕХ преподавателей)
curl http://localhost:8080/api/groups/12345/aggregate | jq '.teachers | length'

# Проверить search
curl http://localhost:8080/groups/search?q=inf | jq '. | length'

# Проверить schedule (должен работать для одного дня)
curl http://localhost:8080/api/groups/12345/schedule | jq
curl "http://localhost:8080/api/groups/12345/schedule?date=2025-11-15" | jq
```

---

## Структура файлов

```
.
├── FIRESTORE_ARCHITECTURE.md     # Полная архитектурная документация
├── DEPLOYMENT.md                 # Детальное руководство по деплою
├── FIRESTORE_MIGRATION.md        # Это файл (краткая инструкция)
│
├── Sources/
│   ├── DswAggregator/            # DswCore library (общий код)
│   │   ├── Config/
│   │   │   ├── AppConfig.swift              # BackendMode configuration
│   │   │   └── DIContainer.swift            # FirestoreService initialization
│   │   ├── Domain/Models/
│   │   ├── Infrastructure/
│   │   │   ├── Firestore/
│   │   │   │   ├── FirestoreModels.swift    # Firestore document models
│   │   │   │   ├── GoogleAuthService.swift  # Google OAuth2 authentication
│   │   │   │   └── FirestoreService.swift   # Firestore REST API client
│   │   │   └── ...
│   │   ├── Services/
│   │   │   ├── FirestoreAggregationService.swift  # Read aggregate from Firestore
│   │   │   ├── Caching/
│   │   │   │   ├── InMemoryCacheStore.swift       # Added dailyScheduleCache
│   │   │   │   ├── CacheKey.swift                 # Added DailyScheduleCacheKey
│   │   │   │   └── CacheStats.swift               # Added dailyScheduleCount
│   │   │   └── ...
│   │   └── Presentation/Routes/
│   │       └── GroupsRoutes.swift           # Updated endpoints
│   │
│   ├── App/                      # Main API executable
│   │   └── main.swift
│   │
│   └── SyncRunner/               # Sync executable
│       └── main.swift
│
├── Dockerfile                    # Vapor API Dockerfile
├── Dockerfile.sync              # SyncRunner Dockerfile
├── docker-compose.yml           # Development compose
├── docker-compose.prod.yml      # Production compose (with sync-runner)
│
└── scripts/
    ├── dsw-sync.sh              # Sync script
    └── dsw-sync.cron            # Cron configuration
```

---

## Ключевые изменения в коде

### 1. AppConfig (`Sources/DswAggregator/Config/AppConfig.swift`)

Добавлен `BackendMode`:
- `live` - скрейпинг (по умолчанию)
- `cached` - Firestore

### 2. DIContainer (`Sources/DswAggregator/Config/DIContainer.swift`)

Инициализирует `FirestoreService` если mode=cached.

### 3. GroupsRoutes (`Sources/DswAggregator/Presentation/Routes/GroupsRoutes.swift`)

- `/api/groups/:id/aggregate` - проверяет BackendMode, читает из Firestore если cached
- `/groups/search` - проверяет BackendMode, читает из Firestore если cached
- `/api/groups/:id/schedule` - **ИЗМЕНЕНО**: теперь только один день (today или ?date=YYYY-MM-DD), с кешем 60 сек

### 4. InMemoryCacheStore (`Sources/DswAggregator/Services/Caching/InMemoryCacheStore.swift`)

Добавлен `dailyScheduleCache` для кеширования /schedule (60 секунд).

### 5. FirestoreService (`Sources/DswAggregator/Infrastructure/Firestore/FirestoreService.swift`)

Actor для работы с Firestore REST API:
- Аутентификация через GoogleAuthService (JWT + OAuth2)
- CRUD операции для groups, teachers, metadata
- Батчевое чтение преподавателей

### 6. SyncRunner (`Sources/SyncRunner/main.swift`)

Отдельный исполняемый файл для синхронизации:
- Получает список всех групп
- Обходит каждую группу (с throttling)
- Собирает уникальных преподавателей
- Записывает в Firestore
- Логирует статистику

---

## Environment Variables

### Vapor API

```bash
# Backend mode
DSW_BACKEND_MODE=live              # или "cached"

# Firestore (только для cached mode)
FIRESTORE_PROJECT_ID=dsw-timetable-prod
FIRESTORE_CREDENTIALS_PATH=/run/secrets/firestore-service-account.json

# Default ranges
DSW_DEFAULT_FROM=2025-09-06
DSW_DEFAULT_TO=2026-02-08
DSW_DEFAULT_INTERVAL=semester
```

### SyncRunner

```bash
FIRESTORE_PROJECT_ID=dsw-timetable-prod
FIRESTORE_CREDENTIALS_PATH=/run/secrets/firestore-service-account.json
DSW_DEFAULT_FROM=2025-09-06
DSW_DEFAULT_TO=2026-02-08
DSW_DEFAULT_INTERVAL=semester
```

---

## API Changes (Breaking Changes)

### `/api/groups/:id/schedule`

**До:**
```bash
GET /api/groups/12345/schedule?from=2025-09-06&to=2026-02-08&type=3
# Возвращает весь семестр
```

**После:**
```bash
GET /api/groups/12345/schedule
# Возвращает только сегодняшний день (Warsaw timezone)

GET /api/groups/12345/schedule?date=2025-11-15
# Возвращает конкретный день
```

**⚠️ ВАЖНО:** Если мобильное приложение использует `/schedule` для получения всего семестра, его нужно обновить и использовать `/aggregate` вместо этого.

### `/api/groups/:id/aggregate`

**Изменение:** В cached mode теперь возвращает **ВСЕХ** преподавателей университета, а не только тех, кто ведёт пары в данной группе.

Причина: Пользователь хочет, чтобы фронтенд показывал полный список преподавателей.

---

## Откат (Rollback)

Если что-то пошло не так:

```bash
# 1. Остановить Vapor
docker compose -f docker-compose.prod.yml stop vapor

# 2. Изменить режим обратно на live
nano docker-compose.prod.yml
# DSW_BACKEND_MODE=live

# 3. Перезапустить
docker compose -f docker-compose.prod.yml up -d vapor

# Приложение вернётся к старому поведению (без Firestore)
```

---

## Мониторинг

```bash
# Vapor логи
docker logs vapor -f

# Sync логи
tail -f logs/*.log
tail -f /var/log/dsw-sync-cron.log

# Firestore Console
https://console.cloud.google.com/firestore/data

# Проверить статус последнего синка
# Документ: metadata/lastSync
```

---

## Troubleshooting

### Ошибка: "Firestore service not configured"

```bash
# Проверить credentials
ls -la /srv/secrets/firestore-service-account.json

# Проверить permissions
sudo chmod 600 /srv/secrets/firestore-service-account.json

# Проверить что путь правильный в docker-compose
cat docker-compose.prod.yml | grep FIRESTORE_CREDENTIALS_PATH
```

### Sync занимает слишком много времени

```bash
# Это нормально для первого запуска (~15-30 минут для 1400 групп)
# Последующие запуски будут быстрее благодаря кешированию

# Мониторить прогресс
tail -f logs/*.log
```

### /schedule возвращает пустой массив

```bash
# Проверить дату
curl "http://localhost:8080/api/groups/12345/schedule?date=2025-11-15"

# Проверить что группа существует
curl "http://localhost:8080/groups/search?q=12345"
```

---

## Полезные команды

```bash
# Пересобрать всё
docker compose -f docker-compose.prod.yml build --no-cache

# Запустить sync вручную
docker compose -f docker-compose.prod.yml run --rm sync-runner

# Проверить использование ресурсов
docker stats

# Очистить логи
truncate -s 0 /var/log/dsw-sync-cron.log
rm -f logs/*.log

# Перезапустить всё
docker compose -f docker-compose.prod.yml restart
```

---

## Следующие шаги

1. ✅ Развернуть в live режиме
2. ✅ Настроить Firestore
3. ✅ Запустить первый sync
4. ✅ Настроить cron
5. ✅ Переключиться на cached режим
6. 🔄 Мониторить несколько дней
7. 🔄 Обновить мобильное приложение (если нужно)
8. ✅ Документировать всё

---

Для подробной информации см. [FIRESTORE_ARCHITECTURE.md](FIRESTORE_ARCHITECTURE.md) и [DEPLOYMENT.md](DEPLOYMENT.md).
