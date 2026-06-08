#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

trap 'trap_err "${LINENO}" "${BASH_COMMAND}" "$?"' ERR

usage() {
    cat <<'EOF'
사용법:
  ./deploy-frontend.sh
  ./deploy-frontend.sh --skip-git-sync

예시:
  ./deploy-frontend.sh
  ./deploy-frontend.sh --skip-git-sync
EOF
}

restart_frontend() {
    if pm2 describe blog-frontend >/dev/null 2>&1; then
        pm2 restart blog-frontend --update-env
    else
        pm2 start ecosystem.config.cjs --only blog-frontend
    fi

    pm2 save >/dev/null
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

    init_logging "deploy-frontend"
    acquire_deploy_lock
    require_commands git curl flock
    load_node_toolchain
    require_dir "$BLOG_FRONTEND_DIR"
    require_file "$BLOG_FRONTEND_DIR/.env"
    require_file "$BLOG_FRONTEND_DIR/ecosystem.config.cjs"

    log "[frontend 1/7] 배포 시작: branch=${BLOG_DEPLOY_BRANCH} skip_git_sync=${skip_git_sync}"

    log "[frontend 2/7] 서버 작업 트리를 확인합니다."
    ensure_git_worktree_clean "$BLOG_FRONTEND_DIR"
    if [ "$skip_git_sync" = "1" ]; then
        log "[Git 1/1] --skip-git-sync 요청: 서버 저장소 fetch, checkout, pull 을 생략합니다."
        resolved_commit=$(git -C "$BLOG_FRONTEND_DIR" rev-parse HEAD)
    else
        log "[Git 1/1] origin/${BLOG_DEPLOY_BRANCH} 을 서버 저장소에 동기화합니다."
        resolved_commit=$(sync_repo_to_branch "$BLOG_FRONTEND_DIR" "$BLOG_DEPLOY_BRANCH")
    fi

    log "[frontend 3/7] 배포 커밋 확인: $resolved_commit"

    cd "$BLOG_FRONTEND_DIR"

    log "[frontend 4/8] 기존 Next.js 빌드 산출물을 정리합니다."
    rm -rf .next

    log "[frontend 5/8] Yarn 의존성 설치와 프로덕션 빌드를 실행합니다."
    run_yarn install --immutable
    run_yarn build
    log "[frontend 6/8] blog-frontend PM2 프로세스를 재시작합니다."
    restart_frontend

    log "[frontend 7/8] frontend direct, nginx 헬스체크를 실행합니다."
    wait_for_http "frontend direct" "$BLOG_FRONTEND_HEALTH_URL"
    wait_for_http \
        "frontend nginx" \
        "$BLOG_FRONTEND_PROXY_HEALTH_URL" \
        -H "Host: ${BLOG_PUBLIC_FRONTEND_HOST}"

    record_deploy_state "frontend" "$BLOG_DEPLOY_BRANCH" "$resolved_commit"
    log "[frontend 8/8] frontend 배포 완료"
}

main "$@"
