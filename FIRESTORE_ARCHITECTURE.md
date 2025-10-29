# Firestore Architecture для DSW Timetable

## Обзор архитектуры

Переход от модели "запрос на лету" к модели с предзагрузкой данных в Firestore.

```
┌─────────────────────────────────────────────────────────────┐
│                         VPS (Poland)                        │
│                                                             │
│  ┌──────────────┐        ┌─────────────────┐               │
│  │              │        │                 │               │
│  │  Cron Job    │───────▶│  SyncRunner     │               │
│  │  (2x daily)  │        │  (Swift)        │               │
│  │              │        │                 │               │
│  └──────────────┘        └────────┬────────┘               │
│                                   │                         │
│                                   │ Polish IP               │
│                                   ▼                         │
│                          ┌─────────────────┐                │
│                          │   University    │                │
│                          │   Website       │                │
│                          │  (scraping)     │                │
│                          └─────────────────┘                │
│                                   │                         │
│                                   │ Parse & Write           │
│                                   ▼                         │
│                          ┌─────────────────┐                │
│                          │   Firestore     │                │
│                          │   (Cloud)       │                │
│                          └────────┬────────┘                │
│                                   │                         │
│                                   │ Read                    │
│  ┌─────────────┐                  │                         │
│  │             │                  │                         │
│  │  Vapor API  │◀─────────────────┘                         │
│  │  (Docker)   │                                            │
│  │             │                                            │
│  └──────┬──────┘                                            │
│         │                                                   │
│         │ /api/groups/:id/aggregate (from Firestore)       │
│         │ /groups/search (from Firestore)                  │
│         │ /api/groups/:id/schedule (live scraping + cache) │
│         │                                                   │
└─────────┼───────────────────────────────────────────────────┘
          │
          ▼
    Mobile App
```

---

## Firestore Schema

### Коллекция: `groups`

Документ на каждую группу. ID документа = `groupId` (Int as String).

**Путь:** `groups/{groupId}`

**Структура:**
```json
{
  "groupId": 12345,
  "groupCode": "I-SEM5-INF",
  "groupName": "Informatyka sem. 5",
  "program": "Informatyka",
  "faculty": "Wydział Nauk Ścisłych",
  "from": "2025-09-06",
  "to": "2026-02-08",
  "intervalType": 3,
  "schedule": [
    {
      "title": "Programowanie obiektowe",
      "teacherName": "dr Jan Kowalski",
      "teacherId": 456,
      "teacherEmail": "j.kowalski@dsw.edu.pl",
      "room": "A-123",
      "type": "Wyk",
      "grading": "Egzamin",
      "studyTrack": "Stacjonarne",
      "groups": "I-SEM5-INF",
      "remarks": "Brak",
      "startISO": "2025-09-06T08:00:00+02:00",
      "endISO": "2025-09-06T09:30:00+02:00"
    }
  ],
  "teacherIds": [456, 789, 101],
  "lastUpdated": "2025-10-29T12:00:00Z",
  "syncStatus": "ok"
}
```

**Поля:**
- `groupId` (Int) - ID группы
- `groupCode` (String) - код группы
- `groupName` (String) - название группы
- `program` (String) - программа обучения
- `faculty` (String) - факультет
- `from` (String) - начало периода (YYYY-MM-DD)
- `to` (String) - конец периода (YYYY-MM-DD)
- `intervalType` (Int) - тип интервала (1=week, 2=month, 3=semester)
- `schedule` (Array) - массив ScheduleEvent
- `teacherIds` (Array<Int>) - список всех уникальных teacherId из этой группы
- `lastUpdated` (String ISO8601) - время последнего обновления
- `syncStatus` (String) - статус последнего синка ("ok", "error")

**Индексы:**
- Автоматический по document ID (groupId)
- Composite: `lastUpdated DESC` (для мониторинга)

---

### Коллекция: `teachers`

Документ на каждого преподавателя. ID документа = `teacherId` (Int as String).

**Путь:** `teachers/{teacherId}`

**Структура:**
```json
{
  "id": 456,
  "name": "dr Jan Kowalski",
  "title": "Doktor nauk technicznych",
  "department": "Katedra Informatyki",
  "email": "j.kowalski@dsw.edu.pl",
  "phone": "+48 123 456 789",
  "aboutHTML": "<p>Biografia...</p>",
  "schedule": [
    {
      "title": "Programowanie obiektowe",
      "teacherName": "dr Jan Kowalski",
      "teacherId": 456,
      "teacherEmail": "j.kowalski@dsw.edu.pl",
      "room": "A-123",
      "type": "Wyk",
      "grading": "Egzamin",
      "studyTrack": "Stacjonarne",
      "groups": "I-SEM5-INF",
      "remarks": "Brak",
      "startISO": "2025-09-06T08:00:00+02:00",
      "endISO": "2025-09-06T09:30:00+02:00"
    }
  ],
  "lastUpdated": "2025-10-29T12:00:00Z",
  "syncStatus": "ok"
}
```

