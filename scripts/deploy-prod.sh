#!/usr/bin/env bash
set -Eeuo pipefail

DEPLOY_HOST=${BLOG_DEPLOY_HOST:-jaubi-prod-app}
REMOTE_DEPLOY_DIR=${BLOG_DEPLOY_REMOTE_DIR:-/opt/deploy/blog}
LOCAL_DEPLOY_SCRIPTS_DIR=${BLOG_DEPLOY_LOCAL_SCRIPTS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../deploy/ec2/scripts" && pwd)}
BACKEND_REPO_DIR=${BLOG_BACKEND_REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../blog.backend" && pwd)}
FRONTEND_REPO_DIR=${BLOG_FRONTEND_REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../blog.frontend" && pwd)}
DEPLOY_BRANCH=${BLOG_DEPLOY_BRANCH:-main}
DEPLOY_SOURCE_BRANCH=${BLOG_DEPLOY_SOURCE_BRANCH:-develop}
DEPLOY_TAG_ENV=${BLOG_DEPLOY_TAG_ENV:-prod}
DEPLOY_TAG_PREFIX=${BLOG_DEPLOY_TAG_PREFIX:-deploy/${DEPLOY_TAG_ENV}}
DEPLOY_TAG_REMOTE=${BLOG_DEPLOY_TAG_REMOTE:-origin}
SESSION_TIMESTAMP=${BLOG_DEPLOY_SESSION_TIMESTAMP:-$(date +%Y%m%d-%H%M%S)}
CHECKOUT_SOURCE_REPOS=()
PROMOTION_HAS_CHANGES=0

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
  배포 전에는 로컬 앱 저장소에서 origin/develop 을 main 에 --no-ff 로
  병합하고 origin/main 으로 push합니다.
  origin/develop 에 새 커밋이 없으면 서버 Git 동기화와 배포 태그 생성을
  생략하고 서버 재배포 스크립트만 실행합니다.
  성공 또는 실패로 스크립트가 종료되기 직전에 로컬 저장소를 develop 으로
  checkout 합니다.

환경변수:
  BLOG_DEPLOY_HOST        SSH 별칭 또는 호스트명 (기본값: jaubi-prod-app)
  BLOG_DEPLOY_REMOTE_DIR  서버 배포 스크립트 경로 (기본값: /opt/deploy/blog)
  BLOG_DEPLOY_LOCAL_SCRIPTS_DIR  로컬 서버 배포 스크립트 경로 (기본값: ${LOCAL_DEPLOY_SCRIPTS_DIR})
  BLOG_BACKEND_REPO_DIR   로컬 backend 저장소 경로 (기본값: ${BACKEND_REPO_DIR})
  BLOG_FRONTEND_REPO_DIR  로컬 frontend 저장소 경로 (기본값: ${FRONTEND_REPO_DIR})
  BLOG_DEPLOY_BRANCH      서버 배포 대상 브랜치 (기본값: ${DEPLOY_BRANCH})
  BLOG_DEPLOY_SOURCE_BRANCH  로컬 병합 원본 브랜치 (기본값: ${DEPLOY_SOURCE_BRANCH})
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

log_step() {
    local component=$1
    local step=$2
    local message=$3

    printf '\n[%s][%s] %s\n' "$component" "$step" "$message"
}

print_deploy_flow() {
    local component=$1

    cat <<EOF

============================================================
배포 순서도: $component
============================================================
  01. 로컬 저장소와 작업 트리 확인
  02. origin/main, origin/develop fetch
  03. 로컬 main checkout 및 origin/main fast-forward
  04. origin/develop 신규 커밋 확인
      ├─ 있음: main 에 --no-ff 병합 -> origin/main push
      │        -> 서버 origin/main 동기화 -> 서버 재배포 -> 태그 생성/push
      └─ 없음: 서버 Git 동기화 생략 -> 서버 재배포만 실행
               -> 태그 생성/push 생략
  05. 성공 또는 실패 종료 직전 로컬 develop checkout
============================================================
EOF
}

register_source_checkout() {
    local repo_dir=$1
    local registered_repo

    for registered_repo in "${CHECKOUT_SOURCE_REPOS[@]:-}"; do
        if [ "$registered_repo" = "$repo_dir" ]; then
            return
        fi
    done

    CHECKOUT_SOURCE_REPOS+=("$repo_dir")
}

checkout_source_branches_on_exit() {
    local exit_code=$?
    local checkout_failed=0
    local repo_dir

    trap - EXIT
    set +e

    if [ "${#CHECKOUT_SOURCE_REPOS[@]}" -gt 0 ]; then
        printf '\n============================================================\n'
        printf '[종료 처리] 로컬 저장소를 %s 브랜치로 복귀합니다. exit=%s\n' "$DEPLOY_SOURCE_BRANCH" "$exit_code"
        printf '============================================================\n'
    fi

    for repo_dir in "${CHECKOUT_SOURCE_REPOS[@]}"; do
        printf '[종료 처리] checkout 시작: repo=%s branch=%s\n' "$repo_dir" "$DEPLOY_SOURCE_BRANCH"

        if git -C "$repo_dir" show-ref --verify --quiet "refs/heads/${DEPLOY_SOURCE_BRANCH}"; then
            git -C "$repo_dir" checkout "$DEPLOY_SOURCE_BRANCH"
        elif git -C "$repo_dir" show-ref --verify --quiet "refs/remotes/origin/${DEPLOY_SOURCE_BRANCH}"; then
            git -C "$repo_dir" checkout -b "$DEPLOY_SOURCE_BRANCH" --track "origin/${DEPLOY_SOURCE_BRANCH}"
        else
            printf '[종료 처리] ERROR: checkout 실패: 로컬 또는 origin/%s 브랜치를 찾지 못했습니다. repo=%s\n' \
                "$DEPLOY_SOURCE_BRANCH" "$repo_dir" >&2
            checkout_failed=1
            continue
        fi

        if [ "$(git -C "$repo_dir" branch --show-current)" != "$DEPLOY_SOURCE_BRANCH" ]; then
            printf '[종료 처리] ERROR: checkout 실패: repo=%s expected=%s actual=%s\n' \
                "$repo_dir" "$DEPLOY_SOURCE_BRANCH" "$(git -C "$repo_dir" branch --show-current)" >&2
            checkout_failed=1
            continue
        fi

        printf '[종료 처리] checkout 완료: repo=%s branch=%s\n' "$repo_dir" "$DEPLOY_SOURCE_BRANCH"
    done

    if [ "$checkout_failed" = "1" ] && [ "$exit_code" = "0" ]; then
        exit_code=1
    fi

    exit "$exit_code"
}

trap checkout_source_branches_on_exit EXIT

require_dir() {
    local dir_path=$1
    [ -d "$dir_path" ] || die "디렉터리를 찾을 수 없습니다: $dir_path"
}

require_git_repo() {
    local repo_dir=$1

    require_dir "$repo_dir"
    git -C "$repo_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Git 저장소가 아닙니다: $repo_dir"
}

ensure_git_worktree_clean() {
    local repo_dir=$1
    local dirty=""

    dirty=$(git -C "$repo_dir" status --porcelain --untracked-files=all -- \
        . \
        ':(exclude).DS_Store' \
        ':(exclude,glob)**/.DS_Store')
    [ -z "$dirty" ] || die "로컬 저장소에 변경사항이 있습니다. 먼저 정리하세요: $repo_dir"
}

fetch_origin_branch() {
    local repo_dir=$1
    local branch=$2

    git -C "$repo_dir" fetch --prune origin "+refs/heads/${branch}:refs/remotes/origin/${branch}"
}

checkout_branch() {
    local repo_dir=$1
    local branch=$2

    if git -C "$repo_dir" show-ref --verify --quiet "refs/heads/${branch}"; then
        git -C "$repo_dir" checkout "$branch"
    else
        git -C "$repo_dir" checkout -b "$branch" --track "origin/${branch}"
    fi
}

ensure_branch_not_ahead() {
    local repo_dir=$1
    local branch=$2
    local counts=""
    local ahead_count=""

    counts=$(git -C "$repo_dir" rev-list --left-right --count "${branch}...origin/${branch}")
    ahead_count=${counts%%[[:space:]]*}

    [ "$ahead_count" = "0" ] || die "로컬 ${branch} 브랜치가 origin/${branch} 보다 앞서 있습니다. 먼저 정리하세요: $repo_dir"
}

rollback_local_merge() {
    local repo_dir=$1
    local branch=$2
    local commit_sha=$3

    echo "로컬 ${branch} 브랜치를 병합 전 커밋으로 원복합니다: $commit_sha" >&2

    if git -C "$repo_dir" rev-parse --verify --quiet MERGE_HEAD >/dev/null; then
        git -C "$repo_dir" merge --abort || true
    fi

    git -C "$repo_dir" reset --hard "$commit_sha"
}

promote_local_branch() {
    local component=$1
    local repo_dir=$2
    local ancestor_status=0
    local previous_commit=""

    PROMOTION_HAS_CHANGES=0
    print_deploy_flow "$component"
    register_source_checkout "$repo_dir"

    log_step "$component" "01/05" "로컬 저장소와 작업 트리가 배포 가능한 상태인지 확인합니다."
    require_git_repo "$repo_dir"
    ensure_git_worktree_clean "$repo_dir"

    log_step "$component" "02/05" "origin/${DEPLOY_BRANCH}, origin/${DEPLOY_SOURCE_BRANCH} 브랜치를 fetch 합니다."
    fetch_origin_branch "$repo_dir" "$DEPLOY_BRANCH"
    fetch_origin_branch "$repo_dir" "$DEPLOY_SOURCE_BRANCH"

    log_step "$component" "03/05" "로컬 ${DEPLOY_BRANCH} 브랜치를 checkout 하고 origin/${DEPLOY_BRANCH} 까지 fast-forward 합니다."
    checkout_branch "$repo_dir" "$DEPLOY_BRANCH"
    ensure_branch_not_ahead "$repo_dir" "$DEPLOY_BRANCH"
    git -C "$repo_dir" merge --ff-only "origin/${DEPLOY_BRANCH}"
    previous_commit=$(git -C "$repo_dir" rev-parse HEAD)

    log_step "$component" "04/05" "origin/${DEPLOY_SOURCE_BRANCH} 에 ${DEPLOY_BRANCH} 미반영 커밋이 있는지 확인합니다."

    if git -C "$repo_dir" merge-base --is-ancestor "origin/${DEPLOY_SOURCE_BRANCH}" "$DEPLOY_BRANCH"; then
        printf '[%s][분기] 신규 커밋 없음: origin/%s 의 모든 커밋이 %s 에 이미 반영되어 있습니다.\n' \
            "$component" "$DEPLOY_SOURCE_BRANCH" "$DEPLOY_BRANCH"
        printf '[%s][분기] 병합, origin/%s push, 서버 Git 동기화, 배포 태그 생성을 생략합니다.\n' \
            "$component" "$DEPLOY_BRANCH"
        return
    else
        ancestor_status=$?
    fi

    [ "$ancestor_status" = "1" ] \
        || die "원격 develop 신규 커밋 확인에 실패했습니다: $component origin/${DEPLOY_SOURCE_BRANCH} -> ${DEPLOY_BRANCH}"

    PROMOTION_HAS_CHANGES=1
    printf '[%s][분기] 신규 커밋 있음: origin/%s 을 %s 에 --no-ff 로 병합합니다.\n' \
        "$component" "$DEPLOY_SOURCE_BRANCH" "$DEPLOY_BRANCH"

    if ! git -C "$repo_dir" merge --no-ff "origin/${DEPLOY_SOURCE_BRANCH}" \
        -m "Merge origin/${DEPLOY_SOURCE_BRANCH} into ${DEPLOY_BRANCH} for deployment"; then
        rollback_local_merge "$repo_dir" "$DEPLOY_BRANCH" "$previous_commit"
        die "로컬 브랜치 병합에 실패했습니다: $component origin/${DEPLOY_SOURCE_BRANCH} -> ${DEPLOY_BRANCH}"
    fi

    if ! git -C "$repo_dir" push origin "${DEPLOY_BRANCH}:${DEPLOY_BRANCH}"; then
        rollback_local_merge "$repo_dir" "$DEPLOY_BRANCH" "$previous_commit"
        die "원격 브랜치 push에 실패했습니다: $component origin/${DEPLOY_BRANCH}"
    fi

    printf '[%s][분기] origin/%s push 완료: 서버 Git 동기화와 배포 태그 생성을 진행합니다.\n' \
        "$component" "$DEPLOY_BRANCH"
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

    git -C "$repo_dir" fetch --no-tags "$DEPLOY_TAG_REMOTE" "+refs/heads/${DEPLOY_BRANCH}:refs/remotes/${DEPLOY_TAG_REMOTE}/${DEPLOY_BRANCH}"
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

    printf '\n============================================================\n'
    printf '배포 시작: component=%s branch=%s host=%s\n' "$component" "$DEPLOY_BRANCH" "$DEPLOY_HOST"
    printf '============================================================\n'

    promote_local_branch "$component" "$repo_dir"

    log_step "$component" "05/05" "서버 배포 스크립트를 실행합니다."

    if [ "$PROMOTION_HAS_CHANGES" = "1" ]; then
        printf '[%s][서버] 신규 커밋이 있으므로 서버에서 origin/%s 을 동기화한 뒤 배포합니다.\n' \
            "$component" "$DEPLOY_BRANCH"
        run_remote_script "$remote_script"

        printf '[%s][태그] 신규 커밋 배포이므로 배포 태그를 생성하고 push 합니다.\n' "$component"
        create_and_push_deploy_tag "$component" "$repo_dir"
    else
        printf '[%s][서버] 신규 커밋이 없으므로 서버 Git 동기화를 생략하고 재배포만 수행합니다.\n' "$component"
        run_remote_script "$remote_script" --skip-git-sync
        printf '[%s][태그] 신규 커밋이 없으므로 배포 태그 생성을 생략합니다.\n' "$component"
    fi

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
