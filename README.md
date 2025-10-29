# DSW Timetable API

REST API для предоставления расписания занятий студентам Dolnośląskiej Szkoły Wyższej.

## Возможности

- 📅 Получение расписания групп и преподавателей
- 🔍 Поиск групп по названию/коду
- 👥 Информация о преподавателях с контактами
- 🚀 Два режима работы: live scraping и cached data (Firestore)
- ⚡ In-memory кеширование для быстрых ответов
- 🔄 Автоматическая синхронизация данных (2 раза в день)
- 🌍 Поддержка таймзоны Europe/Warsaw
- 🎛️ Server-driven feature flags для клиента

## Технологии

- **Backend**: Swift 6, Vapor 4
- **Database**: Google Firestore
- **Parsing**: SwiftSoup
- **Deployment**: Docker, docker-compose, nginx
- **VPS**: OVH (Poland)

## Архитектура

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   Mobile     │────→│    Vapor     │────→│  Firestore   │
│     App      │     │   API Server │     │   (Google)   │
└──────────────┘     └──────────────┘     └──────────────┘
                            ↑                      ↑
                            │                      │
                            │              ┌──────────────┐
                            │              │ SyncRunner   │
                            │              │ (cron 2x/day)│
                            │              └──────┬───────┘
                            │                     │
                     ┌──────────────────────────────┐
                     │   University Website         │
                     │   harmonogramy.dsw.edu.pl    │
                     └──────────────────────────────┘
```

## API Endpoints

### Поиск групп
```http
GET /groups/search?q=INF
```

Возвращает список групп, соответствующих запросу.

### Расписание группы + все преподаватели
```http
GET /api/groups/:id/aggregate?from=2025-09-06&to=2026-02-08&type=3
```

Возвращает:
- Полное расписание группы за период
- **ВСЕ** преподаватели университета с их расписаниями и контактами
- Используется для предзагрузки данных в приложение

### Расписание группы на день
```http
GET /api/groups/:id/schedule?date=2025-11-01
```

Возвращает расписание группы на конкретную дату.
Если `date` не указан - возвращает "сегодня" (Europe/Warsaw timezone).

**Важно**: Этот эндпоинт всегда работает в live режиме (scraping), независимо от `DSW_BACKEND_MODE`.

### Feature Flags
```http
GET /api/feature-flags
```

Возвращает feature flags и параметры для клиентского приложения.

## Быстрый старт

### Локальная разработка

1. Клонируйте репозиторий:
```bash
git clone https://github.com/yourusername/Vapor-Timetable-DSW.git
cd Vapor-Timetable-DSW
```

2. Установите зависимости:
```bash
swift package resolve
```

3. Запустите в live режиме (без Firestore):
```bash
export DSW_BACKEND_MODE=live
export DSW_ENABLE_MOCK=0
swift run DswAggregator
```

4. Проверьте:
```bash
curl http://localhost:8080/groups/search?q=INF
```

### Деплой на VPS с Firestore

См. подробные инструкции:
- [docs/FIRESTORE_SETUP.md](docs/FIRESTORE_SETUP.md) - Настройка Google Firestore
- [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) - Деплой на VPS
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) - Архитектура системы

Краткая инструкция:

1. Настройте Google Firestore и создайте сервисный аккаунт
2. Скопируйте ключ на VPS в `/srv/secrets/`
3. Запустите API сервер:
```bash
cd /srv/app
docker-compose up -d
```

4. Запустите первую синхронизацию:
```bash
docker-compose -f docker-compose.yml -f docker-compose.local.yml run --rm dsw-sync
```

5. Настройте cron для автоматической синхронизации:
```bash
sudo bash /srv/app/scripts/setup-cron.sh
```

6. Переключите на cached режим:
```bash
# Отредактируйте docker-compose.yml:
# DSW_BACKEND_MODE=cached

docker-compose restart vapor
```

## Конфигурация

Основные переменные окружения:

```bash
# Backend mode
DSW_BACKEND_MODE=cached          # 'live' or 'cached'

# Firestore
FIRESTORE_PROJECT_ID=your-project-id
FIRESTORE_CREDENTIALS_PATH=/run/secrets/firestore-service-account.json

# Semester defaults
DSW_DEFAULT_FROM=2025-09-06
DSW_DEFAULT_TO=2026-02-08
DSW_DEFAULT_INTERVAL=semester

# Cache TTLs (seconds)
DSW_TTL_SCHEDULE_SECS=60         # 1 minute
DSW_TTL_SEARCH_SECS=259200       # 3 days
DSW_TTL_AGGREGATE_SECS=18000     # 5 hours

