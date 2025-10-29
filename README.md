# DSW Timetable API

REST API для мобильного приложения расписания DSW University (Польша). Построено на Vapor (Swift 6).

## Архитектура

Проект состоит из двух компонентов:

1. **Vapor API Server** (`DswAggregator`) - HTTP API для мобильного приложения
2. **Sync Runner** (`SyncRunner`) - Периодическая синхронизация данных в Firestore

### Режимы работы

#### Live Mode (DSW_BACKEND_MODE=live)
- API скрапит сайт университета при каждом запросе
- Данные всегда актуальные, но медленнее
- Использует in-memory кэш для оптимизации

#### Cached Mode (DSW_BACKEND_MODE=cached)
- API читает предзагруженные данные из Firestore
- Быстрый ответ, но данные обновляются по расписанию (2 раза в день)
- Sync Runner собирает данные с сайта университета и сохраняет в Firestore

## API Endpoints

### `GET /api/groups/:groupId/aggregate`
Полная информация о группе:
- Расписание группы на семестр
- Список преподавателей с их расписаниями
- Метаданные группы

**Query parameters:**
- `from` - начало периода (YYYY-MM-DD), default: из env
- `to` - конец периода (YYYY-MM-DD), default: из env
- `type` - тип интервала (0=week, 1=month, 2=semester), default: 2

### `GET /groups/search?q=query`
Поиск групп по названию, коду, программе или факультету.

### `GET /api/groups/:groupId/schedule`
Расписание группы (всегда актуальное, читается с сайта университета).
Использует кэш 60 секунд.

## Quick Start

### Локальная разработка

```bash
# Установка зависимостей
swift package resolve

# Запуск в live mode
export DSW_BACKEND_MODE=live
swift run DswAggregator serve

# API доступен на http://localhost:8080
```

### Docker

```bash
# Сборка
docker build -t dsw-aggregator .

# Запуск
docker run -p 8080:8080 \
  -e DSW_BACKEND_MODE=live \
  dsw-aggregator
```

## Production Deployment

См. [DEPLOYMENT.md](DEPLOYMENT.md) для детальной инструкции по развертыванию с Firestore.

### Краткая инструкция:

1. Создать проект в Google Cloud с Firestore
2. Скачать service account JSON ключ
3. Загрузить на VPS в `/srv/secrets/firestore-service-account.json`
4. Настроить environment variables
5. Собрать sync-runner: `./scripts/build-sync.sh`
6. Запустить первичную синхронизацию: `./scripts/run-sync.sh`
7. Настроить cron: `./scripts/setup-cron.sh`
8. Переключить API в cached mode

## Environment Variables

### Common
```bash
DSW_DEFAULT_FROM=2025-09-06           # Начало семестра
DSW_DEFAULT_TO=2026-02-08             # Конец семестра
DSW_DEFAULT_INTERVAL=semester         # week | month | semester
```

### API Server
```bash
ENV=production
DSW_BACKEND_MODE=live                 # live | cached
DSW_ENABLE_MOCK=0                     # 1 для mock данных

# Cache TTLs (seconds)
DSW_TTL_SCHEDULE_SECS=60
DSW_TTL_SEARCH_SECS=259200
DSW_TTL_AGGREGATE_SECS=18000
DSW_TTL_TEACHER_SECS=18000

# Firestore (только для cached mode)
FIRESTORE_PROJECT_ID=your-project-id
FIRESTORE_CREDENTIALS_PATH=/run/secrets/firestore-service-account.json
```

### Sync Runner
```bash
FIRESTORE_PROJECT_ID=your-project-id
FIRESTORE_CREDENTIALS_PATH=/run/secrets/firestore-service-account.json
SYNC_DELAY_GROUPS_MS=150              # Задержка между группами (ms)
SYNC_DELAY_TEACHERS_MS=100            # Задержка между преподавателями (ms)
```

## Project Structure

```
Sources/
├── DswAggregator/                    # Main API server
│   ├── Config/                       # App configuration
│   ├── Domain/
│   │   ├── Models/                   # DTOs (AggregateResponse, etc.)
│   │   └── Utils/                    # Utilities
│   ├── Infrastructure/
│   │   ├── Clients/                  # HTTP clients for university site
│   │   ├── Firebase/                 # Firestore integration
│   │   │   ├── Models/               # Firestore document models
│   │   │   ├── FirestoreClient.swift # Low-level Firestore REST API
│   │   │   ├── FirestoreReader.swift # High-level read operations
│   │   │   └── FirestoreWriter.swift # High-level write operations
│   │   ├── Parsing/                  # HTML parsers (SwiftSoup)
│   │   └── Support/                  # Helpers
│   ├── Services/                     # Business logic
│   │   ├── AggregationService.swift
│   │   ├── GroupScheduleService.swift
│   │   ├── GroupSearchService.swift
│   │   ├── TeacherDetailsService.swift
│   │   └── Caching/                  # In-memory cache
│   ├── Presentation/
│   │   └── Routes/                   # HTTP endpoints
│   └── Sync Runner/
│       └── SyncAllGroupsRunner.swift # Sync logic
│
└── SyncRunner/                       # Sync executable
    └── main.swift

scripts/
├── build-sync.sh                     # Build sync-runner Docker image
├── run-sync.sh                       # Run sync manually
└── setup-cron.sh                     # Configure cron job
```

## Firestore Schema

```
/groups/{groupId}
  - groupId, from, to, intervalType
  - groupSchedule: [ScheduleEvent]
  - teacherIds: [Int]
  - groupInfo: { code, name, tracks, program, faculty }
  - fetchedAt: timestamp

/teachers/{teacherId}
  - id, name, title, department, email, phone
  - aboutHTML: String
  - schedule: [ScheduleEvent]
  - fetchedAt: timestamp

/metadata/groupsList
  - groups: [GroupInfo]
  - updatedAt: timestamp

/metadata/lastSync
  - timestamp, status, totalGroups, processedGroups, failedGroups
  - errorMessage, duration, startedAt
```

## Development

### Build
```bash
swift build
```

### Run API Server
```bash
swift run DswAggregator serve
```

### Run Sync Runner
```bash
export FIRESTORE_PROJECT_ID=your-project-id
export FIRESTORE_CREDENTIALS_PATH=/path/to/service-account.json
swift run SyncRunner
```

### Tests
```bash
swift test
```

## Tech Stack

- **Swift 6.0** - Language
- **Vapor 4.115+** - Web framework
- **SwiftSoup** - HTML parsing
- **JWTKit** - Service account authentication
- **Firestore** - Database (via REST API)
- **Docker** - Containerization

## License

MIT

## Links

- API: https://api.dsw.wtf
- University: https://harmonogramy.dsw.edu.pl
- [Vapor Website](https://vapor.codes)
- [Vapor Documentation](https://docs.vapor.codes)
