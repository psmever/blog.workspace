#!/usr/bin/env bash
set -Eeuo pipefail

DEPLOY_HOST=${BLOG_DEPLOY_HOST:-jaubi-prod-app}
REMOTE_DEPLOY_DIR=${BLOG_DEPLOY_REMOTE_DIR:-/opt/deploy/blog}
LOCAL_DEPLOY_SCRIPTS_DIR=${BLOG_DEPLOY_LOCAL_SCRIPTS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../deploy/ec2/scripts" && pwd)}
DEPLOY_BRANCH=${BLOG_DEPLOY_BRANCH:-main}
DEPLOY_SOURCE_BRANCH=${BLOG_DEPLOY_SOURCE_BRANCH:-develop}
DEPLOY_TAG_ENV=${BLOG_DEPLOY_TAG_ENV:-prod}
DEPLOY_TAG_PREFIX=${BLOG_DEPLOY_TAG_PREFIX:-deploy/${DEPLOY_TAG_ENV}}
SESSION_TIMESTAMP=${BLOG_DEPLOY_SESSION_TIMESTAMP:-$(date +%Y%m%d-%H%M%S)}

usage() {
    cat <<EOF
사용법:
  ./scripts/deploy-prod.sh sync
  ./scripts/deploy-prod.sh backend
  ./scripts/deploy-prod.sh frontend
  ./scripts/deploy-prod.sh all
  ./scripts/deploy-prod.sh status

설명:
  backend/frontend/all 배포 시 서버가 origin/develop 을 main 에
  --no-ff 로 병합하고 origin/main 으로 push한 뒤 배포합니다.
  origin/develop 이 이미 main 에 반영된 경우 병합과 push를 생략하고
  현재 main 커밋을 재배포합니다. 신규 승격 배포 성공 후에는 서버에서
  deploy/prod/<app>/<timestamp> annotated tag를 생성하고 push합니다.

환경변수:
  BLOG_DEPLOY_HOST        SSH 별칭 또는 호스트명 (기본값: jaubi-prod-app)
  BLOG_DEPLOY_REMOTE_DIR  서버 배포 스크립트 경로 (기본값: /opt/deploy/blog)
  BLOG_DEPLOY_LOCAL_SCRIPTS_DIR  로컬 서버 배포 스크립트 경로 (기본값: ${LOCAL_DEPLOY_SCRIPTS_DIR})
  BLOG_DEPLOY_BRANCH      서버 배포 대상 브랜치 (기본값: ${DEPLOY_BRANCH})
  BLOG_DEPLOY_SOURCE_BRANCH  서버 병합 원본 브랜치 (기본값: ${DEPLOY_SOURCE_BRANCH})
  BLOG_DEPLOY_TAG_ENV     배포 태그 환경명 (기본값: ${DEPLOY_TAG_ENV})
  BLOG_DEPLOY_TAG_PREFIX  배포 태그 prefix (기본값: ${DEPLOY_TAG_PREFIX})
  BLOG_DEPLOY_SESSION_TIMESTAMP  배포 세션 timestamp override (기본값: ${SESSION_TIMESTAMP})

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

log_step() {
    local component=$1
    local step=$2
    local message=$3

    printf '\n[%s][%s] %s\n' "$component" "$step" "$message"
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

deploy_component() {
    local component=$1
    local remote_script=$2

    printf '\n============================================================\n'
    printf '배포 시작: component=%s branch=%s host=%s\n' "$component" "$DEPLOY_BRANCH" "$DEPLOY_HOST"
    printf '============================================================\n'

    log_step "$component" "01/01" "서버 승격 및 배포 스크립트를 실행합니다."
    run_remote_script env \
        "BLOG_DEPLOY_BRANCH=$DEPLOY_BRANCH" \
        "BLOG_DEPLOY_SOURCE_BRANCH=$DEPLOY_SOURCE_BRANCH" \
        "BLOG_DEPLOY_TAG_ENV=$DEPLOY_TAG_ENV" \
        "BLOG_DEPLOY_TAG_PREFIX=$DEPLOY_TAG_PREFIX" \
        "BLOG_DEPLOY_SESSION_TIMESTAMP=$SESSION_TIMESTAMP" \
        "$remote_script"

    printf '[%s][완료] 컴포넌트 배포가 완료되었습니다.\n' "$component"
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

    deploy_component "backend" "${REMOTE_DEPLOY_DIR}/deploy-backend.sh"
}

cmd_frontend() {
    [ $# -eq 0 ] || die "frontend 배포는 인자를 받지 않습니다."

    deploy_component "frontend" "${REMOTE_DEPLOY_DIR}/deploy-frontend.sh"
}

cmd_all() {
    [ $# -eq 0 ] || die "all 배포는 인자를 받지 않습니다."

    run_remote_script env \
        "BLOG_DEPLOY_BRANCH=$DEPLOY_BRANCH" \
        "BLOG_DEPLOY_SOURCE_BRANCH=$DEPLOY_SOURCE_BRANCH" \
        "BLOG_DEPLOY_TAG_ENV=$DEPLOY_TAG_ENV" \
        "BLOG_DEPLOY_TAG_PREFIX=$DEPLOY_TAG_PREFIX" \
        "BLOG_DEPLOY_SESSION_TIMESTAMP=$SESSION_TIMESTAMP" \
        "${REMOTE_DEPLOY_DIR}/deploy-all.sh"
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
