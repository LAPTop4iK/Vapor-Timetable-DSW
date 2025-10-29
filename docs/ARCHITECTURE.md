# Архитектура DSW Timetable API

## Обзор

DSW Timetable API - это сервис для предоставления расписания занятий студентам Dolnośląskiej Szkoły Wyższej через мобильное приложение.

## Компоненты системы

### 1. **DswCore** (Общая библиотека)

Путь: `Sources/DswAggregator/`

Содержит весь общий код, используемый как API сервером, так и sync runner:

- **Domain/Models** - модели данных (DTO)
  - `AggregateResponse` - расписание группы + все преподаватели
  - `GroupScheduleResponse` - только расписание группы
  - `TeacherCard` - карточка преподавателя с расписанием
  - `GroupInfo` - информация о группе
  - `ScheduleEvent` - событие расписания (пара)

- **Services** - бизнес-логика
  - `AggregationService` - сборка расписания группы + преподавателей
  - `GroupScheduleService` - получение расписания группы
  - `GroupSearchService` - поиск групп
  - `TeacherDetailsService` - получение информации о преподавателе
  - `FirestoreAggregationService` - чтение из Firestore
  - Caching services - кеширование с TTL

- **Infrastructure**
  - `Clients/VaporDSWClient` - HTTP клиент для сайта университета
  - `Parsing/` - парсеры HTML (SwiftSoup)
  - `Firestore/` - интеграция с Google Firestore
    - `FirestoreService` - CRUD операции
    - `GoogleAuthService` - OAuth2 аутентификация
    - `FirestoreModels` - модели документов

- **Presentation/Routes** - API endpoints
  - `GroupsRoutes` - маршруты для групп и расписаний
  - `FeatureFlagsRoutes` - feature flags и параметры

- **Config** - конфигурация приложения
  - `AppConfig` - чтение переменных окружения
  - `DIContainer` - dependency injection

### 2. **DswAggregator** (API Server)

Путь: `Sources/App/`

Основной веб-сервер на Vapor:
- Обрабатывает HTTP запросы от мобильного приложения
- Работает в двух режимах:
  - **live** - скрапинг с сайта университета в реальном времени
  - **cached** - чтение предзагруженных данных из Firestore
- Кеширование ответов в памяти (TTL configurable)
- Обработка timezone (Europe/Warsaw)

**API Endpoints:**

```
GET /groups/search?q=INF
  → Список групп, соответствующих запросу

GET /api/groups/:id/aggregate?from=...&to=...&type=...
  → Расписание группы + ВСЕ преподаватели университета

GET /api/groups/:id/schedule?date=YYYY-MM-DD
  → Расписание группы на конкретный день (всегда live)

GET /api/feature-flags
  → Feature flags для клиента
```

### 3. **SyncRunner** (Data Preloader)

Путь: `Sources/SyncRunner/`

Standalone приложение для предзагрузки данных в Firestore:

**Процесс синхронизации:**

1. Получает список всех групп (~1400)
2. Для каждой группы:
   - Скрапит расписание с сайта университета
   - Извлекает уникальных преподавателей
   - Для каждого нового преподавателя:
     - Получает карточку (имя, должность, email, etc.)
     - Получает расписание преподавателя
   - Сохраняет группу в Firestore
3. Сохраняет всех преподавателей в Firestore
4. Обновляет метаданные (список групп, статус синка)

**Особенности:**
- Кеширование преподавателей в пределах одного запуска
- Throttling между запросами (300-1000ms)
- Обработка ошибок (продолжает при частичных ошибках)
- Подробное логирование прогресса
- Статус синхронизации в Firestore

**Запуск:**
- Вручную: `docker-compose run --rm dsw-sync`
- Автоматически: через cron 2 раза в день

## Режимы работы

### Live Mode (DSW_BACKEND_MODE=live)

```
┌─────────────┐
│   Client    │
└──────┬──────┘
       │ HTTP
       ↓
┌─────────────┐
│   Vapor     │
│   Server    │
└──────┬──────┘
       │ HTTP
       ↓
┌─────────────┐
│ University  │
│   Website   │
└─────────────┘
```

- Каждый запрос идет на сайт университета
- Кеширование в памяти (TTL configurable)
- Медленнее, но всегда актуальные данные
- Риск блокировки при большом количестве запросов

### Cached Mode (DSW_BACKEND_MODE=cached)

```
┌─────────────┐              ┌─────────────┐
│   Client    │              │ SyncRunner  │
└──────┬──────┘              └──────┬──────┘
       │ HTTP                       │ Periodic
       ↓                            ↓
┌─────────────┐              ┌─────────────┐
│   Vapor     │←────────────→│  Firestore  │
│   Server    │    Read       │   (Google)  │
└─────────────┘              └──────┬──────┘
                                    ↑ Write
                                    │
                             ┌──────┴──────┐
                             │ University  │
                             │   Website   │
                             └─────────────┘
```

- Запросы читают из Firestore (быстро)
- Данные обновляются периодически (cron)
- Скрапинг только для `/schedule` endpoint (один день)
- Устойчивость к проблемам с сайтом университета

## Структура данных Firestore

