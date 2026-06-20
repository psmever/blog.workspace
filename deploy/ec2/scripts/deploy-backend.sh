#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

trap 'trap_err "${LINENO}" "${BASH_COMMAND}" "$?"' ERR

usage() {
    cat <<'EOF'
사용법:
  ./deploy-backend.sh

예시:
  ./deploy-backend.sh
EOF
}

main() {
    local resolved_commit
    local deployed_at

    if [ $# -ne 0 ]; then
        usage
        exit 1
    fi

    init_logging "deploy-backend"
    acquire_deploy_lock
    require_commands git php composer curl sudo flock
    require_dir "$BLOG_BACKEND_DIR"
    require_file "$BLOG_BACKEND_DIR/.env"

    log "[backend 1/7] 배포 시작: ${BLOG_DEPLOY_BRANCH} <- ${BLOG_DEPLOY_SOURCE_BRANCH}"

    log "[backend 2/7] Laravel cache 생성 파일과 서버 작업 트리를 확인합니다."
    sanitize_laravel_cache_state "$BLOG_BACKEND_DIR"
    ensure_git_worktree_clean "$BLOG_BACKEND_DIR"
    promote_source_to_deploy_branch "backend" "$BLOG_BACKEND_DIR"
    resolved_commit=$BLOG_RESOLVED_COMMIT

    log "[backend 3/7] 배포 커밋 확인: $resolved_commit"

    cd "$BLOG_BACKEND_DIR"

    log "[backend 4/7] Composer 의존성 설치와 Laravel migration/cache 작업을 실행합니다."
    composer install --no-dev --prefer-dist --no-interaction --optimize-autoloader
    php artisan migrate --force
    php artisan optimize:clear
    php artisan config:cache
    php artisan route:cache

    log "[backend 5/7] blog-backend systemd 서비스를 재시작합니다."
    run_sudo systemctl restart blog-backend

    log "[backend 6/7] backend direct, nginx 헬스체크를 실행합니다."
    wait_for_http \
        "backend direct" \
        "$BLOG_BACKEND_HEALTH_URL" \
        -H "Client-Type: ${BLOG_CLIENT_TYPE}"

    wait_for_http \
        "backend nginx" \
        "$BLOG_BACKEND_PROXY_HEALTH_URL" \
        -H "Host: ${BLOG_PUBLIC_BACKEND_HOST}" \
        -H "Client-Type: ${BLOG_CLIENT_TYPE}"

    deployed_at=$(date -Iseconds)
    record_deploy_state "backend" "$BLOG_DEPLOY_BRANCH" "$resolved_commit" "$deployed_at"
    if [ "$BLOG_PROMOTION_HAS_CHANGES" = "1" ]; then
        create_and_push_deploy_tag "backend" "$BLOG_BACKEND_DIR" "$resolved_commit" "$deployed_at"
    else
        log "신규 승격 커밋이 없으므로 배포 태그 생성을 생략합니다."
    fi
    log "[backend 7/7] backend 배포 완료"
}

main "$@"