**Поля:**
- `id` (Int) - ID преподавателя
- `name` (String?) - полное имя
- `title` (String?) - учёная степень
- `department` (String?) - кафедра/подразделение
- `email` (String?) - email
- `phone` (String?) - телефон
- `aboutHTML` (String?) - биография в HTML
- `schedule` (Array) - полное расписание преподавателя (ScheduleEvent[])
- `lastUpdated` (String ISO8601) - время последнего обновления
- `syncStatus` (String) - статус ("ok", "error")

**Индексы:**
- Автоматический по document ID (teacherId)
- `name` (для поиска, опционально)

---

### Коллекция: `metadata`

Служебные документы.

#### Документ: `metadata/groupsList`

Полный список всех групп (для эндпойнта `/groups/search`).

**Структура:**
```json
{
  "groups": [
    {
      "groupId": 12345,
      "code": "I-SEM5-INF",
      "name": "Informatyka sem. 5",
      "tracks": [
        {"trackId": 1, "title": "Stacjonarne"}
      ],
      "program": "Informatyka",
      "faculty": "Wydział Nauk Ścisłych"
    }
  ],
  "totalCount": 1400,
  "lastUpdated": "2025-10-29T12:00:00Z"
}
```

**Поля:**
- `groups` (Array<GroupInfo>) - полный список всех групп
- `totalCount` (Int) - количество групп
- `lastUpdated` (String ISO8601) - время последнего обновления

#### Документ: `metadata/lastSync`

Статус последнего синка.

**Структура:**
```json
{
  "startedAt": "2025-10-29T08:00:00Z",
  "completedAt": "2025-10-29T12:34:56Z",
  "status": "ok",
  "totalGroups": 1400,
  "processedGroups": 1400,
  "failedGroups": 0,
  "totalTeachers": 350,
  "processedTeachers": 350,
  "failedTeachers": 0,
  "errorLog": [],
  "durationSeconds": 16496
}
```

**Поля:**
- `startedAt` (String ISO8601) - начало синка
- `completedAt` (String ISO8601?) - конец синка (null если ещё идёт)
- `status` (String) - "running", "ok", "partial_error", "failed"
- `totalGroups` (Int) - всего групп для обработки
- `processedGroups` (Int) - обработано групп
- `failedGroups` (Int) - групп с ошибками
- `totalTeachers` (Int) - всего уникальных преподавателей
- `processedTeachers` (Int) - обработано преподавателей
- `failedTeachers` (Int) - преподавателей с ошибками
- `errorLog` (Array<String>) - лог ошибок (первые 100)
- `durationSeconds` (Int?) - длительность в секундах

#### Документ: `metadata/allTeachers`

**НОВОЕ**: Полный список всех преподавателей университета (собирается из всех групп).

**Структура:**
```json
{
  "teacherIds": [123, 456, 789, ...],
  "totalCount": 350,
  "lastUpdated": "2025-10-29T12:00:00Z"
}
```

**Назначение:**
- Используется в `/api/groups/:id/aggregate` для получения ВСЕХ преподавателей университета
- Позволяет фронтенду показывать полный список преподавателей, а не только тех, кто ведёт пары в конкретной группе

---

## API Endpoints Changes

### GET `/api/groups/:groupId/aggregate`

**До миграции:**
- Скрейпит расписание группы с сайта университета
- Собирает уникальных преподавателей из расписания группы
- Для каждого преподавателя скрейпит карточку + расписание
- Возвращает AggregateResponse

**После миграции:**
- Читает `groups/{groupId}` из Firestore
- Читает `metadata/allTeachers` чтобы получить список всех teacherId
- Читает все документы `teachers/{teacherId}` батчами
- Формирует AggregateResponse со ВСЕМИ преподавателями университета
- Возвращает тот же JSON формат

**Примечание:** Теперь в `teachers` будет список ВСЕХ преподавателей университета, а не только тех, кто ведёт пары в текущей группе.

---

### GET `/groups/search`

