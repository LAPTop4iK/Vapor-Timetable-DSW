# DSW Timetable - Deployment Guide

Это руководство описывает процесс развертывания DSW Timetable API с Firestore интеграцией на VPS.

## Оглавление

1. [Предварительные требования](#предварительные-требования)
2. [Настройка Firestore](#настройка-firestore)
3. [Подготовка VPS](#подготовка-vps)
4. [Развертывание приложения](#развертывание-приложения)
5. [Настройка Cron](#настройка-cron)
6. [Первый запуск синхронизации](#первый-запуск-синхронизации)
7. [Переключение на Firestore режим](#переключение-на-firestore-режим)
8. [Мониторинг и устранение неполадок](#мониторинг-и-устранение-неполадок)

---

## Предварительные требования

- VPS с Ubuntu 20.04+ (Poland region для польского IP)
- Docker и Docker Compose установлены
- Доступ к Google Cloud Console
- Домен api.dsw.wtf с настроенными DNS записями
- SSL сертификаты (Let's Encrypt)

---

## Настройка Firestore

### 1. Создание проекта в Google Cloud

```bash
# Войти в Google Cloud Console: https://console.cloud.google.com/

# 1. Создать новый проект
#    Название: dsw-timetable-prod (или любое другое)
#    ID проекта: dsw-timetable-prod

# 2. Включить Firestore API
#    Navigation Menu → Firestore → Enable API
#    Выбрать "Native mode"
#    Регион: europe-central2 (Warsaw) или ближайший

# 3. Создать сервисный аккаунт
#    Navigation Menu → IAM & Admin → Service Accounts
#    → Create Service Account

# Параметры:
#   Name: firestore-sync-service
#   ID: firestore-sync-service
#   Role: Cloud Datastore User

# 4. Создать ключ
#    Actions → Manage Keys → Add Key → Create New Key
#    Type: JSON
#    Скачать файл (firestore-service-account.json)
```

### 2. Загрузка ключа на VPS

```bash
# На локальной машине
scp firestore-service-account.json user@api.dsw.wtf:/tmp/

# На VPS
ssh user@api.dsw.wtf
sudo mkdir -p /srv/secrets
sudo mv /tmp/firestore-service-account.json /srv/secrets/
sudo chmod 600 /srv/secrets/firestore-service-account.json
sudo chown root:root /srv/secrets/firestore-service-account.json
```

---

## Подготовка VPS

### 1. Создание директорий

```bash
# Основная директория проекта
sudo mkdir -p /srv/dsw-timetable
sudo chown -R $USER:$USER /srv/dsw-timetable

# Директория для логов
mkdir -p /srv/dsw-timetable/logs
chmod 755 /srv/dsw-timetable/logs
```

### 2. Клонирование репозитория

```bash
cd /srv/dsw-timetable
git clone <repository-url> .
# или
git pull origin main
```

### 3. Настройка окружения

```bash
# Создать .env файл (опционально)
cat > .env <<EOF
FIRESTORE_PROJECT_ID=dsw-timetable-prod
DSW_DEFAULT_FROM=2025-09-06
DSW_DEFAULT_TO=2026-02-08
DSW_DEFAULT_INTERVAL=semester
DSW_BACKEND_MODE=live
EOF
```

---

## Развертывание приложения

### 1. Сборка Docker образов

```bash
cd /srv/dsw-timetable

# Собрать Vapor API
docker compose -f docker-compose.prod.yml build vapor

# Собрать SyncRunner
docker compose -f docker-compose.prod.yml build sync-runner
```

### 2. Запуск Vapor API (live mode)

```bash
# Запустить в live режиме (без Firestore)
docker compose -f docker-compose.prod.yml up -d vapor nginx

# Проверить логи
docker logs vapor -f

# Проверить что API работает
curl http://localhost:8080/groups/search?q=inf
```

### 3. Проверка здоровья API

```bash
# Проверить /groups/search
curl -X GET "http://localhost:8080/groups/search?q=sem" | jq

# Проверить /api/groups/:id/schedule (должен вернуть расписание на сегодня)
curl -X GET "http://localhost:8080/api/groups/12345/schedule" | jq

# Проверить feature flags
curl -X GET "http://localhost:8080/api/feature-flags" | jq
```

---

## Настройка Cron

### 1. Установка скрипта синхронизации

```bash
# Скопировать скрипт
sudo cp /srv/dsw-timetable/scripts/dsw-sync.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/dsw-sync.sh

# Проверить что скрипт работает
sudo /usr/local/bin/dsw-sync.sh --help
```

### 2. Настройка cron job

```bash
# Скопировать cron файл
sudo cp /srv/dsw-timetable/scripts/dsw-sync.cron /etc/cron.d/dsw-sync
sudo chmod 644 /etc/cron.d/dsw-sync

# Перезапустить cron
sudo systemctl restart cron

# Проверить что cron job добавлен
sudo crontab -l
# или
cat /etc/cron.d/dsw-sync
```

### 3. Настройка логирования

```bash
# Создать файл логов
sudo touch /var/log/dsw-sync-cron.log
sudo chmod 644 /var/log/dsw-sync-cron.log

# Настроить logrotate (опционально)
sudo tee /etc/logrotate.d/dsw-sync <<EOF
/var/log/dsw-sync-cron.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
}
EOF
```

---

## Первый запуск синхронизации

### 1. Тестовый запуск (вручную)

```bash
# ВАЖНО: Первый sync может занять 15-30 минут для ~1400 групп

# Запустить вручную
cd /srv/dsw-timetable
sudo docker compose -f docker-compose.prod.yml run --rm sync-runner

# Мониторить прогресс
tail -f /srv/dsw-timetable/logs/sync.log
```

### 2. Проверка данных в Firestore

```bash
# Зайти в Firestore Console
# https://console.cloud.google.com/firestore/data

# Проверить коллекции:
# - groups/<groupId> - должны быть документы для каждой группы
# - teachers/<teacherId> - документы преподавателей
# - metadata/groupsList - список всех групп
# - metadata/allTeachers - список всех teacherId
# - metadata/lastSync - статус последнего синка
```

### 3. Проверка статуса синхронизации

Можно создать простой скрипт для проверки:

```bash
#!/bin/bash
# check-sync-status.sh

curl -s "https://firestore.googleapis.com/v1/projects/dsw-timetable-prod/databases/(default)/documents/metadata/lastSync" \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" | jq
```

---

## Переключение на Firestore режим

### 1. Обновление конфигурации

```bash
# Остановить Vapor
cd /srv/dsw-timetable
docker compose -f docker-compose.prod.yml stop vapor

# Обновить .env или docker-compose.prod.yml
# Изменить: DSW_BACKEND_MODE=live → DSW_BACKEND_MODE=cached

# Для docker-compose.prod.yml:
nano docker-compose.prod.yml
# Найти строку:
#   - DSW_BACKEND_MODE=live
# Изменить на:
#   - DSW_BACKEND_MODE=cached
```

### 2. Перезапуск с Firestore режимом

```bash
# Пересобрать (если нужно)
docker compose -f docker-compose.prod.yml build vapor

# Запустить
docker compose -f docker-compose.prod.yml up -d vapor

# Проверить логи
docker logs vapor -f

# Должны увидеть:
# "Firestore service initialized in cached mode"
```

### 3. Тестирование Firestore режима

```bash
# Проверить /groups/search (должен читать из Firestore)
curl -X GET "http://localhost:8080/groups/search?q=inf" | jq

# Проверить /api/groups/:id/aggregate (должен вернуть ВСЕХ преподавателей)
curl -X GET "http://localhost:8080/api/groups/12345/aggregate" | jq '.teachers | length'

# /api/groups/:id/schedule всё ещё должен работать в live режиме
curl -X GET "http://localhost:8080/api/groups/12345/schedule" | jq
```

---

## Мониторинг и устранение неполадок

### 1. Логи

```bash
# Vapor API логи
docker logs vapor -f

# Sync runner логи
cat /srv/dsw-timetable/logs/*.log

# Cron логи
tail -f /var/log/dsw-sync-cron.log

# System logs
sudo journalctl -u docker -f
```

### 2. Проверка статуса контейнеров

```bash
# Список запущенных контейнеров
docker ps

# Проверка ресурсов
docker stats
```

### 3. Ручной запуск sync

```bash
# Если cron не сработал или нужно обновить данные вручную
cd /srv/dsw-timetable
sudo /usr/local/bin/dsw-sync.sh
```

### 4. Откат на live режим

```bash
# Если что-то пошло не так с Firestore
docker compose -f docker-compose.prod.yml stop vapor

# Изменить DSW_BACKEND_MODE=cached → DSW_BACKEND_MODE=live
nano docker-compose.prod.yml

# Перезапустить
docker compose -f docker-compose.prod.yml up -d vapor
```

### 5. Очистка и перезапуск

```bash
# Полная очистка и пересборка
cd /srv/dsw-timetable
docker compose -f docker-compose.prod.yml down
docker system prune -a
docker compose -f docker-compose.prod.yml build
docker compose -f docker-compose.prod.yml up -d
```

### 6. Частые проблемы

#### Проблема: Firestore service not configured

**Решение:**
```bash
# Проверить что credentials существуют
ls -la /srv/secrets/firestore-service-account.json

# Проверить что путь правильный в docker-compose.prod.yml
cat docker-compose.prod.yml | grep FIRESTORE_CREDENTIALS_PATH

# Проверить права доступа
sudo chmod 600 /srv/secrets/firestore-service-account.json
```

#### Проблема: Sync timeout / too slow

**Решение:**
```bash
# Увеличить throttling intervals в SyncRunner
# Или запускать sync реже (раз в день вместо 2 раз)
```

#### Проблема: University website blocks requests

**Решение:**
```bash
# Проверить что VPS в Польше
curl ipinfo.io

# Увеличить delays между запросами
# Проверить User-Agent в VaporDSWClient
```

#### Проблема: Wrong timezone for /schedule

**Решение:**
```bash
# Проверить что используется Europe/Warsaw
docker exec vapor date
# Должно показывать Warsaw time

# Если нет, добавить в docker-compose.prod.yml:
#   environment:
#     - TZ=Europe/Warsaw
```

---

## Архитектурные заметки

### Режимы работы

1. **Live mode** (`DSW_BACKEND_MODE=live`)
   - `/api/groups/:id/aggregate` - скрейпит университетский сайт
   - `/groups/search` - скрейпит университетский сайт
   - `/api/groups/:id/schedule` - скрейпит один день (с кешем 60 сек)

2. **Cached mode** (`DSW_BACKEND_MODE=cached`)
   - `/api/groups/:id/aggregate` - читает из Firestore, возвращает ВСЕХ преподавателей
   - `/groups/search` - читает из Firestore
   - `/api/groups/:id/schedule` - всё ещё скрейпит (live) один день (с кешем 60 сек)

### Firestore коллекции

- `groups/{groupId}` - расписание группы + метаданные
- `teachers/{teacherId}` - карточка преподавателя + расписание
- `metadata/groupsList` - полный список групп
- `metadata/allTeachers` - список всех teacherId
- `metadata/lastSync` - статус последнего синка

### Caching strategy

- **In-memory cache** (InMemoryCacheStore):
  - Group schedule: 30 min
  - Group search: 3 days
  - Aggregate: 5 hours (reset at 8 AM)
  - Teacher cards: 5 hours (reset at 8 AM)
  - **NEW: Daily schedule: 60 seconds**

- **Firestore** (persistent):
  - Данные обновляются 2 раза в день через cron
  - Полный sync занимает ~15-30 минут

---

## Checklist для деплоя

- [ ] Firestore проект создан и настроен
- [ ] Service account ключ скачан и загружен на VPS
- [ ] Docker и Docker Compose установлены
- [ ] Репозиторий клонирован в /srv/dsw-timetable
- [ ] Docker образы собраны (vapor, sync-runner)
- [ ] Vapor запущен в live режиме и работает
- [ ] Cron скрипт установлен (/usr/local/bin/dsw-sync.sh)
- [ ] Cron job настроен (/etc/cron.d/dsw-sync)
- [ ] Первый sync выполнен успешно
- [ ] Данные появились в Firestore
- [ ] DSW_BACKEND_MODE изменен на "cached"
- [ ] Vapor перезапущен в cached режиме
- [ ] API тестирование пройдено
- [ ] Мониторинг логов настроен
- [ ] Мобильное приложение протестировано с новым API

---

## Поддержка

При возникновении проблем:

1. Проверить логи (см. раздел "Мониторинг")
2. Проверить статус Firestore в Console
3. Попробовать откат на live режим
4. Запустить sync вручную с increased logging

Для вопросов и багов: создать issue в репозитории.