```
firestore/
├── groups/
│   ├── 123                        # Document: группа
│   │   ├── groupId: 123
│   │   ├── groupCode: "WSEI-INF-S1-1"
│   │   ├── groupName: "Informatyka S1 gr.1"
│   │   ├── program: "Informatyka"
│   │   ├── faculty: "Wydział Informatyki"
│   │   ├── from: "2025-09-06"
│   │   ├── to: "2026-02-08"
│   │   ├── intervalType: 3
│   │   ├── schedule: [ScheduleEvent]
│   │   ├── teacherIds: [456, 789]
│   │   ├── lastUpdated: "2025-10-29T12:00:00Z"
│   │   └── syncStatus: "ok"
│   └── ...
│
├── teachers/
│   ├── 456                        # Document: преподаватель
│   │   ├── id: 456
│   │   ├── name: "Dr Jan Kowalski"
│   │   ├── title: "Adiunkt"
│   │   ├── department: "Katedra Informatyki"
│   │   ├── email: "j.kowalski@dsw.edu.pl"
│   │   ├── phone: "+48 71 123 4567"
│   │   ├── aboutHTML: "<p>...</p>"
│   │   ├── schedule: [ScheduleEvent]
│   │   ├── lastUpdated: "2025-10-29T12:00:00Z"
│   │   └── syncStatus: "ok"
│   └── ...
│
└── metadata/
    ├── groupsList                 # Document: список всех групп
    │   ├── groups: [GroupInfo]
    │   ├── totalCount: 1400
    │   └── lastUpdated: "2025-10-29T12:00:00Z"
    │
    ├── allTeachers                # Document: список всех преподавателей
    │   ├── teacherIds: [456, 789, ...]
    │   ├── totalCount: 500
    │   └── lastUpdated: "2025-10-29T12:00:00Z"
    │
    └── lastSync                   # Document: статус синхронизации
        ├── startedAt: "2025-10-29T12:00:00Z"
        ├── completedAt: "2025-10-29T13:30:00Z"
        ├── status: "ok"
        ├── totalGroups: 1400
        ├── processedGroups: 1398
        ├── failedGroups: 2
        ├── totalTeachers: 500
        ├── processedTeachers: 498
        ├── failedTeachers: 2
        ├── errorLog: ["Error 1", "Error 2"]
        └── durationSeconds: 5400
```

## Кеширование

### In-Memory Cache (Vapor)

```swift
actor InMemoryCacheStore {
    // Группа расписания (для aggregate)
    groupSchedule: TTL = DSW_TTL_AGGREGATE_SECS (5 hours)

    // Поиск групп
    groupSearch: TTL = DSW_TTL_SEARCH_SECS (3 days)

    // Агрегированные данные
    aggregate: TTL = DSW_TTL_AGGREGATE_SECS (5 hours)

    // Карточки преподавателей
    teacher: TTL = DSW_TTL_TEACHER_SECS (5 hours)

    // Расписание на день
    dailySchedule: TTL = 60 seconds
}
```

### Firestore Cache

- Данные обновляются 2 раза в день
- Эффективный TTL: ~12 часов
- Не expires автоматически

## Timezone Handling

Все времена пар в расписании используют Europe/Warsaw timezone:

```swift
let warsawTZ = TimeZone(identifier: "Europe/Warsaw")!
var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = warsawTZ
```

Это гарантирует, что:
- Время пар совпадает с сайтом университета
- Endpoint `/schedule` без параметра `date` возвращает "сегодня" по польскому времени
- Нет проблем с DST (daylight saving time)

## Безопасность

1. **Firestore Access**:
   - Сервисный аккаунт Google (OAuth2 JWT)
   - Приватный ключ хранится на VPS (не в git)
   - Admin SDK bypasses Firestore security rules

2. **Rate Limiting**:
   - Throttling между запросами к университету (300-1000ms)
   - In-memory cache для снижения нагрузки
   - Firestore для долгосрочного кеширования

3. **Error Handling**:
   - Graceful degradation (продолжение при ошибках)
   - Подробное логирование
   - Fallback к live mode если Firestore недоступен

## Performance

### Live Mode
- Aggregate endpoint: ~5-15 секунд (зависит от кол-ва преподавателей)
- Schedule endpoint: ~1-3 секунды
- Search endpoint: ~500-1000ms

### Cached Mode
- Aggregate endpoint: ~100-300ms (чтение из Firestore)
- Schedule endpoint: ~1-3 секунды (live + 60s cache)
- Search endpoint: ~50-100ms (чтение из Firestore)

### Sync Runner
- Полная синхронизация: ~30-60 минут
- ~1400 групп + ~500 преподавателей
- Throttled для избежания блокировки

## Мониторинг

1. **API Health**:
   - `GET /groups/search` - должен вернуть список групп
   - Response time < 500ms (cached mode)

2. **Sync Status**:
   - Проверить `/var/log/dsw-sync.log`
   - Firestore: `metadata/lastSync`
   - Должен быть status: "ok" или "partial_error"

3. **Firestore Usage**:
   - Google Cloud Console → Firestore
   - Проверить storage и операции
   - Установить budget alerts

4. **Errors**:
   - Docker logs: `docker-compose logs -f vapor`
   - Sync logs: `tail -f /var/log/dsw-sync.log`
   - Firestore errorLog в `metadata/lastSync`

## Масштабирование

Текущая архитектура поддерживает:
- До 10,000 req/day легко (в пределах Firestore free tier)
- Horizontal scaling: добавить больше Vapor instances за load balancer
- Vertical scaling: увеличить VPS ресурсы

Bottlenecks:
- Firestore read operations (50,000/day free)
- VPS network bandwidth
- `/schedule` endpoint (live) - может стать slow при большой нагрузке

Решения:
- Увеличить TTL для `/schedule` cache
- Добавить Redis для shared cache между instances
- Перейти на платный Firestore tier
