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
  ./deploy-backend.sh --skip-git-sync

예시:
  ./deploy-backend.sh
  ./deploy-backend.sh --skip-git-sync
EOF
}

main() {
    local resolved_commit
    local skip_git_sync=0

    if [ $# -eq 1 ] && [ "$1" = "--skip-git-sync" ]; then
        skip_git_sync=1
    elif [ $# -ne 0 ]; then
        usage
        exit 1
    fi

    init_logging "deploy-backend"
    acquire_deploy_lock
    require_commands git php composer curl sudo flock
    require_dir "$BLOG_BACKEND_DIR"
    require_file "$BLOG_BACKEND_DIR/.env"

    log "[backend 1/7] 배포 시작: branch=${BLOG_DEPLOY_BRANCH} skip_git_sync=${skip_git_sync}"

    log "[backend 2/7] Laravel cache 생성 파일과 서버 작업 트리를 확인합니다."
    sanitize_laravel_cache_state "$BLOG_BACKEND_DIR"
    ensure_git_worktree_clean "$BLOG_BACKEND_DIR"
    if [ "$skip_git_sync" = "1" ]; then
        log "[Git 1/1] --skip-git-sync 요청: 서버 저장소 fetch, checkout, pull 을 생략합니다."
        resolved_commit=$(git -C "$BLOG_BACKEND_DIR" rev-parse HEAD)
    else
        log "[Git 1/1] origin/${BLOG_DEPLOY_BRANCH} 을 서버 저장소에 동기화합니다."
        resolved_commit=$(sync_repo_to_branch "$BLOG_BACKEND_DIR" "$BLOG_DEPLOY_BRANCH")
    fi

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

    record_deploy_state "backend" "$BLOG_DEPLOY_BRANCH" "$resolved_commit"
    log "[backend 7/7] backend 배포 완료"
}

main "$@"
