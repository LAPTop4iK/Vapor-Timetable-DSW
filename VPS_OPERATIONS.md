# VPS Operations Guide

Полное руководство по работе с DSW Timetable на VPS сервере.

## 📋 Содержание

1. [Структура на сервере](#структура-на-сервере)
2. [Первый запуск](#первый-запуск)
3. [Обновление кода](#обновление-кода)
4. [Работа с логами](#работа-с-логами)
5. [Работа с базой данных](#работа-с-базой-данных)
6. [Управление сервисами](#управление-сервисами)
7. [Обновление параметров](#обновление-параметров)
8. [Синхронизация данных](#синхронизация-данных)
9. [Мониторинг](#мониторинг)
10. [Troubleshooting](#troubleshooting)

---

## Структура на сервере

```
/srv/app/
├── .env                      # Конфигурация (DB пароли, параметры)
├── docker-compose.yml        # Docker Compose конфигурация
├── nginx/
│   ├── certs/               # SSL сертификаты
│   └── nginx.conf           # Nginx конфигурация
├── redeploy.sh              # Скрипт обновления и перезапуска
├── scripts/
│   ├── build-sync.sh        # Сборка SyncRunner
│   ├── run-sync.sh          # Ручной запуск синхронизации
│   └── setup-cron.sh        # Настройка автоматической синхронизации
└── vapor/                   # Git репозиторий
    ├── Sources/
    ├── Package.swift
    ├── Dockerfile
    ├── Dockerfile.sync
    └── ...
```

---

## Первый запуск

### 1. Убедитесь что находитесь в правильной директории
```bash
cd /srv/app
```

### 2. Настройте пароль базы данных
```bash
nano .env
```

**Обязательно** установите `DB_PASSWORD`:
```bash
DB_PASSWORD=your_secure_password_here
DB_USER=vapor
DB_NAME=dsw_timetable
DSW_BACKEND_MODE=cached
DSW_DEFAULT_FROM=2025-09-06
DSW_DEFAULT_TO=2026-02-08
SYNC_DELAY_GROUPS_MS=150
SYNC_DELAY_TEACHERS_MS=100
```

Сохраните: `Ctrl+O`, `Enter`, `Ctrl+X`

### 3. Запустите все сервисы
```bash
cd /srv/app/vapor
./redeploy.sh
```

Этот скрипт автоматически:
- Подтянет последний код из Git
- Скопирует конфигурацию
- Соберет Docker образы
- Запустит контейнеры (PostgreSQL, Vapor API, nginx)

### 4. Проверьте что всё запустилось
```bash
cd /srv/app
docker compose ps
```

Все сервисы должны быть в статусе `healthy` или `running`.

### 5. Запустите первую синхронизацию
```bash
./scripts/run-sync.sh
```

Это заполнит базу данных расписаниями групп и преподавателей.

---

## Обновление кода

### Обновление из Git и перезапуск (рекомендуется)
```bash
cd /srv/app/vapor
./redeploy.sh
```

Скрипт автоматически:
1. Сделает `git pull`
2. Обновит конфигурацию
3. Пересоберет Docker образы
4. Перезапустит контейнеры

### Обновление конкретной ветки
```bash
cd /srv/app/vapor
git fetch origin
git checkout claude/review-commit-fix-011CUd9oTmdJgWh6VZAiiXL3
git pull origin claude/review-commit-fix-011CUd9oTmdJgWh6VZAiiXL3
./redeploy.sh
```

---

## Работа с логами

### Просмотр логов всех контейнеров
```bash
cd /srv/app
docker compose logs
```

### Просмотр логов конкретного сервиса
```bash
# API сервер (Vapor)
docker compose logs vapor

# База данных
docker compose logs postgres

# Nginx
docker compose logs nginx
```

### Просмотр логов в реальном времени (follow)
```bash
# Все сервисы
docker compose logs -f

# Только Vapor API
docker compose logs -f vapor

# Последние 100 строк и follow
docker compose logs -f --tail=100 vapor
```

### Экспорт логов в файл
```bash
# Все логи
docker compose logs > all-logs.txt

# Только Vapor за последний час
docker compose logs --since 1h vapor > vapor-recent.log
```

### Просмотр логов синхронизации (если настроен cron)
```bash
tail -f /srv/app/sync-cron.log
```

---

## Работа с базой данных

### Подключение к PostgreSQL через psql
```bash
cd /srv/app

# Подключиться к базе данных
docker compose exec postgres psql -U vapor -d dsw_timetable
```

### Полезные SQL команды

#### Посмотреть все таблицы
```sql
\dt
```

#### Количество групп в базе
```sql
SELECT COUNT(*) FROM groups;
```

#### Количество преподавателей
```sql
SELECT COUNT(*) FROM teachers;
```

#### Последний статус синхронизации
```sql
SELECT * FROM sync_status ORDER BY timestamp DESC LIMIT 1;
```

#### История синхронизаций
```sql
SELECT
    timestamp,
    status,
    total_groups,
    processed_groups,
    failed_groups,
    duration
FROM sync_status
ORDER BY timestamp DESC
LIMIT 10;
```

#### Поиск группы
```sql
SELECT group_id, group_info FROM groups WHERE group_info::text LIKE '%sem%';
```

#### Информация о конкретной группе
```sql
SELECT * FROM groups WHERE group_id = 1234;
```

#### Список всех групп (только имена)
```sql
SELECT group_id, group_info->'name' as name FROM groups ORDER BY group_id;
```

#### Выход из psql
```sql
\q
```

### Создание резервной копии базы данных
```bash
cd /srv/app

# Полный дамп базы данных
docker compose exec postgres pg_dump -U vapor dsw_timetable > backup-$(date +%Y%m%d-%H%M%S).sql

# Дамп с сжатием
docker compose exec postgres pg_dump -U vapor dsw_timetable | gzip > backup-$(date +%Y%m%d-%H%M%S).sql.gz
```

### Восстановление из резервной копии
```bash
cd /srv/app

# Из обычного дампа
cat backup-20250130-120000.sql | docker compose exec -T postgres psql -U vapor -d dsw_timetable

# Из сжатого дампа
gunzip -c backup-20250130-120000.sql.gz | docker compose exec -T postgres psql -U vapor -d dsw_timetable
```

### Очистка данных (осторожно!)
```bash
# Подключиться к базе
docker compose exec postgres psql -U vapor -d dsw_timetable

# Удалить все группы
TRUNCATE TABLE groups CASCADE;

# Удалить все данные синхронизации
TRUNCATE TABLE teachers CASCADE;
TRUNCATE TABLE groups_list CASCADE;
TRUNCATE TABLE sync_status CASCADE;
```

---

## Управление сервисами

### Проверка статуса
```bash
cd /srv/app
docker compose ps
```

### Запуск всех сервисов
```bash
docker compose up -d
```

### Остановка всех сервисов
```bash
docker compose down
```

### Остановка с удалением volumes (ОСТОРОЖНО - удалит базу данных!)
```bash
docker compose down -v
```

### Перезапуск конкретного сервиса
```bash
# Перезапустить API
docker compose restart vapor

# Перезапустить БД
docker compose restart postgres

# Перезапустить nginx
docker compose restart nginx
```

### Пересборка и перезапуск (после изменения кода)
```bash
# Только Vapor API
docker compose up -d --build vapor

# Все сервисы
docker compose up -d --build
```

### Просмотр использования ресурсов
```bash
# Все контейнеры
docker stats

# Конкретный контейнер
docker stats dsw-postgres
docker stats vapor
docker stats nginx
```

---

## Обновление параметров

### Редактирование .env файла
```bash
cd /srv/app
nano .env
```

### Основные параметры

#### База данных
```bash
DB_PASSWORD=your_secure_password      # Пароль PostgreSQL
DB_USER=vapor                         # Пользователь БД
DB_NAME=dsw_timetable                 # Имя базы данных
```

#### Режим работы API
```bash
# cached - читать из PostgreSQL (рекомендуется для production)
# live - запрашивать напрямую с сайта университета (для разработки)
DSW_BACKEND_MODE=cached
```

#### Параметры семестра (для синхронизации)
```bash
DSW_DEFAULT_FROM=2025-09-06    # Начало семестра
DSW_DEFAULT_TO=2026-02-08      # Конец семестра
```

#### Throttling синхронизации (защита от перегрузки сервера университета)
```bash
SYNC_DELAY_GROUPS_MS=150       # Задержка между группами (мс)
SYNC_DELAY_TEACHERS_MS=100     # Задержка между преподавателями (мс)
```

### Применение изменений после редактирования .env
```bash
cd /srv/app

# Перезапустить сервисы для применения новых переменных
docker compose down
docker compose up -d
```

---

## Синхронизация данных

### Ручной запуск синхронизации
```bash
cd /srv/app
./scripts/run-sync.sh
```

Это запустит процесс синхронизации, который:
1. Получит список всех групп
2. Для каждой группы получит расписание
3. Соберет информацию о преподавателях
4. Сохранит всё в PostgreSQL

**Время выполнения**: ~30-60 минут в зависимости от количества групп.

### Просмотр прогресса синхронизации в реальном времени
```bash
# В отдельном терминале
docker logs -f $(docker ps -q --filter ancestor=dsw-sync-runner:latest)
```

### Настройка автоматической синхронизации (cron)
```bash
cd /srv/app
./scripts/setup-cron.sh
```

По умолчанию синхронизация запускается **каждый день в 3:00 ночи**.

### Изменение времени автоматической синхронизации
```bash
# Редактировать crontab
crontab -e

# Найти строку:
# 0 3 * * * /srv/app/scripts/run-sync.sh >> /srv/app/sync-cron.log 2>&1

# Формат: минута час день месяц день_недели команда
# Примеры:
# 0 2 * * *     - каждый день в 2:00
# 0 */6 * * *   - каждые 6 часов
# 0 0 * * 0     - каждое воскресенье в полночь
```

### Отключение автоматической синхронизации
```bash
crontab -e
# Удалить или закомментировать строку с run-sync.sh
```

### Проверка логов автоматической синхронизации
```bash
tail -f /srv/app/sync-cron.log
```

---

## Мониторинг

### Проверка здоровья API
```bash
# Проверка что API отвечает
curl http://localhost/api/health

# Проверка конкретного эндпоинта
curl http://localhost/groups/search?q=sem
```

### Проверка статуса PostgreSQL
```bash
docker compose exec postgres pg_isready -U vapor
```

### Проверка подключения к базе данных
```bash
docker compose exec postgres psql -U vapor -d dsw_timetable -c "SELECT COUNT(*) FROM groups;"
```

### Мониторинг дискового пространства
```bash
# Общее использование диска
df -h

# Использование Docker
docker system df

# Размер volumes
docker volume ls -q | xargs docker volume inspect | grep -A 5 Mountpoint
```

### Очистка неиспользуемых Docker ресурсов
```bash
# Удалить неиспользуемые образы
docker image prune -a

# Удалить неиспользуемые volumes (ОСТОРОЖНО!)
docker volume prune

# Полная очистка (образы, контейнеры, сети, volumes)
docker system prune -a --volumes
```

---

## Troubleshooting

### Проблема: Контейнер постоянно перезапускается

**Решение 1**: Проверить логи
```bash
docker compose logs vapor
```

**Решение 2**: Проверить что DB_PASSWORD установлен
```bash
grep DB_PASSWORD /srv/app/.env
```

**Решение 3**: Проверить подключение к базе
```bash
docker compose exec postgres psql -U vapor -d dsw_timetable -c "SELECT 1;"
```

### Проблема: API возвращает 404 или 502

**Решение 1**: Проверить что Vapor запущен
```bash
docker compose ps vapor
```

**Решение 2**: Проверить nginx конфигурацию
```bash
docker compose exec nginx nginx -t
```

**Решение 3**: Проверить логи nginx
```bash
docker compose logs nginx
```

### Проблема: Синхронизация не работает

**Решение 1**: Запустить синхронизацию вручную и проверить ошибки
```bash
./scripts/run-sync.sh
```

**Решение 2**: Проверить что образ собран
```bash
docker images | grep dsw-sync-runner
```

**Решение 3**: Пересобрать образ синхронизации
```bash
cd /srv/app/vapor
docker build -f Dockerfile.sync -t dsw-sync-runner:latest .
```

### Проблема: База данных не запускается

**Решение 1**: Проверить что пароль установлен
```bash
cat /srv/app/.env | grep DB_PASSWORD
```

**Решение 2**: Пересоздать контейнер базы данных
```bash
docker compose down
docker volume rm app_postgres_data  # ОСТОРОЖНО - удалит все данные!
docker compose up -d
```

### Проблема: Мало места на диске

**Решение 1**: Проверить использование
```bash
df -h
docker system df
```

**Решение 2**: Удалить старые логи
```bash
# Очистить логи Docker
sudo sh -c 'echo "" > $(docker inspect --format="{{.LogPath}}" vapor)'
sudo sh -c 'echo "" > $(docker inspect --format="{{.LogPath}}" dsw-postgres)'
```

**Решение 3**: Удалить старые Docker образы
```bash
docker image prune -a -f
```

### Проблема: Не могу подключиться к серверу по HTTPS

**Решение 1**: Проверить что nginx запущен
```bash
docker compose ps nginx
```

**Решение 2**: Проверить сертификаты
```bash
ls -la /srv/app/nginx/certs/
```

**Решение 3**: Проверить firewall
```bash
sudo ufw status
sudo ufw allow 443/tcp
```

---

## Быстрая справка команд

```bash
# Обновить код и перезапустить
cd /srv/app/vapor && ./redeploy.sh

# Посмотреть логи API
cd /srv/app && docker compose logs -f vapor

# Запустить синхронизацию
cd /srv/app && ./scripts/run-sync.sh

# Проверить статус контейнеров
cd /srv/app && docker compose ps

# Подключиться к базе данных
cd /srv/app && docker compose exec postgres psql -U vapor -d dsw_timetable

# Перезапустить API
cd /srv/app && docker compose restart vapor

# Редактировать параметры
cd /srv/app && nano .env

# Создать резервную копию БД
cd /srv/app && docker compose exec postgres pg_dump -U vapor dsw_timetable > backup.sql
```

---

## Дополнительная информация

### Порты
- **80** - HTTP (nginx)
- **443** - HTTPS (nginx)
- **5432** - PostgreSQL (только внутри Docker network)
- **8080** - Vapor API (только внутри Docker network)

### Docker Networks
- `app_app-network` - внутренняя сеть для связи контейнеров

### Docker Volumes
- `app_postgres_data` - хранилище данных PostgreSQL

### Полезные ссылки
- Документация Vapor: https://docs.vapor.codes
- Документация PostgreSQL: https://www.postgresql.org/docs/
- Документация Docker Compose: https://docs.docker.com/compose/