# Feature flags
DSW_FEATURE_FLAGS_JSON={"show_ads":true,"show_debug_menu":false}
DSW_FEATURE_FLAGS_VERSION=1.0.1
```

См. [.env.example](.env.example) для полного списка.

## Режимы работы

### Live Mode
- Каждый запрос scraping с сайта университета
- Медленнее, но всегда актуальные данные
- Используйте для разработки или если Firestore недоступен

### Cached Mode (рекомендуется для production)
- Данные читаются из Firestore
- Быстрые ответы (100-300ms)
- Обновление через SyncRunner 2 раза в день
- `/schedule` endpoint остается live для актуальности

## Синхронизация данных

SyncRunner обходит все ~1400 групп и собирает:
- Расписание каждой группы
- Карточки всех преподавателей (~500)
- Расписания преподавателей

Процесс:
- Длительность: 30-60 минут
- Throttling: 300-1000ms между запросами
- Кеширование преподавателей в памяти
- Запись в Firestore по завершении

Запуск:
```bash
# Вручную
docker-compose -f docker-compose.yml -f docker-compose.local.yml run --rm dsw-sync

# Или через cron скрипт
sudo /srv/app/scripts/sync-runner.sh

# Логи
tail -f /var/log/dsw-sync.log
```

## Структура проекта

```
Sources/
├── DswAggregator/              # Общая библиотека (DswCore)
│   ├── Domain/                 # Модели данных
│   │   ├── Models/             # DTO (AggregateResponse, etc.)
│   │   └── Utils/              # Утилиты (timezone, parsers)
│   ├── Services/               # Бизнес-логика
│   │   ├── AggregationService.swift
│   │   ├── GroupScheduleService.swift
│   │   ├── FirestoreAggregationService.swift
│   │   └── Caching/            # In-memory cache
│   ├── Infrastructure/         # Внешние интеграции
│   │   ├── Clients/            # HTTP клиенты
│   │   ├── Parsing/            # HTML парсеры
│   │   └── Firestore/          # Firestore SDK
│   ├── Presentation/Routes/    # API маршруты
│   └── Config/                 # Конфигурация
├── App/                        # API Server executable
│   └── main.swift
└── SyncRunner/                 # Data sync executable
    └── main.swift

scripts/
├── sync-runner.sh              # Wrapper для cron
└── setup-cron.sh               # Установка cron job

docs/
├── FIRESTORE_SETUP.md          # Настройка Firestore
├── DEPLOYMENT.md               # Деплой на VPS
└── ARCHITECTURE.md             # Архитектура системы
```

## Разработка

### Требования
- macOS 13+ или Linux
- Swift 6.0+
- Docker (для production build)

### Сборка
```bash
swift build
```

### Запуск тестов
```bash
swift test
```

### Форматирование кода
```bash
swift-format -i -r Sources/
```

## Важные замечания

### Совместимость с клиентом

**Не меняйте формат JSON ответов!** Мобильное приложение уже интегрировано с API.

Существующие DTO:
- `AggregateResponse` - должен содержать `teachers` (массив ВСЕХ преподавателей)
- `GroupScheduleResponse` - расписание группы
- `TeacherCard` - карточка преподавателя
- `GroupInfo` - информация о группе

### Timezone

Все времена используют **Europe/Warsaw** timezone для корректного отображения расписания.

### Преподаватели в aggregate

С новой архитектурой `/api/groups/:id/aggregate` возвращает **всех** преподавателей университета, а не только преподавателей конкретной группы. Это необходимо для предзагрузки данных в приложение.

### Rate Limiting

При использовании live mode:
- Throttling между запросами к университету
- In-memory cache для снижения нагрузки
- Риск временной блокировки при большом количестве запросов

Решение: используйте cached mode в production.

## Мониторинг

### Проверка health
```bash
curl https://api.dsw.wtf/groups/search
```

### Просмотр логов
```bash
# API логи
docker-compose logs -f vapor

# Sync логи
tail -f /var/log/dsw-sync.log
```

### Статус синхронизации
Проверьте Firestore: `metadata/lastSync`

### Firestore usage
Google Cloud Console → Firestore → Usage

## Лицензия

Proprietary - все права защищены.

## Контакты

- **Автор**: LAPTop4iK
- **VPS**: api.dsw.wtf
- **Университет**: Dolnośląska Szkoła Wyższa

---

Сделано с ❤️ и Swift
