#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

trap 'trap_err "${LINENO}" "${BASH_COMMAND}" "$?"' ERR

usage() {
    cat <<'EOF'
사용법:
  ./deploy-all.sh <tag-or-sha>

예시:
  ./deploy-all.sh v2026.05.21-1
EOF
}

main() {
    local requested_ref=${1:-}

    [ -n "$requested_ref" ] || {
        usage
        exit 1
    }

    init_logging "deploy-all"
    acquire_deploy_lock
    require_file "$SCRIPT_DIR/deploy-backend.sh"
    require_file "$SCRIPT_DIR/deploy-frontend.sh"

    log "전체 배포 시작: ref=$requested_ref"
    BLOG_SKIP_DEPLOY_LOCK=1 "$SCRIPT_DIR/deploy-backend.sh" "$requested_ref"
    BLOG_SKIP_DEPLOY_LOCK=1 "$SCRIPT_DIR/deploy-frontend.sh" "$requested_ref"
    log "전체 배포 완료"
}

main "$@"
