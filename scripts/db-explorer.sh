#!/bin/bash
set -euo pipefail

# Colors for better UI
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

APP_DIR="/srv/app"

# Function to execute SQL query
execute_query() {
    local query="$1"
    docker compose -f "$APP_DIR/docker-compose.yml" exec -T postgres psql -U vapor -d dsw_timetable -c "$query"
}

# Function to show header
show_header() {
    clear
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}${BOLD}          DSW Timetable Database Explorer${NC}                  ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Function to wait for user
wait_for_user() {
    echo ""
    echo -e "${YELLOW}Press ENTER to continue...${NC}"
    read
}

# Menu functions
show_menu() {
    show_header
    echo -e "${BOLD}📊 СТАТИСТИКА И ОБЩАЯ ИНФОРМАЦИЯ${NC}"
    echo -e "  ${GREEN}1${NC})  Общая статистика базы данных"
    echo -e "  ${GREEN}2${NC})  Статистика последней синхронизации"
    echo -e "  ${GREEN}3${NC})  История последних 10 синхронизаций"
    echo ""
    echo -e "${BOLD}👥 ПРЕПОДАВАТЕЛИ${NC}"
    echo -e "  ${GREEN}4${NC})  Список всех преподавателей (ID + Имя)"
    echo -e "  ${GREEN}5${NC})  Количество преподавателей"
    echo -e "  ${GREEN}6${NC})  Топ-10 самых занятых преподавателей"
    echo -e "  ${GREEN}7${NC})  Преподаватели без занятий"
    echo -e "  ${GREEN}8${NC})  Преподаватели по кафедрам"
    echo -e "  ${GREEN}9${NC})  Поиск преподавателя по имени"
    echo ""
    echo -e "${BOLD}🎓 ГРУППЫ${NC}"
    echo -e "  ${GREEN}10${NC}) Список всех групп"
    echo -e "  ${GREEN}11${NC}) Количество групп"
    echo -e "  ${GREEN}12${NC}) Топ-10 групп с наибольшим количеством занятий"
    echo -e "  ${GREEN}13${NC}) Группы без занятий"
    echo -e "  ${GREEN}14${NC}) Группы с идентичным расписанием"
    echo -e "  ${GREEN}15${NC}) Группы по факультетам"
    echo -e "  ${GREEN}16${NC}) Поиск группы по названию"
    echo ""
    echo -e "${BOLD}📈 АНАЛИТИКА${NC}"
    echo -e "  ${GREEN}17${NC}) Преподаватели с наибольшим числом групп"
    echo -e "  ${GREEN}18${NC}) Группы с наибольшим числом преподавателей"
    echo -e "  ${GREEN}19${NC}) Средняя нагрузка преподавателей"
    echo -e "  ${GREEN}20${NC}) Размеры таблиц в базе данных"
    echo ""
    echo -e "${BOLD}🔧 СЛУЖЕБНОЕ${NC}"
    echo -e "  ${GREEN}21${NC}) Прямое подключение к PostgreSQL (psql)"
    echo -e "  ${GREEN}22${NC}) Выполнить произвольный SQL запрос"
    echo -e "  ${GREEN}23${NC}) Группы с одинаковым НЕ пустым расписанием (кластеры)"
    echo -e "  ${GREEN}24${NC}) Группы с одинаковым пустым расписанием"
    echo ""
    echo -e "  ${RED}0${NC})  Выход"
    echo ""
    echo -e -n "${BOLD}Выберите команду: ${NC}"
}

# Query functions
query_1() {
    show_header
    echo -e "${BOLD}📊 Общая статистика базы данных${NC}"
    echo ""
    execute_query "
    SELECT
        'Groups' as table_name,
        COUNT(*) as total_records,
        COUNT(*) FILTER (WHERE fetched_at IS NOT NULL) as with_fetch_time,
        TO_CHAR(MAX(fetched_at), 'YYYY-MM-DD HH24:MI:SS') as last_updated
    FROM groups
    UNION ALL
    SELECT
        'Teachers',
        COUNT(*),
        COUNT(*) FILTER (WHERE fetched_at IS NOT NULL),
        TO_CHAR(MAX(fetched_at), 'YYYY-MM-DD HH24:MI:SS')
    FROM teachers
    UNION ALL
    SELECT
        'Groups List',
        COUNT(*),
        COUNT(*),
        TO_CHAR(MAX(updated_at), 'YYYY-MM-DD HH24:MI:SS')
    FROM groups_list
    UNION ALL
    SELECT
        'Sync Status',
        COUNT(*),
        COUNT(*),
        TO_CHAR(MAX(timestamp), 'YYYY-MM-DD HH24:MI:SS')
    FROM sync_status;
    "
    wait_for_user
}

