#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

trap 'trap_err "${LINENO}" "${BASH_COMMAND}" "$?"' ERR

usage() {
    cat <<'EOF'
사용법:
  ./deploy-all.sh

예시:
  ./deploy-all.sh
EOF
}

main() {
    [ $# -eq 0 ] || {
        usage
        exit 1
    }

    init_logging "deploy-all"
    acquire_deploy_lock
    require_file "$SCRIPT_DIR/deploy-backend.sh"
    require_file "$SCRIPT_DIR/deploy-frontend.sh"

    log "전체 배포 시작: branch=${BLOG_DEPLOY_BRANCH}"
    BLOG_SKIP_DEPLOY_LOCK=1 "$SCRIPT_DIR/deploy-backend.sh"
    BLOG_SKIP_DEPLOY_LOCK=1 "$SCRIPT_DIR/deploy-frontend.sh"
    log "전체 배포 완료"
}

main "$@"
