#!/bin/bash

# Анализ логов контейнеров и всех Docker volumes. Linux, Bash 4+.
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

show_help() {
    echo "Использование: $0 [ОПЦИИ]"
    echo "  -h, --help      Показать справку"
    echo "  -a, --all       Включить остановленные контейнеры в анализ логов"
    echo "  -l, --limit N   Топ N контейнеров по размеру логов (по умолчанию: 10)"
    echo "  --logs-only     Только анализ логов"
    echo "  --volumes-only  Только анализ volumes"
    echo "Volumes всегда выводятся все, независимо от --all и --limit."
    echo "ACTIVE: есть работающий контейнер; INACTIVE: только остановленные; UNUSED: нет контейнеров."
    echo "Размер измеряется на Docker-хосте через du; недоступный размер обозначается N/A."
}

human_readable() {
    if command -v numfmt >/dev/null 2>&1; then
        numfmt --to=iec --suffix=B "$1"
    else
        awk -v b="$1" 'BEGIN {
            split("B KiB MiB GiB TiB PiB EiB", u, " ");
            i=1; while (b>=1024 && i<7) { b/=1024; i++ }
            printf "%.2f%s\n", b, u[i]
        }'
    fi
}

analyze_container_logs() {
    local container=$1 info name image driver log_path size=0 entries=0
    echo "Анализ контейнера: $container" >&2
    info=$(docker inspect --format '{{printf "%s\t%s\t%s\t%s" .Name .Config.Image .HostConfig.LogConfig.Type .LogPath}}' "$container") || return 1
    IFS=$'\t' read -r name image driver log_path <<< "$info"
    name=${name#/}
    log_path=${log_path:--}
    driver=${driver:-unknown}
    if [[ -f "$log_path" && -r "$log_path" ]]; then
        size=$(stat -c%s -- "$log_path" 2>/dev/null) || size=0
        entries=$(wc -l < "$log_path" 2>/dev/null) || entries=0
        entries=${entries//[[:space:]]/}
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$size" "$name" "$image" "$entries" "$driver" "$log_path"
}

report_container_logs() (
    local show_all=$1 limit=$2 ids id rows size name image entries driver log_path
    rows=$(mktemp) || return 1
    trap 'rm -f -- "$rows"' EXIT
    if [[ "$show_all" == true ]]; then
        ids=$(docker ps -aq) || return 1
    else
        ids=$(docker ps -q) || return 1
    fi
    if [[ -z "$ids" ]]; then
        echo "Контейнеры не найдены"
        return 0
    fi
    while IFS= read -r id; do
        [[ -n "$id" ]] || continue
        analyze_container_logs "$id" >> "$rows" || return 1
    done <<< "$ids"
    printf '%-30s %-30s %-12s %-12s %s\n' "CONTAINER" "IMAGE" "LOG SIZE" "ENTRIES" "DRIVER"
    while IFS=$'\t' read -r size name image entries driver log_path; do
        printf '%-30s %-30s %-12s %-12s %s\n' "$name" "$image" "$(human_readable "$size")" "$entries" "$driver"
    done < <(sort -t $'\t' -k1,1nr "$rows" | head -n "$limit")
    echo
    echo -e "${CYAN}ПУТИ К ЛОГАМ (топ 5):${NC}"
    while IFS=$'\t' read -r size name image entries driver log_path; do
        [[ "$log_path" == '-' ]] || printf '%s: %s\n' "$name" "$log_path"
    done < <(sort -t $'\t' -k1,1nr "$rows" | head -n 5)
)

analyze_docker_volumes() (
    local volumes ids id data volume name running info driver mountpoint usage size status rows human
    local total=0 unknown=0 active=0 inactive=0 unused=0
    declare -A containers=() running_volumes=()
    volumes=$(docker volume ls -q) || return 1
    if [[ -z "$volumes" ]]; then
        echo "Volumes не найдены"
        return 0
    fi
    ids=$(docker ps -aq) || return 1
    while IFS= read -r id; do
        [[ -n "$id" ]] || continue
        data=$(docker inspect --format '{{range .Mounts}}{{if eq .Type "volume"}}{{printf "%s\t%s\t%t\n" .Name $.Name $.State.Running}}{{end}}{{end}}' "$id") || {
            echo "Ошибка проверки контейнера $id. Повторите анализ." >&2
            return 1
        }
        while IFS=$'\t' read -r volume name running; do
            [[ -n "$volume" ]] || continue
            name=${name#/}
            containers["$volume"]="${containers[$volume]:+${containers[$volume]}, }$name"
            [[ "$running" != true ]] || running_volumes["$volume"]=1
        done <<< "$data"
    done <<< "$ids"
    rows=$(mktemp) || return 1
    trap 'rm -f -- "$rows"' EXIT
    echo "Анализ всех volumes (измерение размера может занять время)..." >&2
    while IFS= read -r volume; do
        [[ -n "$volume" ]] || continue
        if [[ ${running_volumes[$volume]:-0} == 1 ]]; then
            status=ACTIVE
            active=$((active + 1))
        elif [[ -n ${containers[$volume]:-} ]]; then
            status=INACTIVE
            inactive=$((inactive + 1))
        else
            status=UNUSED
            unused=$((unused + 1))
        fi
        driver='-'
        mountpoint='-'
        size=-1
        if info=$(docker volume inspect --format '{{printf "%s\t%s" .Driver .Mountpoint}}' "$volume"); then
            IFS=$'\t' read -r driver mountpoint <<< "$info"
            if [[ -n "$mountpoint" && -d "$mountpoint" ]] && usage=$(du -s -B1 -- "$mountpoint" 2>/dev/null); then
                size=${usage%%$'\t'*}
                [[ "$size" =~ ^[0-9]+$ ]] || size=-1
            fi
        fi
        if (( size >= 0 )); then
            total=$((total + size))
        else
            unknown=$((unknown + 1))
        fi
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$size" "$volume" "$status" "${driver:--}" "${containers[$volume]:--}" "${mountpoint:--}" >> "$rows"
    done <<< "$volumes"
    printf '%-40s %-10s %-12s %-12s %s\n' "VOLUME" "STATUS" "DISK SIZE" "DRIVER" "CONTAINERS"
    while IFS=$'\t' read -r size volume status driver name mountpoint; do
        human=N/A
        if (( size >= 0 )); then human=$(human_readable "$size"); fi
        printf '%-40s %-10s %-12s %-12s %s\n' "$volume" "$status" "$human" "$driver" "$name"
    done < <(sort -t $'\t' -k1,1nr "$rows")
    printf '\nACTIVE: %s | INACTIVE: %s | UNUSED: %s\n' "$active" "$inactive" "$unused"
    printf 'Суммарный измеренный размер: %s\n' "$(human_readable "$total")
"
    if (( unknown > 0 )); then
        printf 'Размер недоступен для %s volumes; они не включены в сумму.\n' "$unknown"
    fi
    echo
    echo -e "${CYAN}ПУТИ К VOLUMES (все):${NC}"
    while IFS=$'\t' read -r size volume status driver name mountpoint; do
        printf '%s: %s\n' "$volume" "$mountpoint"
    done < <(sort -t $'\t' -k1,1nr "$rows")
)

main() {
    local show_all=false limit=10 logs_only=false volumes_only=false
    while (( $# )); do
        case $1 in
            -h|--help) show_help; return 0 ;;
            -a|--all) show_all=true; shift ;;
            -l|--limit)
                if [[ $# -lt 2 || ! "$2" =~ ^[1-9][0-9]*$ ]]; then
                    echo "Ошибка: --limit требует положительное целое число" >&2
                    return 1
                fi
                limit=$2; shift 2 ;;
            --logs-only) logs_only=true; shift ;;
            --volumes-only) volumes_only=true; shift ;;
            *) echo "Неизвестный параметр: $1" >&2; show_help; return 1 ;;
        esac
    done
    if (( BASH_VERSINFO[0] < 4 )); then
        echo "Ошибка: требуется Bash 4 или новее" >&2; return 1
    fi
    if [[ "$logs_only" == true && "$volumes_only" == true ]]; then
        echo "Ошибка: --logs-only и --volumes-only несовместимы" >&2; return 1
    fi
    command -v docker >/dev/null 2>&1 || { echo "Ошибка: docker не установлен" >&2; return 1; }
    docker info >/dev/null 2>&1 || { echo "Ошибка: Docker daemon недоступен" >&2; return 1; }
    echo -e "${BLUE}Анализ дискового пространства Docker...${NC}"
    if [[ "$volumes_only" == false ]]; then
        echo -e "${PURPLE}ТАБЛИЦА 1: Логи контейнеров${NC}"
        report_container_logs "$show_all" "$limit" || return 1
        echo
    fi
    if [[ "$logs_only" == false ]]; then
        echo -e "${BLUE}ТАБЛИЦА 2: Docker Volumes${NC}"
        analyze_docker_volumes || return 1
        echo
    fi
    echo -e "${GREEN}ОБЩАЯ СТАТИСТИКА DOCKER:${NC}"
    docker system df || return 1
    echo -e "${GREEN}АНАЛИЗ ЗАВЕРШЕН${NC}"
}

main "$@"
