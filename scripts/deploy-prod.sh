#!/usr/bin/env bash
set -Eeuo pipefail

DEPLOY_HOST=${BLOG_DEPLOY_HOST:-jaubi-prod-app}
REMOTE_DEPLOY_DIR=${BLOG_DEPLOY_REMOTE_DIR:-/opt/deploy/blog}
LOCAL_DEPLOY_SCRIPTS_DIR=${BLOG_DEPLOY_LOCAL_SCRIPTS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../deploy/ec2/scripts" && pwd)}

usage() {
    cat <<EOF
사용법:
  ./scripts/deploy-prod.sh sync
  ./scripts/deploy-prod.sh backend
  ./scripts/deploy-prod.sh frontend
  ./scripts/deploy-prod.sh all
  ./scripts/deploy-prod.sh status

환경변수:
  BLOG_DEPLOY_HOST        SSH 별칭 또는 호스트명 (기본값: jaubi-prod-app)
  BLOG_DEPLOY_REMOTE_DIR  서버 배포 스크립트 경로 (기본값: /opt/deploy/blog)
  BLOG_DEPLOY_LOCAL_SCRIPTS_DIR  로컬 서버 배포 스크립트 경로 (기본값: ${LOCAL_DEPLOY_SCRIPTS_DIR})

예시:
  ./scripts/deploy-prod.sh sync
  ./scripts/deploy-prod.sh backend
  ./scripts/deploy-prod.sh frontend
  ./scripts/deploy-prod.sh all
  ./scripts/deploy-prod.sh status
EOF
}

die() {
    echo "ERROR: $*" >&2
    exit 1
}

require_dir() {
    local dir_path=$1
    [ -d "$dir_path" ] || die "디렉터리를 찾을 수 없습니다: $dir_path"
}

run_remote_script() {
    local remote_script=$1
    shift || true

    local remote_command=""
    printf -v remote_command '%q ' "$remote_script" "$@"
    ssh "$DEPLOY_HOST" "$remote_command"
}

run_remote_shell() {
    local remote_command=$1
    ssh "$DEPLOY_HOST" "$remote_command"
}

cmd_sync() {
    local local_script_dir=$LOCAL_DEPLOY_SCRIPTS_DIR
    local script_files=()
    local remote_mkdir_command=""
    local remote_fix_permissions_command=""

    require_dir "$local_script_dir"

    shopt -s nullglob
    script_files=("$local_script_dir"/*.sh)
    shopt -u nullglob
    [ "${#script_files[@]}" -gt 0 ] || die "업로드할 스크립트를 찾을 수 없습니다: $local_script_dir"

    printf -v remote_mkdir_command 'mkdir -p %q' "$REMOTE_DEPLOY_DIR"
    printf -v remote_fix_permissions_command 'find %q -maxdepth 1 -type f -name %q -exec chmod 755 {} +' "$REMOTE_DEPLOY_DIR" '*.sh'

    echo "서버 배포 스크립트 동기화: host=$DEPLOY_HOST dir=$REMOTE_DEPLOY_DIR"
    run_remote_shell "$remote_mkdir_command"
    scp "${script_files[@]}" "${DEPLOY_HOST}:${REMOTE_DEPLOY_DIR}/"
    run_remote_shell "$remote_fix_permissions_command"
    echo "동기화 완료"
}

cmd_backend() {
    [ $# -eq 0 ] || die "backend 배포는 인자를 받지 않습니다."

    echo "deploy target=backend branch=main host=$DEPLOY_HOST"
    run_remote_script "${REMOTE_DEPLOY_DIR}/deploy-backend.sh"
}

cmd_frontend() {
    [ $# -eq 0 ] || die "frontend 배포는 인자를 받지 않습니다."

    echo "deploy target=frontend branch=main host=$DEPLOY_HOST"
    run_remote_script "${REMOTE_DEPLOY_DIR}/deploy-frontend.sh"
}

cmd_all() {
    [ $# -eq 0 ] || die "all 배포는 인자를 받지 않습니다."

    echo "deploy target=all branch=main host=$DEPLOY_HOST"
    run_remote_script "${REMOTE_DEPLOY_DIR}/deploy-all.sh"
}

cmd_status() {
    [ $# -eq 0 ] || die "status 는 인자를 받지 않습니다."
    echo "deploy status host=$DEPLOY_HOST"
    run_remote_script "${REMOTE_DEPLOY_DIR}/deploy-status.sh"
}

main() {
    local command=${1:-}
    shift || true

    if [ -z "$command" ]; then
        usage
        exit 1
    fi

    case "$command" in
        sync)
            cmd_sync "$@"
            ;;
        backend)
            cmd_backend "$@"
            ;;
        frontend)
            cmd_frontend "$@"
            ;;
        all)
            cmd_all "$@"
            ;;
        status)
            cmd_status "$@"
            ;;
        -h|--help|help)
            usage
            ;;
        *)
            usage
            exit 1
            ;;
    esac
}

main "$@"
