#!/bin/bash

# Скрипт для анализа дискового пространства Docker
# Включает анализ логов и volumes

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Функция для вывода справки
show_help() {
    echo "Использование: $0 [ОПЦИИ]"
    echo ""
    echo "Опции:"
    echo "  -h, --help      Показать эту справку"
    echo "  -a, --all       Показать все контейнеры (включая остановленные)"
    echo "  -l, --limit N   Показать топ N контейнеров (по умолчанию: 10)"
    echo "  --logs-only     Только анализ логов"
    echo "  --volumes-only  Только анализ volumes"
    echo ""
    echo "Примеры:"
    echo "  $0                    # Полный анализ (логи + volumes)"
    echo "  $0 -l 5              # Топ-5 в каждой категории"
    echo "  $0 --logs-only       # Только анализ логов"
}

# Функция для конвертации байтов в человеко-читаемый формат
human_readable() {
    local bytes=$1
    if command -v numfmt >/dev/null 2>&1; then
        numfmt --to=iec --suffix=B $bytes
    else
        if [ $bytes -ge 1073741824 ]; then
            echo "$(echo "scale=2; $bytes/1073741824" | bc)GB"
        elif [ $bytes -ge 1048576 ]; then
            echo "$(echo "scale=2; $bytes/1048576" | bc)MB"
        elif [ $bytes -ge 1024 ]; then
            echo "$(echo "scale=2; $bytes/1024" | bc)KB"
        else
            echo "${bytes}B"
        fi
    fi
}

# Функция для получения пути к логам
get_log_path() {
    local container=$1
    docker inspect --format='{{.LogPath}}' "$container" 2>/dev/null
}

# Функция для анализа логов контейнера
analyze_container_logs() {
    local container=$1
    
    echo "Анализ контейнера: $container" >&2
    
    # Получаем базовую информацию
    local name=$(docker inspect --format='{{.Name}}' "$container" 2>/dev/null | sed 's|/||')
    local image=$(docker inspect --format='{{.Config.Image}}' "$container" 2>/dev/null)
    local status=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null)
    
    # Получаем путь к логам
    local log_path=$(get_log_path "$container")
    
    local log_size=0
    local log_entries=0
    local log_driver="unknown"
    
    if [ -n "$log_path" ] && [ "$log_path" != "null" ] && [ "$log_path" != "<no value>" ]; then
        if [ -f "$log_path" ]; then
            # Получаем размер лога
            log_size=$(stat -c%s "$log_path" 2>/dev/null || echo "0")
            # Получаем количество записей
            log_entries=$(wc -l < "$log_path" 2>/dev/null || echo "0")
            # Получаем драйвер логирования
            log_driver=$(docker inspect --format='{{.HostConfig.LogConfig.Type}}' "$container" 2>/dev/null || echo "json-file")
        fi
    fi
    
    # Выводим результат в формате для сортировки
    echo "$log_size $log_driver $log_entries $log_path $name $image $status $container"
}

# Функция для анализа volumes
analyze_docker_volumes() {
    echo "Анализ volumes..." >&2
    local volumes_file=$(mktemp)
    
    docker volume ls -q 2>/dev/null | while read volume; do
        local volume_info=$(docker volume inspect "$volume" 2>/dev/null)
        if [ -n "$volume_info" ]; then
            local mountpoint=$(echo "$volume_info" | grep -o '"Mountpoint":"[^"]*"' | cut -d'"' -f4)
            if [ -n "$mountpoint" ] && [ -d "$mountpoint" ]; then
                local size=$(du -sb "$mountpoint" 2>/dev/null | cut -f1)
                local driver=$(echo "$volume_info" | grep -o '"Driver":"[^"]*"' | cut -d'"' -f4)
                echo "$size $volume $driver $mountpoint"
            fi
        fi
    done > "$volumes_file"
    
    echo "$volumes_file"
}

