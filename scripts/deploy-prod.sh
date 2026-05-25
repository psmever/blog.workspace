#!/usr/bin/env bash
set -Eeuo pipefail

DEPLOY_HOST=${BLOG_DEPLOY_HOST:-jaubi-prod-app}
REMOTE_DEPLOY_DIR=${BLOG_DEPLOY_REMOTE_DIR:-/opt/deploy/blog}
LOCAL_DEPLOY_SCRIPTS_DIR=${BLOG_DEPLOY_LOCAL_SCRIPTS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../deploy/ec2/scripts" && pwd)}
BACKEND_REPO_DIR=${BLOG_BACKEND_REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../blog.backend" && pwd)}
FRONTEND_REPO_DIR=${BLOG_FRONTEND_REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../blog.frontend" && pwd)}
DEPLOY_BRANCH=${BLOG_DEPLOY_BRANCH:-main}
DEPLOY_TAG_ENV=${BLOG_DEPLOY_TAG_ENV:-prod}
DEPLOY_TAG_PREFIX=${BLOG_DEPLOY_TAG_PREFIX:-deploy/${DEPLOY_TAG_ENV}}
DEPLOY_TAG_REMOTE=${BLOG_DEPLOY_TAG_REMOTE:-origin}
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
  backend/frontend/all 배포가 성공하면 각 앱 저장소에
  deploy/prod/<app>/<timestamp> annotated tag를 자동 생성하고 push합니다.

환경변수:
  BLOG_DEPLOY_HOST        SSH 별칭 또는 호스트명 (기본값: jaubi-prod-app)
  BLOG_DEPLOY_REMOTE_DIR  서버 배포 스크립트 경로 (기본값: /opt/deploy/blog)
  BLOG_DEPLOY_LOCAL_SCRIPTS_DIR  로컬 서버 배포 스크립트 경로 (기본값: ${LOCAL_DEPLOY_SCRIPTS_DIR})
  BLOG_BACKEND_REPO_DIR   로컬 backend 저장소 경로 (기본값: ${BACKEND_REPO_DIR})
  BLOG_FRONTEND_REPO_DIR  로컬 frontend 저장소 경로 (기본값: ${FRONTEND_REPO_DIR})
  BLOG_DEPLOY_BRANCH      서버 배포 대상 브랜치 (기본값: ${DEPLOY_BRANCH})
  BLOG_DEPLOY_TAG_ENV     배포 태그 환경명 (기본값: ${DEPLOY_TAG_ENV})
  BLOG_DEPLOY_TAG_PREFIX  배포 태그 prefix (기본값: ${DEPLOY_TAG_PREFIX})
  BLOG_DEPLOY_TAG_REMOTE  태그 push 대상 remote (기본값: ${DEPLOY_TAG_REMOTE})
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

require_dir() {
    local dir_path=$1
    [ -d "$dir_path" ] || die "디렉터리를 찾을 수 없습니다: $dir_path"
}

require_git_repo() {
    local repo_dir=$1

    require_dir "$repo_dir"
    git -C "$repo_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Git 저장소가 아닙니다: $repo_dir"
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

load_remote_component_state() {
    local component=$1
    local output=""

    REMOTE_DEPLOY_BRANCH=""
    REMOTE_COMMIT_SHA=""
    REMOTE_DEPLOYED_AT=""

    output=$(run_remote_script "${REMOTE_DEPLOY_DIR}/deploy-status.sh" --component "$component" --format env)

    while IFS='=' read -r key value; do
        case "$key" in
            deploy_branch)
                REMOTE_DEPLOY_BRANCH=$value
                ;;
            commit_sha)
                REMOTE_COMMIT_SHA=$value
                ;;
            deployed_at)
                REMOTE_DEPLOYED_AT=$value
                ;;
        esac
    done <<< "$output"

    [ -n "$REMOTE_DEPLOY_BRANCH" ] || die "원격 배포 브랜치 정보를 읽지 못했습니다: $component"
    [ -n "$REMOTE_COMMIT_SHA" ] || die "원격 배포 커밋 정보를 읽지 못했습니다: $component"
    [ -n "$REMOTE_DEPLOYED_AT" ] || die "원격 배포 시각 정보를 읽지 못했습니다: $component"
}

ensure_tag_not_exists() {
    local repo_dir=$1
    local tag_name=$2
    local remote_tag_output=""

    git -C "$repo_dir" rev-parse --verify --quiet "refs/tags/${tag_name}" >/dev/null 2>&1 \
        && die "로컬 태그가 이미 존재합니다: ${repo_dir} ${tag_name}"

    remote_tag_output=$(git -C "$repo_dir" ls-remote --tags --refs "$DEPLOY_TAG_REMOTE" "refs/tags/${tag_name}") \
        || die "원격 태그 확인에 실패했습니다: ${repo_dir} ${DEPLOY_TAG_REMOTE}"

    [ -z "$remote_tag_output" ] || die "원격 태그가 이미 존재합니다: ${repo_dir} ${tag_name}"
}

create_and_push_deploy_tag() {
    local component=$1
    local repo_dir=$2
    local tag_name="${DEPLOY_TAG_PREFIX}/${component}/${SESSION_TIMESTAMP}"

    require_git_repo "$repo_dir"
    load_remote_component_state "$component"

    [ "$REMOTE_DEPLOY_BRANCH" = "$DEPLOY_BRANCH" ] || die "원격 배포 브랜치가 예상과 다릅니다: expected=${DEPLOY_BRANCH} actual=${REMOTE_DEPLOY_BRANCH}"

    echo "deploy tag create component=$component repo=$repo_dir tag=$tag_name commit=$REMOTE_COMMIT_SHA"

    git -C "$repo_dir" fetch "$DEPLOY_TAG_REMOTE" "$DEPLOY_BRANCH" --tags
    git -C "$repo_dir" cat-file -e "${REMOTE_COMMIT_SHA}^{commit}" >/dev/null 2>&1 \
        || die "로컬 저장소에서 원격 배포 커밋을 찾지 못했습니다: ${repo_dir} ${REMOTE_COMMIT_SHA}"

    ensure_tag_not_exists "$repo_dir" "$tag_name"

    git -C "$repo_dir" tag -a "$tag_name" "$REMOTE_COMMIT_SHA" \
        -m "Deploy ${DEPLOY_TAG_ENV} ${component} ${SESSION_TIMESTAMP}" \
        -m "environment: ${DEPLOY_TAG_ENV}" \
        -m "component: ${component}" \
        -m "branch: ${REMOTE_DEPLOY_BRANCH}" \
        -m "commit: ${REMOTE_COMMIT_SHA}" \
        -m "deployed_at: ${REMOTE_DEPLOYED_AT}" \
        -m "host: ${DEPLOY_HOST}"

    if ! git -C "$repo_dir" push "$DEPLOY_TAG_REMOTE" "refs/tags/${tag_name}"; then
        git -C "$repo_dir" tag -d "$tag_name" >/dev/null 2>&1 || true
        die "배포는 완료됐지만 태그 기록 push는 실패했습니다: ${component} ${tag_name}"
    fi

    echo "deploy tag pushed component=$component tag=$tag_name"
}

deploy_and_tag_component() {
    local component=$1
    local repo_dir=$2
    local remote_script=$3

    echo "deploy target=$component branch=$DEPLOY_BRANCH host=$DEPLOY_HOST"
    run_remote_script "$remote_script"
    create_and_push_deploy_tag "$component" "$repo_dir"
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

    deploy_and_tag_component "backend" "$BACKEND_REPO_DIR" "${REMOTE_DEPLOY_DIR}/deploy-backend.sh"
}

cmd_frontend() {
    [ $# -eq 0 ] || die "frontend 배포는 인자를 받지 않습니다."

    deploy_and_tag_component "frontend" "$FRONTEND_REPO_DIR" "${REMOTE_DEPLOY_DIR}/deploy-frontend.sh"
}

cmd_all() {
    [ $# -eq 0 ] || die "all 배포는 인자를 받지 않습니다."

    deploy_and_tag_component "backend" "$BACKEND_REPO_DIR" "${REMOTE_DEPLOY_DIR}/deploy-backend.sh"
    deploy_and_tag_component "frontend" "$FRONTEND_REPO_DIR" "${REMOTE_DEPLOY_DIR}/deploy-frontend.sh"
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