**До миграции:**
- POST запрос на harmonogramy.dsw.edu.pl/Plany/ZnajdzGrupe
- Парсит HTML
- Возвращает список групп

**После миграции:**
- Читает `metadata/groupsList` из Firestore
- Фильтрует по query параметру `q` локально (case-insensitive)
- Возвращает тот же JSON формат

---

### GET `/api/groups/:groupId/schedule`

**До и после миграции:**
- Остаётся LIVE эндпойнтом (скрейпит сайт университета)
- НО: теперь только за ONE DAY (сегодня или ?date=YYYY-MM-DD)
- НЕ за весь семестр
- Добавляется in-memory кеш (TTL 60 секунд) на ключ (groupId, date)
- Учитывает Europe/Warsaw timezone

**Cache Key:**
```swift
struct DailyScheduleCacheKey: Hashable {
    let groupId: Int
    let date: String // YYYY-MM-DD
}
```

**Логика:**
1. Парсим query параметры: `date` (optional, default = сегодня в Warsaw)
2. Проверяем кеш для (groupId, date)
3. Если кеш hit → возвращаем
4. Если кеш miss → скрейпим университетский сайт для ONE DAY
5. Кешируем на 60 секунд
6. Возвращаем

---

## SyncRunner Implementation

### Исполняемый файл: `SyncRunner`

**Расположение:** `Sources/SyncRunner/main.swift`

**Архитектура:**
```swift
// Package.swift
targets: [
    .executableTarget(
        name: "SyncRunner",
        dependencies: [
            .product(name: "Vapor", package: "vapor"),
            .product(name: "SwiftSoup", package: "SwiftSoup"),
            // Firebase Admin SDK
        ],
        path: "Sources/SyncRunner"
    )
]
```

**Логика SyncRunner:**

1. **Инициализация**
   - Загружает сервисный аккаунт из `/run/secrets/firestore-service-account.json`
   - Инициализирует Firestore клиент
   - Настраивает логирование в `/var/log/dsw-sync.log`

2. **Получение списка всех групп**
   - Использует `GroupSearchService` с query = ""
   - Получает полный список всех ~1400 групп
   - Сохраняет в `metadata/groupsList`

3. **Обработка каждой группы** (с throttling и retry)
   - Для каждой группы:
     - Вызывает `AggregationService.aggregate()` с параметрами по умолчанию
     - Получает расписание группы + список преподавателей
     - Извлекает уникальные `teacherId` из расписания
     - Для каждого НОВОГО преподавателя (не в кеше текущего прогона):
       - Вызывает `TeacherDetailsService.fetchTeacherCard()`
       - Добавляет в локальный кеш преподавателей (Map<teacherId, TeacherCard>)
     - Формирует документ для `groups/{groupId}`
     - Записывает в Firestore
   - **Throttling:**
     - Задержка 0.5-1 секунда между группами
     - Задержка 0.3-0.5 секунды между преподавателями
   - **Retry:**
     - До 3 попыток при сетевых ошибках
     - Exponential backoff (1s, 2s, 4s)

4. **Обработка всех преподавателей**
   - После обработки всех групп → имеем полный Set<teacherId>
   - Записываем каждого преподавателя из кеша в `teachers/{teacherId}`
   - Записываем список всех teacherId в `metadata/allTeachers`

5. **Финализация**
   - Обновляет `metadata/lastSync` со статистикой
   - Закрывает Firestore соединение
   - Возвращает exit code (0 = ok, 1 = errors)