# Основная функция
main() {
    # Парсинг аргументов
    local SHOW_ALL=false
    local LIMIT=10
    local LOGS_ONLY=false
    local VOLUMES_ONLY=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -a|--all)
                SHOW_ALL=true
                shift
                ;;
            -l|--limit)
                LIMIT="$2"
                shift 2
                ;;
            --logs-only)
                LOGS_ONLY=true
                shift
                ;;
            --volumes-only)
                VOLUMES_ONLY=true
                shift
                ;;
            *)
                echo "Неизвестный параметр: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Проверка Docker
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}Ошибка: docker не установлен${NC}"
        exit 1
    fi

    if ! docker info >/dev/null 2>&1; then
        echo -e "${RED}Ошибка: Docker daemon не доступен${NC}"
        exit 1
    fi

    echo -e "${BLUE}Анализ дискового пространства Docker...${NC}"
    echo ""

    # Анализ контейнеров
    if [ "$VOLUMES_ONLY" = false ]; then
        echo -e "${PURPLE}ТАБЛИЦА 1: Логи контейнеров${NC}"
        echo "=================================================================================================="
        
        # Получаем список контейнеров
        if [ "$SHOW_ALL" = true ]; then
            CONTAINERS=$(docker ps -aq)
        else
            CONTAINERS=$(docker ps -q)
        fi
        
        if [ -z "$CONTAINERS" ]; then
            echo "Контейнеры не найдены"
        else
            # Создаем временный файл для результатов
            local temp_file=$(mktemp)
            
            # Анализируем каждый контейнер
            for container in $CONTAINERS; do
                analyze_container_logs "$container" >> "$temp_file"
            done
            
            # Выводим таблицу логов
            echo "ИМЯ КОНТЕЙНЕРА          ОБРАЗ               РАЗМЕР ЛОГОВ   ЗАПИСИ   ДРАЙВЕР"
            echo "--------------------------------------------------------------------------------------------------"
            
            sort -nr "$temp_file" | head -n "$LIMIT" | while read line; do
                local log_size=$(echo "$line" | awk '{print $1}')
                local log_driver=$(echo "$line" | awk '{print $2}')
                local log_entries=$(echo "$line" | awk '{print $3}')
                local log_path=$(echo "$line" | awk '{print $4}')
                local name=$(echo "$line" | awk '{print $5}')
                local image=$(echo "$line" | awk '{print $6}')
                local status=$(echo "$line" | awk '{print $7}')
                local container_id=$(echo "$line" | awk '{print $8}')
                
                local human_size=$(human_readable $log_size)
                
                printf "%-20s %-20s %-12s %-8s %-10s\n" \
                    "${name:0:19}" \
                    "${image:0:19}" \
                    "$human_size" \
                    "$log_entries" \
                    "${log_driver:0:9}"
            done
            
            echo "=================================================================================================="
            
            # Таблица путей к логам (топ 5)
            echo ""
            echo -e "${CYAN}ПУТИ К ЛОГАМ (топ 5):${NC}"
            echo "=================================================="
            
            sort -nr "$temp_file" | head -n 5 | while read line; do
                local name=$(echo "$line" | awk '{print $5}')
                local log_path=$(echo "$line" | awk '{print $4}')
                
                if [ "$log_path" != "unknown" ] && [ -n "$log_path" ]; then
                    echo "Контейнер: $name"
                    echo "Путь: $log_path"
                    echo "--------------------------------------------------"
                fi
            done
            
            # Очистка
            rm -f "$temp_file"
        fi
        
        echo ""
    fi

    # Анализ volumes
    if [ "$LOGS_ONLY" = false ]; then
        echo -e "${BLUE}ТАБЛИЦА 2: Docker Volumes${NC}"
        echo "=================================================================================="
        
        local volumes_file=$(analyze_docker_volumes)
        
        if [ -s "$volumes_file" ]; then
            echo "VOLUME               РАЗМЕР         ДРАЙВЕР"
            echo "----------------------------------------------------------------------------------"
            
            sort -nr "$volumes_file" | head -n "$LIMIT" | while read line; do
                local size=$(echo "$line" | awk '{print $1}')
                local volume=$(echo "$line" | awk '{print $2}')
                local driver=$(echo "$line" | awk '{print $3}')
                local mountpoint=$(echo "$line" | awk '{print $4}')
                
                local human_size=$(human_readable $size)
                
                printf "%-20s %-12s %-10s\n" \
                    "${volume:0:19}" \
                    "$human_size" \
                    "${driver:0:9}"
            done
            
            echo "=================================================================================="
            
            # Пути к volumes
            echo ""
            echo -e "${CYAN}ПУТИ К VOLUMES (топ 5):${NC}"
            echo "=================================================="
            
            sort -nr "$volumes_file" | head -n 5 | while read line; do
                local volume=$(echo "$line" | awk '{print $2}')
                local mountpoint=$(echo "$line" | awk '{print $4}')
                
                echo "Volume: $volume"
                echo "Путь: $mountpoint"
                echo "--------------------------------------------------"
            done
        else
            echo "Volumes не найдены"
        fi
        
        # Очистка
        if [ -f "$volumes_file" ]; then
            rm -f "$volumes_file"
        fi
        
        echo ""
    fi

    # Общая статистика
    echo -e "${GREEN}ОБЩАЯ СТАТИСТИКА DOCKER:${NC}"
    docker system df
    echo ""
    
    echo -e "${GREEN}АНАЛИЗ ЗАВЕРШЕН${NC}"
}

# Запуск главной функции
main "$@"