query_2() {
    show_header
    echo -e "${BOLD}📊 Статистика последней синхронизации${NC}"
    echo ""
    execute_query "
    SELECT
        TO_CHAR(timestamp, 'YYYY-MM-DD HH24:MI:SS') as timestamp,
        status,
        total_groups,
        processed_groups,
        failed_groups,
        ROUND(duration::numeric, 2) as duration_sec,
        ROUND((processed_groups::numeric / NULLIF(total_groups, 0) * 100), 2) as success_rate_percent,
        COALESCE(error_message, 'No errors') as error_message
    FROM sync_status
    ORDER BY timestamp DESC
    LIMIT 1;
    "
    wait_for_user
}

query_3() {
    show_header
    echo -e "${BOLD}📊 История последних 10 синхронизаций${NC}"
    echo ""
    execute_query "
    SELECT
        TO_CHAR(timestamp, 'YYYY-MM-DD HH24:MI:SS') as timestamp,
        status,
        total_groups,
        processed_groups,
        failed_groups,
        ROUND(duration::numeric, 2) as duration_sec
    FROM sync_status
    ORDER BY timestamp DESC
    LIMIT 10;
    "
    wait_for_user
}

query_4() {
    show_header
    echo -e "${BOLD}👥 Список всех преподавателей${NC}"
    echo ""
    execute_query "
    SELECT
        id,
        COALESCE(name, 'Unknown') as name,
        COALESCE(title, '-') as title,
        COALESCE(department, '-') as department
    FROM teachers
    ORDER BY name;
    " | head -100
    echo ""
    echo -e "${YELLOW}(показаны первые 100 записей)${NC}"
    wait_for_user
}

query_5() {
    show_header
    echo -e "${BOLD}👥 Количество преподавателей${NC}"
    echo ""
    execute_query "
    SELECT
        COUNT(*) as total_teachers,
        COUNT(DISTINCT department) as unique_departments,
        COUNT(*) FILTER (WHERE email IS NOT NULL) as teachers_with_email,
        COUNT(*) FILTER (WHERE phone IS NOT NULL) as teachers_with_phone,
        COUNT(*) FILTER (WHERE schedule != '[]') as teachers_with_schedule
    FROM teachers;
    "
    wait_for_user
}

query_6() {
    show_header
    echo -e "${BOLD}👥 Топ-10 самых занятых преподавателей${NC}"
    echo ""
    execute_query "
    SELECT
        id,
        COALESCE(name, 'Unknown') as name,
        COALESCE(title, '-') as title,
        COALESCE(department, '-') as department,
        CASE
            WHEN schedule = '[]' THEN 0
            ELSE jsonb_array_length(schedule::jsonb)
        END as events_count
    FROM teachers
    WHERE schedule IS NOT NULL
    ORDER BY events_count DESC
    LIMIT 10;
    "
    wait_for_user
}

query_7() {
    show_header
    echo -e "${BOLD}👥 Преподаватели без занятий${NC}"
    echo ""
    execute_query "
    SELECT
        id,
        COALESCE(name, 'Unknown') as name,
        COALESCE(title, '-') as title,
        COALESCE(department, '-') as department
    FROM teachers
    WHERE schedule = '[]'
       OR jsonb_array_length(schedule::jsonb) = 0
    ORDER BY name;
    "
    wait_for_user
}

query_8() {
    show_header
    echo -e "${BOLD}👥 Преподаватели по кафедрам${NC}"
    echo ""
    execute_query "
    SELECT
        COALESCE(department, 'Unknown') as department,
        COUNT(*) as teachers_count
    FROM teachers
    GROUP BY department
    ORDER BY teachers_count DESC;
    "
    wait_for_user
}

query_9() {
    show_header
    echo -e "${BOLD}👥 Поиск преподавателя по имени${NC}"
    echo ""
    echo -e -n "Введите часть имени: "
    read search_term
    echo ""
    execute_query "
    SELECT
        id,
        name,
        COALESCE(title, '-') as title,
        COALESCE(department, '-') as department,
        COALESCE(email, '-') as email
    FROM teachers
    WHERE name ILIKE '%$search_term%'
    ORDER BY name;
    "
    wait_for_user
}

query_10() {
    show_header
    echo -e "${BOLD}🎓 Список всех групп${NC}"
    echo ""
    execute_query "
    SELECT
        group_id,
        group_info->>'code' as code,
        group_info->>'name' as name,
        group_info->>'faculty' as faculty
    FROM groups
    ORDER BY group_info->>'name';
    " | head -100
    echo ""
    echo -e "${YELLOW}(показаны первые 100 записей)${NC}"
    wait_for_user
}

