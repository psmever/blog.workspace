#!/usr/bin/env bash
set -Eeuo pipefail

SSH_HOST=${BLOG_DB_TUNNEL_HOST:-jaubi-prod-app}
LOCAL_HOST=${BLOG_DB_LOCAL_HOST:-127.0.0.1}
LOCAL_PORT=${BLOG_DB_LOCAL_PORT:-23306}
REMOTE_HOST=${BLOG_DB_REMOTE_HOST:-127.0.0.1}
REMOTE_PORT=${BLOG_DB_REMOTE_PORT:-3306}
DB_NAME=${BLOG_DB_NAME:-blog}
DB_USER=${BLOG_DB_USER:-ops_reader}
TUNNEL_NAME=${BLOG_DB_TUNNEL_NAME:-jaubi-prod-db}
STATE_DIR=${BLOG_DB_TUNNEL_STATE_DIR:-${HOME}/.ssh_tunnels}
PID_FILE="${STATE_DIR}/${TUNNEL_NAME}.pid"
LOG_FILE="${STATE_DIR}/${TUNNEL_NAME}.log"

usage() {
    cat <<EOF
사용법:
  ./scripts/db-tunnel-prod.sh start [--foreground] [--restart]
  ./scripts/db-tunnel-prod.sh stop
  ./scripts/db-tunnel-prod.sh status

설명:
  SSH 별칭 ${SSH_HOST} 를 통해 로컬 ${LOCAL_HOST}:${LOCAL_PORT} 를
  원격 ${REMOTE_HOST}:${REMOTE_PORT} 에 연결합니다.
  start 는 기본적으로 백그라운드로 실행하고 PID 파일과 로그를 남깁니다.

환경변수:
  BLOG_DB_TUNNEL_HOST       SSH 별칭 또는 호스트명 (기본값: ${SSH_HOST})
  BLOG_DB_LOCAL_HOST        로컬 바인드 호스트 (기본값: ${LOCAL_HOST})
  BLOG_DB_LOCAL_PORT        로컬 바인드 포트 (기본값: ${LOCAL_PORT})
  BLOG_DB_REMOTE_HOST       원격 DB 호스트 (기본값: ${REMOTE_HOST})
  BLOG_DB_REMOTE_PORT       원격 DB 포트 (기본값: ${REMOTE_PORT})
  BLOG_DB_NAME              접속 대상 DB 이름 안내용 (기본값: ${DB_NAME})
  BLOG_DB_USER              접속 대상 DB 사용자 안내용 (기본값: ${DB_USER})
  BLOG_DB_TUNNEL_NAME       상태 파일 이름 접두사 (기본값: ${TUNNEL_NAME})
  BLOG_DB_TUNNEL_STATE_DIR  PID/로그 저장 경로 (기본값: ${STATE_DIR})

옵션:
  --foreground   포그라운드 실행
  --restart      실행 중이면 재시작
  -h, --help     도움말 출력

예시:
  ./scripts/db-tunnel-prod.sh start
  ./scripts/db-tunnel-prod.sh start --restart
  ./scripts/db-tunnel-prod.sh status
  ./scripts/db-tunnel-prod.sh stop
  BLOG_DB_LOCAL_PORT=33306 ./scripts/db-tunnel-prod.sh start

접속 예시:
  mariadb -h ${LOCAL_HOST} -P ${LOCAL_PORT} -u ${DB_USER} -p ${DB_NAME}
EOF
}

ensure_state_dir() {
    mkdir -p "$STATE_DIR"
}

is_pid_alive() {
    local pid=${1:-}
    [ -n "$pid" ] && kill -0 "$pid" >/dev/null 2>&1
}

read_pid() {
    [ -f "$PID_FILE" ] || return 1
    tr -d '[:space:]' < "$PID_FILE"
}

port_in_use() {
    local port=$1

    if command -v lsof >/dev/null 2>&1; then
        lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
        return
    fi

    if command -v nc >/dev/null 2>&1; then
        nc -z "$LOCAL_HOST" "$port" >/dev/null 2>&1
        return
    fi

    return 1
}

cleanup_stale_pid() {
    local pid=""
    pid=$(read_pid 2>/dev/null || true)

    if [ -n "$pid" ] && ! is_pid_alive "$pid"; then
        rm -f "$PID_FILE"
    fi
}

print_connection_hint() {
    echo "접속 예시:"
    echo "  mariadb -h ${LOCAL_HOST} -P ${LOCAL_PORT} -u ${DB_USER} -p ${DB_NAME}"
}