**Псевдокод:**
```swift
@main
struct SyncRunner {
    static func main() async throws {
        let firestore = FirestoreService(credentialsPath: "...")
        let logger = Logger(label: "sync-runner")

        logger.info("Starting sync...")
        firestore.updateSyncStatus(status: "running", startedAt: Date())

        // 1. Получить все группы
        let allGroups = try await groupSearchService.search(query: "")
        await firestore.saveGroupsList(allGroups)

        // 2. Локальный кеш преподавателей
        var teacherCache: [Int: TeacherCard] = [:]
        var processedGroups = 0
        var failedGroups = 0

        // 3. Обработка групп
        for group in allGroups {
            do {
                // Получить расписание + преподавателей группы
                let aggregate = try await aggregationService.aggregate(
                    groupId: group.groupId,
                    from: defaultFrom,
                    to: defaultTo,
                    intervalType: .semester
                )

                // Извлечь уникальные teacherId
                let teacherIds = Set(aggregate.groupSchedule.compactMap(\.teacherId))

                // Получить карточки новых преподавателей
                for teacherId in teacherIds {
                    if teacherCache[teacherId] == nil {
                        let card = try await teacherDetailsService.fetchTeacherCard(...)
                        teacherCache[teacherId] = card
                        try await Task.sleep(for: .milliseconds(300))
                    }
                }

                // Сохранить группу в Firestore
                await firestore.saveGroup(
                    groupId: group.groupId,
                    groupInfo: group,
                    schedule: aggregate.groupSchedule,
                    teacherIds: Array(teacherIds)
                )

                processedGroups += 1
                try await Task.sleep(for: .milliseconds(500))

            } catch {
                logger.error("Failed to process group \(group.groupId): \(error)")
                failedGroups += 1
            }
        }

        // 4. Сохранить всех преподавателей
        for (teacherId, card) in teacherCache {
            await firestore.saveTeacher(card)
        }

        // 5. Сохранить список всех преподавателей
        await firestore.saveAllTeachers(Array(teacherCache.keys))

        // 6. Финализация
        await firestore.updateSyncStatus(
            status: failedGroups > 0 ? "partial_error" : "ok",
            processedGroups: processedGroups,
            failedGroups: failedGroups,
            totalTeachers: teacherCache.count
        )

        logger.info("Sync completed!")
    }
}
```

---

## FirestoreService

**Файл:** `Sources/DswAggregator/Infrastructure/Firestore/FirestoreService.swift`

**Зависимость:**
- Firebase Admin SDK для Swift (если доступен)
- Или Google Cloud Firestore REST API

**Методы:**

```swift
actor FirestoreService {
    private let projectId: String
    private let credentials: GoogleCredentials

    init(projectId: String, credentialsPath: String) async throws

    // Groups
    func saveGroup(
        groupId: Int,
        groupInfo: GroupInfo,
        schedule: [ScheduleEvent],
        teacherIds: [Int]
    ) async throws

    func getGroup(groupId: Int) async throws -> FirestoreGroupDocument?

    // Teachers
    func saveTeacher(_ card: TeacherCard) async throws
    func getTeacher(teacherId: Int) async throws -> TeacherCard?
    func getAllTeachers(teacherIds: [Int]) async throws -> [TeacherCard]

    // Metadata
    func saveGroupsList(_ groups: [GroupInfo]) async throws
    func getGroupsList() async throws -> [GroupInfo]

    func saveAllTeachers(_ teacherIds: [Int]) async throws
    func getAllTeacherIds() async throws -> [Int]

    func updateSyncStatus(
        status: String,
        startedAt: Date? = nil,
        processedGroups: Int? = nil,
        failedGroups: Int? = nil,
        totalTeachers: Int? = nil
    ) async throws

    func getSyncStatus() async throws -> SyncStatus
}
```

---

## Configuration Changes

### Environment Variables (docker-compose.yml)

```yaml
services:
  vapor:
    environment:
      # Backend mode
      - DSW_BACKEND_MODE=cached  # "live" или "cached"

      # Firestore
      - FIRESTORE_PROJECT_ID=dsw-timetable-prod
      - FIRESTORE_CREDENTIALS_PATH=/run/secrets/firestore-service-account.json

      # Cache TTLs
      - DSW_TTL_DAILY_SCHEDULE_SECS=60  # новый для /schedule

    secrets:
      - firestore-service-account

  sync-runner:
    build:
      context: ./vapor
      dockerfile: Dockerfile.sync
    container_name: dsw-sync-runner
    restart: "no"  # запускается только через cron
    environment:
      - FIRESTORE_PROJECT_ID=dsw-timetable-prod
      - FIRESTORE_CREDENTIALS_PATH=/run/secrets/firestore-service-account.json
      - DSW_DEFAULT_FROM=2025-09-06
      - DSW_DEFAULT_TO=2026-02-08
      - DSW_DEFAULT_INTERVAL=semester
    secrets:
      - firestore-service-account
    volumes:
      - ./logs:/var/log

secrets:
  firestore-service-account:
    file: /srv/secrets/firestore-service-account.json
```

---

## Cron Setup

### Файл: `/etc/cron.d/dsw-sync`

```cron
# Запуск синка 2 раза в день: в 3:00 и 15:00 Warsaw time
0 3,15 * * * root /usr/local/bin/dsw-sync.sh >> /var/log/dsw-sync-cron.log 2>&1
```

### Скрипт: `/usr/local/bin/dsw-sync.sh`