query_11() {
    show_header
    echo -e "${BOLD}🎓 Количество групп${NC}"
    echo ""
    execute_query "
    SELECT
        COUNT(*) as total_groups,
        COUNT(DISTINCT group_info->>'faculty') as unique_faculties,
        COUNT(*) FILTER (WHERE group_schedule != '[]') as groups_with_schedule
    FROM groups;
    "
    wait_for_user
}

query_12() {
    show_header
    echo -e "${BOLD}🎓 Топ-10 групп с наибольшим количеством занятий${NC}"
    echo ""
    execute_query "
    SELECT
        group_id,
        group_info->>'code' as code,
        group_info->>'name' as name,
        jsonb_array_length(group_schedule::jsonb) as events_count
    FROM groups
    ORDER BY events_count DESC
    LIMIT 10;
    "
    wait_for_user
}

query_13() {
    show_header
    echo -e "${BOLD}🎓 Группы без занятий${NC}"
    echo ""
    execute_query "
    SELECT
        group_id,
        group_info->>'code' as code,
        group_info->>'name' as name,
        group_info->>'faculty' as faculty
    FROM groups
    WHERE group_schedule = '[]'
       OR jsonb_array_length(group_schedule::jsonb) = 0
    ORDER BY group_info->>'name';
    "
    wait_for_user
}

query_14() {
    show_header
    echo -e "${BOLD}🎓 Группы с идентичным расписанием${NC}"
    echo ""
    execute_query "
    SELECT
        g1.group_id as group1_id,
        g1.group_info->>'name' as group1_name,
        g2.group_id as group2_id,
        g2.group_info->>'name' as group2_name,
        jsonb_array_length(g1.group_schedule::jsonb) as events_count
    FROM groups g1
    JOIN groups g2 ON g1.group_schedule = g2.group_schedule
        AND g1.group_id < g2.group_id
    ORDER BY events_count DESC;
    "
    wait_for_user
}

query_15() {
    show_header
    echo -e "${BOLD}🎓 Группы по факультетам${NC}"
    echo ""
    execute_query "
    SELECT
        group_info->>'faculty' as faculty,
        COUNT(*) as groups_count
    FROM groups
    GROUP BY group_info->>'faculty'
    ORDER BY groups_count DESC;
    "
    wait_for_user
}

query_16() {
    show_header
    echo -e "${BOLD}🎓 Поиск группы по названию${NC}"
    echo ""
    echo -e -n "Введите часть названия: "
    read search_term
    echo ""
    execute_query "
    SELECT
        group_id,
        group_info->>'code' as code,
        group_info->>'name' as name,
        group_info->>'faculty' as faculty,
        jsonb_array_length(group_schedule::jsonb) as events_count
    FROM groups
    WHERE group_info->>'name' ILIKE '%$search_term%'
       OR group_info->>'code' ILIKE '%$search_term%'
    ORDER BY group_info->>'name';
    "
    wait_for_user
}

query_17() {
    show_header
    echo -e "${BOLD}📈 Преподаватели с наибольшим числом групп${NC}"
    echo ""
    execute_query "
    SELECT
        t.id,
        t.name,
        COALESCE(t.department, '-') as department,
        COUNT(g.group_id) as groups_count
    FROM teachers t
    LEFT JOIN groups g ON t.id = ANY(g.teacher_ids)
    GROUP BY t.id, t.name, t.department
    ORDER BY groups_count DESC
    LIMIT 10;
    "
    wait_for_user
}

query_18() {
    show_header
    echo -e "${BOLD}📈 Группы с наибольшим числом преподавателей${NC}"
    echo ""
    execute_query "
    SELECT
        group_id,
        group_info->>'code' as code,
        group_info->>'name' as name,
        array_length(teacher_ids, 1) as teachers_count
    FROM groups
    ORDER BY teachers_count DESC NULLS LAST
    LIMIT 10;
    "
    wait_for_user
}

query_19() {
    show_header
    echo -e "${BOLD}📈 Средняя нагрузка преподавателей${NC}"
    echo ""
    execute_query "
    SELECT
        ROUND(AVG(events_count), 2) as avg_events,
        MIN(events_count) as min_events,
        MAX(events_count) as max_events,
        COUNT(*) as total_teachers
    FROM (
        SELECT
            id,
            CASE
                WHEN schedule = '[]' THEN 0
                ELSE jsonb_array_length(schedule::jsonb)
            END as events_count
        FROM teachers
    ) t;
    "
    wait_for_user
}

