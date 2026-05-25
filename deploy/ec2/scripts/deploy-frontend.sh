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

예시:
  ./deploy-frontend.sh
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

    [ $# -eq 0 ] || {
        usage
        exit 1
    }

    init_logging "deploy-frontend"
    acquire_deploy_lock
    require_commands git curl flock
    load_node_toolchain
    require_dir "$BLOG_FRONTEND_DIR"
    require_file "$BLOG_FRONTEND_DIR/.env"
    require_file "$BLOG_FRONTEND_DIR/ecosystem.config.cjs"

    log "frontend 배포 시작: branch=${BLOG_DEPLOY_BRANCH}"

    ensure_git_worktree_clean "$BLOG_FRONTEND_DIR"
    resolved_commit=$(sync_repo_to_branch "$BLOG_FRONTEND_DIR" "$BLOG_DEPLOY_BRANCH")

    log "배포 커밋: $resolved_commit"

    cd "$BLOG_FRONTEND_DIR"

    run_yarn install --immutable
    run_yarn build
    restart_frontend

    wait_for_http "frontend direct" "$BLOG_FRONTEND_HEALTH_URL"
    wait_for_http \
        "frontend nginx" \
        "$BLOG_FRONTEND_PROXY_HEALTH_URL" \
        -H "Host: ${BLOG_PUBLIC_FRONTEND_HOST}"

    record_deploy_state "frontend" "$BLOG_DEPLOY_BRANCH" "$resolved_commit"
    log "frontend 배포 완료"
}

main "$@"