cmd_status() {
    ensure_state_dir
    cleanup_stale_pid

    local pid="(none)"
    local pid_status="stopped"
    local listen="no"

    if [ -f "$PID_FILE" ]; then
        pid=$(read_pid 2>/dev/null || true)
        if [ -n "$pid" ] && is_pid_alive "$pid"; then
            pid_status="running"
        else
            pid_status="stale"
        fi
    fi

    if port_in_use "$LOCAL_PORT"; then
        listen="yes"
    fi

    printf "%-18s %s\n" "이름" "$TUNNEL_NAME"
    printf "%-18s %s\n" "SSH 호스트" "$SSH_HOST"
    printf "%-18s %s:%s\n" "로컬 바인드" "$LOCAL_HOST" "$LOCAL_PORT"
    printf "%-18s %s:%s\n" "원격 대상" "$REMOTE_HOST" "$REMOTE_PORT"
    printf "%-18s %s\n" "PID 상태" "$pid_status"
    printf "%-18s %s\n" "PID" "$pid"
    printf "%-18s %s\n" "포트 리슨" "$listen"
    printf "%-18s %s\n" "PID 파일" "$PID_FILE"
    printf "%-18s %s\n" "로그 파일" "$LOG_FILE"
    print_connection_hint
}

cmd_stop() {
    ensure_state_dir
    cleanup_stale_pid

    local pid=""
    pid=$(read_pid 2>/dev/null || true)

    if [ -z "$pid" ]; then
        echo "실행 중인 터널이 없습니다."
        return 0
    fi

    if ! is_pid_alive "$pid"; then
        rm -f "$PID_FILE"
        echo "stale PID 파일을 정리했습니다."
        return 0
    fi

    echo "터널 종료 중... PID=${pid}"
    kill "$pid" >/dev/null 2>&1 || true

    for _ in $(seq 1 30); do
        if ! is_pid_alive "$pid"; then
            break
        fi
        sleep 0.1
    done

    if is_pid_alive "$pid"; then
        kill -9 "$pid" >/dev/null 2>&1 || true
    fi

    rm -f "$PID_FILE"
    echo "터널을 종료했습니다."
}

cmd_start() {
    ensure_state_dir

    local foreground=false
    local restart=false
    local pid=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --foreground)
                foreground=true
                ;;
            --restart)
                restart=true
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo "알 수 없는 옵션: $1" >&2
                usage
                exit 1
                ;;
        esac
        shift
    done

    cleanup_stale_pid
    pid=$(read_pid 2>/dev/null || true)

    if [ -n "$pid" ] && is_pid_alive "$pid"; then
        if [ "$restart" = true ]; then
            cmd_stop
        else
            echo "이미 실행 중입니다. PID=${pid}"
            cmd_status
            exit 0
        fi
    fi

    if port_in_use "$LOCAL_PORT"; then
        echo "로컬 포트 ${LOCAL_PORT} 가 이미 사용 중입니다." >&2
        echo "다른 포트를 쓰려면 BLOG_DB_LOCAL_PORT 를 지정하세요." >&2
        exit 1
    fi

    local ssh_opts=(
        -N
        -L "${LOCAL_HOST}:${LOCAL_PORT}:${REMOTE_HOST}:${REMOTE_PORT}"
        -o ExitOnForwardFailure=yes
        -o ServerAliveInterval=15
        -o ServerAliveCountMax=3
    )

    echo "SSH 터널 시작: ${LOCAL_HOST}:${LOCAL_PORT} -> ${SSH_HOST}:${REMOTE_HOST}:${REMOTE_PORT}"
    print_connection_hint

    if [ "$foreground" = true ]; then
        echo "포그라운드로 실행합니다. 종료는 Ctrl+C 를 사용하세요."
        exec ssh "${ssh_opts[@]}" "$SSH_HOST"
    fi

    : > "$LOG_FILE"
    ssh "${ssh_opts[@]}" "$SSH_HOST" >>"$LOG_FILE" 2>&1 &
    pid=$!
    echo "$pid" > "$PID_FILE"
    sleep 0.3

    if ! is_pid_alive "$pid"; then
        rm -f "$PID_FILE"
        echo "터널 시작에 실패했습니다. 로그를 확인하세요: $LOG_FILE" >&2
        exit 1
    fi

    echo "터널이 백그라운드에서 실행 중입니다. PID=${pid}"
    echo "로그 파일: $LOG_FILE"
}

main() {
    local command=${1:-}
    shift || true

    case "$command" in
        start)
            cmd_start "$@"
            ;;
        stop)
            cmd_stop
            ;;
        status)
            cmd_status
            ;;
        -h|--help|"")
            usage
            ;;
        *)
            echo "알 수 없는 명령: $command" >&2
            usage
            exit 1
            ;;
    esac
}

main "$@"
