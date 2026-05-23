#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

trap 'trap_err "${LINENO}" "${BASH_COMMAND}" "$?"' ERR

usage() {
    cat <<'EOF'
사용법:
  ./deploy-frontend.sh <tag-or-sha>

예시:
  ./deploy-frontend.sh v2026.05.21-1
  ./deploy-frontend.sh 8f42ab1
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
    local requested_ref=${1:-}
    local resolved_commit

    [ -n "$requested_ref" ] || {
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

    log "frontend 배포 시작: ref=$requested_ref"

    ensure_git_worktree_clean "$BLOG_FRONTEND_DIR"
    fetch_origin "$BLOG_FRONTEND_DIR"
    resolved_commit=$(resolve_ref "$BLOG_FRONTEND_DIR" "$requested_ref")

    log "배포 커밋: $resolved_commit"
    checkout_commit "$BLOG_FRONTEND_DIR" "$resolved_commit"

    cd "$BLOG_FRONTEND_DIR"

    run_yarn install --immutable
    run_yarn build
    restart_frontend

    wait_for_http "frontend direct" "$BLOG_FRONTEND_HEALTH_URL"
    wait_for_http \
        "frontend nginx" \
        "$BLOG_FRONTEND_PROXY_HEALTH_URL" \
        -H "Host: ${BLOG_PUBLIC_FRONTEND_HOST}"

    record_deploy_state "frontend" "$requested_ref" "$resolved_commit"
    log "frontend 배포 완료"
}

main "$@"
