#!/usr/bin/env bash
set -Eeuo pipefail

DEPLOY_HOST=${BLOG_DEPLOY_HOST:-blog-prod}
REMOTE_DEPLOY_DIR=${BLOG_DEPLOY_REMOTE_DIR:-/opt/deploy/blog}

usage() {
    cat <<'EOF'
사용법:
  ./scripts/deploy-prod.sh <backend|frontend|all> <tag-or-sha>

환경변수:
  BLOG_DEPLOY_HOST        SSH 별칭 또는 호스트명 (기본값: blog-prod)
  BLOG_DEPLOY_REMOTE_DIR  서버 배포 스크립트 경로 (기본값: /opt/deploy/blog)

예시:
  ./scripts/deploy-prod.sh backend v2026.05.21-1
  ./scripts/deploy-prod.sh frontend 8f42ab1
  ./scripts/deploy-prod.sh all v2026.05.21-1
EOF
}

main() {
    local target=${1:-}
    local requested_ref=${2:-}
    local remote_script=""
    local remote_command=""

    if [ -z "$target" ] || [ -z "$requested_ref" ]; then
        usage
        exit 1
    fi

    case "$target" in
        backend)
            remote_script="${REMOTE_DEPLOY_DIR}/deploy-backend.sh"
            ;;
        frontend)
            remote_script="${REMOTE_DEPLOY_DIR}/deploy-frontend.sh"
            ;;
        all)
            remote_script="${REMOTE_DEPLOY_DIR}/deploy-all.sh"
            ;;
        *)
            usage
            exit 1
            ;;
    esac

    printf -v remote_command '%q ' "$remote_script" "$requested_ref"

    echo "🚀 deploy target=$target ref=$requested_ref host=$DEPLOY_HOST"
    ssh "$DEPLOY_HOST" "$remote_command"
}

main "$@"
