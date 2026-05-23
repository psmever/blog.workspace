#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

trap 'trap_err "${LINENO}" "${BASH_COMMAND}" "$?"' ERR

usage() {
    cat <<'EOF'
사용법:
  ./deploy-backend.sh <tag-or-sha>

예시:
  ./deploy-backend.sh v2026.05.21-1
  ./deploy-backend.sh 8f42ab1
EOF
}

main() {
    local requested_ref=${1:-}
    local resolved_commit

    [ -n "$requested_ref" ] || {
        usage
        exit 1
    }

    init_logging "deploy-backend"
    acquire_deploy_lock
    require_commands git php composer curl sudo flock
    require_dir "$BLOG_BACKEND_DIR"
    require_file "$BLOG_BACKEND_DIR/.env"

    log "backend 배포 시작: ref=$requested_ref"

    sanitize_laravel_cache_state "$BLOG_BACKEND_DIR"
    ensure_git_worktree_clean "$BLOG_BACKEND_DIR"
    fetch_origin "$BLOG_BACKEND_DIR"
    resolved_commit=$(resolve_ref "$BLOG_BACKEND_DIR" "$requested_ref")

    log "배포 커밋: $resolved_commit"
    checkout_commit "$BLOG_BACKEND_DIR" "$resolved_commit"

    cd "$BLOG_BACKEND_DIR"

    composer install --no-dev --prefer-dist --no-interaction --optimize-autoloader
    php artisan migrate --force
    php artisan optimize:clear
    php artisan config:cache
    php artisan route:cache

    run_sudo systemctl restart blog-backend

    wait_for_http \
        "backend direct" \
        "$BLOG_BACKEND_HEALTH_URL" \
        -H "Client-Type: ${BLOG_CLIENT_TYPE}"

    wait_for_http \
        "backend nginx" \
        "$BLOG_BACKEND_PROXY_HEALTH_URL" \
        -H "Host: ${BLOG_PUBLIC_BACKEND_HOST}" \
        -H "Client-Type: ${BLOG_CLIENT_TYPE}"

    record_deploy_state "backend" "$requested_ref" "$resolved_commit"
    log "backend 배포 완료"
}

main "$@"
