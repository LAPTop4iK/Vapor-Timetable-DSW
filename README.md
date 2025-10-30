# DSW Timetable API

REST API для мобильного приложения расписания DSW University (Польша). Построено на Vapor (Swift 6).

## Архитектура

Проект состоит из двух компонентов:

1. **Vapor API Server** (`DswAggregator`) - HTTP API для мобильного приложения
2. **Sync Runner** (`SyncRunner`) - Периодическая синхронизация данных в PostgreSQL

### Режимы работы

#### Live Mode (DSW_BACKEND_MODE=live)
- API скрапит сайт университета при каждом запросе
- Данные всегда актуальные, но медленнее
- Использует in-memory кэш для оптимизации

#### Cached Mode (DSW_BACKEND_MODE=cached)
- API читает предзагруженные данные из PostgreSQL
- Быстрый ответ, но данные обновляются по расписанию (2 раза в день)
- Sync Runner собирает данные с сайта университета и сохраняет в PostgreSQL

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

См. [DEPLOYMENT.md](DEPLOYMENT.md) для детальной инструкции по развертыванию с PostgreSQL.

### Краткая инструкция:

1. Создать .env файл из .env.example
2. Запустить `docker-compose up -d`
3. Собрать sync-runner: `./scripts/build-sync.sh`
4. Запустить первичную синхронизацию: `./scripts/run-sync.sh`
5. Настроить cron: `./scripts/setup-cron.sh` (опционально)

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

# Database (только для cached mode)
DATABASE_URL=postgres://vapor:password@localhost:5432/dsw_timetable
```

### Sync Runner
```bash
DATABASE_URL=postgres://vapor:password@localhost:5432/dsw_timetable
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
│   │   ├── Database/                 # PostgreSQL integration
│   │   │   ├── Models/               # Fluent models
│   │   │   ├── Migrations/           # Database migrations
│   │   │   └── DatabaseService.swift # High-level database operations
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

## Database Schema

PostgreSQL tables:

**groups**
- group_id (PK), from_date, to_date, interval_type
- group_schedule (JSONB), teacher_ids (INT[])
- group_info (JSONB), fetched_at (TIMESTAMP)

**teachers**
- id (PK), name, title, department, email, phone
- about_html (TEXT), schedule (JSONB)
- fetched_at (TIMESTAMP)

**groups_list**
- id (PK), groups (JSONB), updated_at (TIMESTAMP)

**sync_status**
- id (PK), timestamp, status, total_groups, processed_groups
- failed_groups, error_message, duration, started_at

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
export DATABASE_URL=postgres://vapor:password@localhost:5432/dsw_timetable
swift run SyncRunner
```

### Tests
```bash
swift test
```

## Tech Stack

- **Swift 6.0** - Language
- **Vapor 4.115+** - Web framework
- **Fluent** - ORM
- **PostgreSQL 16** - Database
- **SwiftSoup** - HTML parsing
- **Docker** - Containerization

## License

MIT

## Links

- API: https://api.dsw.wtf
- University: https://harmonogramy.dsw.edu.pl
- [Vapor Website](https://vapor.codes)
- [Vapor Documentation](https://docs.vapor.codes)
