# Настройка Firestore для DSW Timetable

## Обзор архитектуры

Система использует Google Firestore как единственное хранилище данных:
- **groups/{groupId}** - расписание и информация о группе
- **teachers/{teacherId}** - карточка и расписание преподавателя
- **metadata/groupsList** - список всех групп
- **metadata/allTeachers** - список всех ID преподавателей
- **metadata/lastSync** - статус последней синхронизации

## Шаг 1: Создание проекта Google Cloud

1. Перейдите в [Google Cloud Console](https://console.cloud.google.com/)
2. Создайте новый проект (например, "dsw-timetable-prod")
3. Запомните **Project ID** (будет использоваться в конфигурации)

## Шаг 2: Включение Firestore

1. В меню навигации выберите **Firestore** (или найдите "Firestore" в поиске)
2. Нажмите **Create Database**
3. Выберите режим: **Native mode** (не Datastore mode!)
4. Выберите локацию: **europe-west3 (Frankfurt)** или близкую к Польше
5. Выберите правила безопасности: **Production mode** (закрытые правила)
6. Нажмите **Create Database**

## Шаг 3: Создание сервисного аккаунта

1. В меню навигации выберите **IAM & Admin** → **Service Accounts**
2. Нажмите **Create Service Account**
3. Введите данные:
   - **Service account name**: `dsw-sync-runner`
   - **Service account ID**: `dsw-sync-runner` (автоматически)
   - **Description**: `Service account for DSW timetable sync runner`
4. Нажмите **Create and Continue**
5. Добавьте роли:
   - **Cloud Datastore User** (для чтения/записи в Firestore)
   - Или более точная роль: **roles/datastore.user**
6. Нажмите **Continue** → **Done**

## Шаг 4: Создание ключа для сервисного аккаунта

1. В списке сервисных аккаунтов найдите `dsw-sync-runner`
2. Нажмите на email аккаунта
3. Перейдите на вкладку **Keys**
4. Нажмите **Add Key** → **Create new key**
5. Выберите формат: **JSON**
6. Нажмите **Create**
7. Файл ключа автоматически скачается (например, `dsw-timetable-prod-abc123.json`)

**ВАЖНО**: Сохраните этот файл в безопасном месте! Его нельзя восстановить.

## Шаг 5: Настройка правил безопасности Firestore

1. В Firestore перейдите на вкладку **Rules**
2. Установите следующие правила:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Запретить все публичные операции
    match /{document=**} {
      allow read, write: if false;
    }

    // Доступ только через сервисный аккаунт
    // (правила применяются только для клиентских SDK, не для admin SDK)
  }
}
```

3. Нажмите **Publish**

Эти правила блокируют публичный доступ. Ваш сервисный аккаунт будет иметь доступ через Admin SDK независимо от этих правил.

## Шаг 6: Копирование ключа на VPS

1. Подключитесь к VPS:
```bash
ssh root@your-vps-ip
```

2. Создайте директорию для секретов:
```bash
mkdir -p /srv/secrets
chmod 700 /srv/secrets
```

3. Скопируйте JSON ключ на VPS (с локальной машины):
```bash
scp dsw-timetable-prod-abc123.json root@your-vps-ip:/srv/secrets/firestore-service-account.json
```

4. Установите правильные права:
```bash
chmod 600 /srv/secrets/firestore-service-account.json
```

## Шаг 7: Проверка настройки

Файл JSON должен содержать примерно следующую структуру:

```json
{
  "type": "service_account",
  "project_id": "dsw-timetable-prod",
  "private_key_id": "abc123...",
  "private_key": "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n",
  "client_email": "dsw-sync-runner@dsw-timetable-prod.iam.gserviceaccount.com",
  "client_id": "123456789",
  "auth_uri": "https://accounts.google.com/o/oauth2/auth",
  "token_uri": "https://oauth2.googleapis.com/token",
  ...
}
```

Основные поля:
- `project_id` - ID вашего Google Cloud проекта
- `private_key` - приватный ключ для подписи JWT
- `client_email` - email сервисного аккаунта

## Шаг 8: Настройка переменных окружения

Добавьте в docker-compose на VPS следующие переменные:

```yaml
environment:
  # Firestore config
  - FIRESTORE_PROJECT_ID=dsw-timetable-prod
  - FIRESTORE_CREDENTIALS_PATH=/run/secrets/firestore-service-account.json

  # Backend mode
  - DSW_BACKEND_MODE=cached  # Использовать Firestore вместо live scraping

volumes:
  - /srv/secrets/firestore-service-account.json:/run/secrets/firestore-service-account.json:ro
```

## Тестирование

1. Запустите синхронизацию вручную:
```bash
cd /srv/app
docker-compose -f docker-compose.yml -f docker-compose.local.yml run --rm dsw-sync
```

2. Проверьте логи на наличие ошибок

3. Проверьте данные в Firestore:
   - Откройте [Firestore Console](https://console.cloud.google.com/firestore)
   - Проверьте наличие коллекций: `groups`, `teachers`, `metadata`

4. Проверьте API:
```bash
curl https://api.dsw.wtf/groups/search
```

## Безопасность

1. **Никогда не коммитьте** JSON ключ в git
2. Храните ключ только на VPS в `/srv/secrets/`
3. Используйте правильные права доступа: `chmod 600`
4. Ротируйте ключи периодически (раз в год)
5. Мониторьте использование Firestore в Cloud Console

## Стоимость

Google Firestore имеет бесплатный tier:
- 1 GB хранилища
- 50,000 операций чтения/день
- 20,000 операций записи/день

Для ~1400 групп и ~500 преподавателей:
- Размер данных: ~100-200 MB (в пределах бесплатного tier)
- Синхронизация 2 раза в день: ~3000 записей = в пределах бесплатного tier
- API запросы от клиентов: зависит от трафика

**Рекомендация**: Установите бюджетные алерты в Google Cloud Console на $5-10/месяц для контроля.
