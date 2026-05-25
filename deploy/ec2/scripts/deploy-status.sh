#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

trap 'trap_err "${LINENO}" "${BASH_COMMAND}" "$?"' ERR

print_row() {
    printf "%-18s %s\n" "$1" "$2"
}

read_state_value() {
    local state_file=$1
    local key=$2

    [ -f "$state_file" ] || return 1
    awk -F= -v key="$key" '$1 == key {print substr($0, index($0, "=") + 1); exit}' "$state_file"
}

http_status() {
    local url=$1
    shift || true

    local code=""
    code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 "$@" "$url" 2>/dev/null || true)

    if [ -n "$code" ] && [ "$code" != "000" ]; then
        printf '%s\n' "$code"
    else
        printf '%s\n' "unreachable"
    fi
}

backend_service_status() {
    systemctl is-active blog-backend 2>/dev/null || printf '%s\n' "unknown"
}

frontend_process_status() {
    export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
    export PM2_HOME="${PM2_HOME:-$HOME/.pm2}"

    if [ -s "$NVM_DIR/nvm.sh" ]; then
        # shellcheck disable=SC1090
        . "$NVM_DIR/nvm.sh"
    fi

    if ! command -v pm2 >/dev/null 2>&1; then
        printf '%s\n' "unavailable"
        return 0
    fi

    local pm2_pid=""
    pm2_pid=$(pm2 pid blog-frontend 2>/dev/null | tail -n 1 | tr -d '[:space:]' || true)

    if [[ "$pm2_pid" =~ ^[1-9][0-9]*$ ]]; then
        printf 'online(pid=%s)\n' "$pm2_pid"
    else
        printf '%s\n' "stopped"
    fi
}

print_component_status() {
    local component=$1
    local component_label=$2
    local process_status=$3
    local direct_health=$4
    local proxy_health=$5
    local state_file="${BLOG_STATE_DIR}/${component}.last_deploy"
    local requested_ref="(none)"
    local commit_sha="(none)"
    local deployed_at="(none)"

    if [ -f "$state_file" ]; then
        requested_ref=$(read_state_value "$state_file" requested_ref || printf '%s\n' "(unknown)")
        commit_sha=$(read_state_value "$state_file" commit_sha || printf '%s\n' "(unknown)")
        deployed_at=$(read_state_value "$state_file" deployed_at || printf '%s\n' "(unknown)")
    fi

    echo "[$component_label]"
    print_row "프로세스" "$process_status"
    print_row "direct health" "$direct_health"
    print_row "proxy health" "$proxy_health"
    print_row "deploy branch" "$requested_ref"
    print_row "commit sha" "$commit_sha"
    print_row "deployed at" "$deployed_at"
    echo
}

main() {
    print_component_status \
        "backend" \
        "backend" \
        "$(backend_service_status)" \
        "$(http_status "$BLOG_BACKEND_HEALTH_URL" -H "Client-Type: ${BLOG_CLIENT_TYPE}")" \
        "$(http_status "$BLOG_BACKEND_PROXY_HEALTH_URL" -H "Host: ${BLOG_PUBLIC_BACKEND_HOST}" -H "Client-Type: ${BLOG_CLIENT_TYPE}")"

    print_component_status \
        "frontend" \
        "frontend" \
        "$(frontend_process_status)" \
        "$(http_status "$BLOG_FRONTEND_HEALTH_URL")" \
        "$(http_status "$BLOG_FRONTEND_PROXY_HEALTH_URL" -H "Host: ${BLOG_PUBLIC_FRONTEND_HOST}")"
}

main "$@"