query_20() {
    show_header
    echo -e "${BOLD}📈 Размеры таблиц в базе данных${NC}"
    echo ""
    execute_query "
    SELECT
        schemaname as schema,
        tablename as table_name,
        pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
    FROM pg_tables
    WHERE schemaname = 'public'
    ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
    "
    wait_for_user
}

query_21() {
    show_header
    echo -e "${BOLD}🔧 Прямое подключение к PostgreSQL${NC}"
    echo ""
    echo -e "${YELLOW}Подключаемся к базе данных...${NC}"
    echo -e "${YELLOW}Для выхода введите: \\q${NC}"
    echo ""
    docker compose -f "$APP_DIR/docker-compose.yml" exec postgres psql -U vapor -d dsw_timetable
}

query_22() {
    show_header
    echo -e "${BOLD}🔧 Выполнить произвольный SQL запрос${NC}"
    echo ""
    echo -e "${YELLOW}Введите SQL запрос (для многострочного - завершите точкой с запятой):${NC}"
    echo -e -n "${BOLD}SQL> ${NC}"
    read sql_query
    echo ""
    if [ -n "$sql_query" ]; then
        execute_query "$sql_query" || echo -e "${RED}Ошибка выполнения запроса${NC}"
    else
        echo -e "${RED}Пустой запрос${NC}"
    fi
    wait_for_user
}

query_23() {
    show_header
    echo -e "${BOLD}🎓 Группы с одинаковым НЕ пустым расписанием (кластеры)${NC}"
    echo ""
    execute_query "
    WITH schedule_buckets AS (
        SELECT
            group_schedule::jsonb                           AS sched,
            jsonb_array_length(group_schedule::jsonb)       AS events_count,
            COUNT(*)                                        AS groups_count,
            ARRAY_AGG(group_id ORDER BY group_id)           AS group_ids,
            ARRAY_AGG(group_info->>'name' ORDER BY group_info->>'name') AS group_names
        FROM groups
        WHERE group_schedule IS NOT NULL
          AND group_schedule <> '[]'
          AND jsonb_array_length(group_schedule::jsonb) > 0
        GROUP BY group_schedule
        HAVING COUNT(*) > 1
    )
    SELECT
        groups_count,
        events_count,
        group_ids,
        group_names
    FROM schedule_buckets
    ORDER BY groups_count DESC, events_count DESC;
    "
    echo ""
    echo -e "${YELLOW}Каждая строка — кластер групп с полностью идентичным НЕ пустым расписанием.${NC}"
    wait_for_user
}

query_24() {
    show_header
    echo -e "${BOLD}🎓 Группы с пустым расписанием${NC}"
    echo ""
    # Столбец с ID групп
    execute_query "
    SELECT
        group_id AS id
    FROM groups
    WHERE group_schedule IS NOT NULL
      AND (group_schedule = '[]' OR jsonb_array_length(group_schedule::jsonb) = 0)
    ORDER BY group_id;
    "
    echo ""
    # Внизу — всего таких групп
    execute_query "
    SELECT
        COUNT(*) AS total_empty_groups
    FROM groups
    WHERE group_schedule IS NOT NULL
      AND (group_schedule = '[]' OR jsonb_array_length(group_schedule::jsonb) = 0);
    "
    wait_for_user
}

# Main loop
main() {
    while true; do
        show_menu
        read choice

        case $choice in
            1) query_1 ;;
            2) query_2 ;;
            3) query_3 ;;
            4) query_4 ;;
            5) query_5 ;;
            6) query_6 ;;
            7) query_7 ;;
            8) query_8 ;;
            9) query_9 ;;
            10) query_10 ;;
            11) query_11 ;;
            12) query_12 ;;
            13) query_13 ;;
            14) query_14 ;;
            15) query_15 ;;
            16) query_16 ;;
            17) query_17 ;;
            18) query_18 ;;
            19) query_19 ;;
            20) query_20 ;;
            21) query_21 ;;
            22) query_22 ;;
            23) query_23 ;;
            24) query_24 ;;
            0)
                show_header
                echo -e "${GREEN}Goodbye!${NC}"
                exit 0
                ;;
            *)
                show_header
                echo -e "${RED}Неверная команда!${NC}"
                wait_for_user
                ;;
        esac
    done
}

# Check if docker compose is running
if ! docker compose -f "$APP_DIR/docker-compose.yml" ps postgres | grep -q "Up"; then
    echo -e "${RED}Error: PostgreSQL container is not running!${NC}"
    echo -e "${YELLOW}Start it with: cd /srv/app && docker compose up -d${NC}"
    exit 1
fi

main
