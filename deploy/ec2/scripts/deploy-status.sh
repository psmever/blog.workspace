#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

trap 'trap_err "${LINENO}" "${BASH_COMMAND}" "$?"' ERR

usage() {
    cat <<'EOF'
사용법:
  ./deploy-status.sh
  ./deploy-status.sh --component <backend|frontend>
  ./deploy-status.sh --component <backend|frontend> --format env

옵션:
  --component   backend 또는 frontend
  --format      human(기본값) 또는 env
  -h, --help    도움말 출력
EOF
}

die_usage() {
    usage >&2
    exit 1
}

print_row() {
    printf "%-18s %s\n" "$1" "$2"
}

read_state_value() {
    local state_file=$1
    local key=$2

    [ -f "$state_file" ] || return 1
    awk -F= -v key="$key" '$1 == key {print substr($0, index($0, "=") + 1); exit}' "$state_file"
}

read_component_state() {
    local component=$1
    local state_file="${BLOG_STATE_DIR}/${component}.last_deploy"

    STATE_DEPLOY_BRANCH="(none)"
    STATE_COMMIT_SHA="(none)"
    STATE_DEPLOYED_AT="(none)"

    if [ -f "$state_file" ]; then
        STATE_DEPLOY_BRANCH=$(read_state_value "$state_file" deploy_branch || printf '%s\n' "")
        if [ -z "$STATE_DEPLOY_BRANCH" ]; then
            STATE_DEPLOY_BRANCH=$(read_state_value "$state_file" requested_ref || printf '%s\n' "(unknown)")
        fi

        STATE_COMMIT_SHA=$(read_state_value "$state_file" commit_sha || printf '%s\n' "(unknown)")
        STATE_DEPLOYED_AT=$(read_state_value "$state_file" deployed_at || printf '%s\n' "(unknown)")
    fi
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

    read_component_state "$component"

    echo "[$component_label]"
    print_row "프로세스" "$process_status"
    print_row "direct health" "$direct_health"
    print_row "proxy health" "$proxy_health"
    print_row "deploy branch" "$STATE_DEPLOY_BRANCH"
    print_row "commit sha" "$STATE_COMMIT_SHA"
    print_row "deployed at" "$STATE_DEPLOYED_AT"
    echo
}

print_component_env() {
    local component=$1

    read_component_state "$component"

    [ "$STATE_DEPLOY_BRANCH" != "(none)" ] || die "배포 상태 파일이 없습니다: ${BLOG_STATE_DIR}/${component}.last_deploy"
    [ "$STATE_COMMIT_SHA" != "(none)" ] || die "배포 커밋 정보를 찾을 수 없습니다: $component"
    [ "$STATE_DEPLOYED_AT" != "(none)" ] || die "배포 시각 정보를 찾을 수 없습니다: $component"

    printf 'component=%s\n' "$component"
    printf 'deploy_branch=%s\n' "$STATE_DEPLOY_BRANCH"
    printf 'commit_sha=%s\n' "$STATE_COMMIT_SHA"
    printf 'deployed_at=%s\n' "$STATE_DEPLOYED_AT"
}

main() {
    local component="all"
    local format="human"

    while [ $# -gt 0 ]; do
        case "$1" in
            --component)
                [ $# -ge 2 ] || die_usage
                component=$2
                shift 2
                ;;
            --format)
                [ $# -ge 2 ] || die_usage
                format=$2
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo "알 수 없는 옵션: $1" >&2
                die_usage
                ;;
        esac
    done

    case "$component" in
        all|backend|frontend)
            ;;
        *)
            die "지원하지 않는 component입니다: $component"
            ;;
    esac

    case "$format" in
        human)
            ;;
        env)
            [ "$component" != "all" ] || die "--format env 는 --component 와 함께 사용해야 합니다."
            print_component_env "$component"
            exit 0
            ;;
        *)
            die "지원하지 않는 format입니다: $format"
            ;;
    esac

    if [ "$component" = "all" ] || [ "$component" = "backend" ]; then
        print_component_status \
            "backend" \
            "backend" \
            "$(backend_service_status)" \
            "$(http_status "$BLOG_BACKEND_HEALTH_URL" -H "Client-Type: ${BLOG_CLIENT_TYPE}")" \
            "$(http_status "$BLOG_BACKEND_PROXY_HEALTH_URL" -H "Host: ${BLOG_PUBLIC_BACKEND_HOST}" -H "Client-Type: ${BLOG_CLIENT_TYPE}")"
    fi

    if [ "$component" = "all" ] || [ "$component" = "frontend" ]; then
        print_component_status \
            "frontend" \
            "frontend" \
            "$(frontend_process_status)" \
            "$(http_status "$BLOG_FRONTEND_HEALTH_URL")" \
            "$(http_status "$BLOG_FRONTEND_PROXY_HEALTH_URL" -H "Host: ${BLOG_PUBLIC_FRONTEND_HOST}")"
    fi
}

main "$@"