```bash
#!/bin/bash
set -e

COMPOSE_FILE="/srv/dsw-timetable/docker-compose.yml"
SYNC_CONTAINER="dsw-sync-runner"

echo "[$(date -Iseconds)] Starting DSW sync..."

cd /srv/dsw-timetable

# Запуск sync-runner контейнера
docker compose -f "$COMPOSE_FILE" run --rm "$SYNC_CONTAINER"

EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo "[$(date -Iseconds)] Sync completed successfully"
else
    echo "[$(date -Iseconds)] Sync failed with exit code $EXIT_CODE"
fi

exit $EXIT_CODE
```

**Права:**
```bash
chmod +x /usr/local/bin/dsw-sync.sh
chown root:root /usr/local/bin/dsw-sync.sh
```

---

## Deployment Plan

### Шаг 1: Создание Firestore проекта
1. Создать проект в Google Cloud Console
2. Включить Firestore Database (Native mode)
3. Создать сервисный аккаунт с ролью "Cloud Datastore User"
4. Скачать JSON ключ
5. Скопировать на VPS: `/srv/secrets/firestore-service-account.json`
6. `chmod 600 /srv/secrets/firestore-service-account.json`

### Шаг 2: Обновление кода
1. Добавить Firebase Admin SDK в Package.swift
2. Реализовать FirestoreService
3. Реализовать SyncRunner
4. Обновить API endpoints для чтения из Firestore (с feature flag)
5. Добавить in-memory кеш для /schedule

### Шаг 3: Тестирование SyncRunner локально
1. Экспортировать FIRESTORE_PROJECT_ID и FIRESTORE_CREDENTIALS_PATH
2. Запустить `swift run SyncRunner` локально на небольшой выборке групп
3. Проверить данные в Firestore Console

### Шаг 4: Docker setup
1. Создать Dockerfile.sync для SyncRunner
2. Обновить docker-compose.yml
3. Протестировать `docker compose run --rm dsw-sync-runner`

### Шаг 5: Cron setup
1. Создать `/usr/local/bin/dsw-sync.sh`
2. Добавить в `/etc/cron.d/dsw-sync`
3. Протестировать вручную

### Шаг 6: Первый полный синк
1. Запустить SyncRunner вручную для ВСЕХ групп
2. Мониторить логи
3. Проверить metadata/lastSync

### Шаг 7: Переключение API на Firestore
1. Установить `DSW_BACKEND_MODE=cached`
2. Рестарт Vapor контейнера
3. Тестирование API endpoints
4. Мониторинг ошибок

### Шаг 8: Мониторинг и оптимизация
1. Настроить alerting на статус синка
2. Оптимизировать batch размеры
3. Настроить Firestore индексы если нужно

---

## Migration Checklist

- [ ] Создать Firestore проект и сервисный аккаунт
- [ ] Реализовать FirestoreService
- [ ] Реализовать SyncRunner
- [ ] Добавить feature flag DSW_BACKEND_MODE
- [ ] Обновить /api/groups/:id/aggregate для чтения из Firestore
- [ ] Обновить /groups/search для чтения из Firestore
- [ ] Добавить in-memory кеш для /schedule (daily)
- [ ] Создать Dockerfile.sync
- [ ] Обновить docker-compose.yml
- [ ] Создать cron скрипт
- [ ] Протестировать полный цикл синка
- [ ] Переключить production на cached mode
- [ ] Настроить мониторинг и alerts

---

## Важные замечания

1. **Timezone:** Всегда использовать Europe/Warsaw для генерации ISO8601 дат
2. **Throttling:** Не более 2 запросов в секунду к университетскому сайту
3. **Retry logic:** Максимум 3 попытки с exponential backoff
4. **Caching:** Кешировать преподавателей ТОЛЬКО в рамках одного прогона синка
5. **Logging:** Все ошибки логировать в файл + в metadata/lastSync.errorLog
6. **Graceful degradation:** Если Firestore недоступен и mode=cached, вернуть 503 Service Unavailable
7. **API compatibility:** НЕ менять формат JSON ответов (AggregateResponse, GroupInfo и т.д.)
8. **Security:** Firestore credentials НЕ должны попасть в git репозиторий

---

## Оценка времени синка

- ~1400 групп
- ~0.5-1 секунда на группу = ~700-1400 секунд = 12-23 минуты
- ~350 уникальных преподавателей
- ~0.3-0.5 секунды на преподавателя = ~105-175 секунд = 2-3 минуты
- Firestore запись: пренебрежимо мало
- **Итого:** ~15-30 минут на полный синк

Запуск 2 раза в день вполне приемлемо.
