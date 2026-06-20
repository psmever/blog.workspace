#!/usr/bin/env bash
set -Eeuo pipefail

: "${BLOG_DEPLOY_ROOT:=/opt/deploy/blog}"
: "${BLOG_DEPLOY_BRANCH:=main}"
: "${BLOG_DEPLOY_SOURCE_BRANCH:=develop}"
: "${BLOG_DEPLOY_TAG_ENV:=prod}"
: "${BLOG_DEPLOY_TAG_PREFIX:=deploy/${BLOG_DEPLOY_TAG_ENV}}"
: "${BLOG_DEPLOY_TAG_REMOTE:=origin}"
: "${BLOG_DEPLOY_SESSION_TIMESTAMP:=$(date +%Y%m%d-%H%M%S)}"
: "${BLOG_BACKEND_DIR:=/var/www/jaubi.co.kr/blog/blog.backend}"
: "${BLOG_FRONTEND_DIR:=/var/www/jaubi.co.kr/blog/blog.frontend}"
: "${BLOG_LOG_DIR:=${BLOG_DEPLOY_ROOT}/logs}"
: "${BLOG_STATE_DIR:=${BLOG_DEPLOY_ROOT}/state}"
: "${BLOG_BACKEND_HEALTH_URL:=http://127.0.0.1:4000/api/health}"
: "${BLOG_BACKEND_PROXY_HEALTH_URL:=http://127.0.0.1/api/health}"
: "${BLOG_FRONTEND_HEALTH_URL:=http://127.0.0.1:3000}"
: "${BLOG_FRONTEND_PROXY_HEALTH_URL:=http://127.0.0.1}"
: "${BLOG_PUBLIC_FRONTEND_HOST:=blog.jaubi.co.kr}"
: "${BLOG_PUBLIC_BACKEND_HOST:=blog.api.jaubi.co.kr}"
: "${BLOG_CLIENT_TYPE:=CT04P}"
: "${BLOG_HEALTHCHECK_ATTEMPTS:=15}"
: "${BLOG_HEALTHCHECK_DELAY_SECONDS:=2}"

timestamp() {
    date "+%Y-%m-%d %H:%M:%S %Z"
}

log() {
    printf '[%s] %s\n' "$(timestamp)" "$*"
}

die() {
    log "ERROR: $*" >&2
    exit 1
}

trap_err() {
    local line_no=$1
    local command=$2
    local exit_code=$3

    log "ERROR: line ${line_no}: ${command} (exit=${exit_code})"
    exit "$exit_code"
}

require_commands() {
    local command_name

    for command_name in "$@"; do
        command -v "$command_name" >/dev/null 2>&1 || die "필수 명령이 없습니다: $command_name"
    done
}

require_dir() {
    local dir_path=$1
    [ -d "$dir_path" ] || die "디렉터리를 찾을 수 없습니다: $dir_path"
}

require_file() {
    local file_path=$1
    [ -f "$file_path" ] || die "파일을 찾을 수 없습니다: $file_path"
}

init_logging() {
    local deploy_name=$1
    local log_file

    mkdir -p "$BLOG_DEPLOY_ROOT" "$BLOG_LOG_DIR" "$BLOG_STATE_DIR"
    log_file="${BLOG_LOG_DIR}/${deploy_name}-$(date +%Y%m%d_%H%M%S).log"

    exec > >(tee -a "$log_file") 2>&1

    log "로그 파일: $log_file"
}

acquire_deploy_lock() {
    local lock_file="${BLOG_DEPLOY_ROOT}/.deploy.lock"

    if [ "${BLOG_SKIP_DEPLOY_LOCK:-0}" = "1" ]; then
        return
    fi

    exec {DEPLOY_LOCK_FD}> "$lock_file"
    flock -n "$DEPLOY_LOCK_FD" || die "다른 배포가 진행 중입니다. lock=$lock_file"
}

ensure_git_worktree_clean() {
    local repo_dir=$1
    local dirty

    dirty=$(git -C "$repo_dir" status --porcelain --untracked-files=no)
    [ -z "$dirty" ] || die "서버 저장소에 추적 중인 변경사항이 있습니다. 먼저 정리하세요: $repo_dir"
}

sanitize_laravel_cache_state() {
    local repo_dir=$1

    if [ -d "$repo_dir/bootstrap/cache" ]; then
        log "Laravel bootstrap cache 생성 파일을 정리합니다."
        find "$repo_dir/bootstrap/cache" -maxdepth 1 -type f \
            \( -name 'packages.php' -o -name 'services.php' -o -name 'config.php' -o -name 'events.php' -o -name 'routes-*.php' \) \
            -delete
    fi
}

fetch_origin_branch() {
    local repo_dir=$1
    local branch=${2:-$BLOG_DEPLOY_BRANCH}

    git -C "$repo_dir" fetch --prune origin "+refs/heads/${branch}:refs/remotes/origin/${branch}" >&2
}

checkout_branch() {
    local repo_dir=$1
    local branch=${2:-$BLOG_DEPLOY_BRANCH}

    if git -C "$repo_dir" show-ref --verify --quiet "refs/heads/${branch}"; then
        git -C "$repo_dir" checkout "$branch" >&2
    else
        git -C "$repo_dir" checkout -b "$branch" --track "origin/${branch}" >&2
    fi
}

fast_forward_branch() {
    local repo_dir=$1
    local branch=${2:-$BLOG_DEPLOY_BRANCH}

    git -C "$repo_dir" merge --ff-only "origin/${branch}" >&2
}

rollback_server_merge() {
    local repo_dir=$1
    local branch=$2
    local commit_sha=$3

    log "서버 ${branch} 브랜치를 병합 전 커밋으로 원복합니다: $commit_sha"

    if git -C "$repo_dir" rev-parse --verify --quiet MERGE_HEAD >/dev/null; then
        git -C "$repo_dir" merge --abort || true
    fi

    git -C "$repo_dir" reset --hard "$commit_sha"
}

promote_source_to_deploy_branch() {
    local component=$1
    local repo_dir=$2
    local previous_commit
    local ancestor_status=0

    BLOG_PROMOTION_HAS_CHANGES=0
    BLOG_RESOLVED_COMMIT=""

    log "[Git 1/5] origin/${BLOG_DEPLOY_BRANCH}, origin/${BLOG_DEPLOY_SOURCE_BRANCH} 브랜치를 fetch 합니다."
    fetch_origin_branch "$repo_dir" "$BLOG_DEPLOY_BRANCH"
    fetch_origin_branch "$repo_dir" "$BLOG_DEPLOY_SOURCE_BRANCH"

    log "[Git 2/5] ${BLOG_DEPLOY_BRANCH} 브랜치를 origin/${BLOG_DEPLOY_BRANCH} 까지 fast-forward 합니다."
    checkout_branch "$repo_dir" "$BLOG_DEPLOY_BRANCH"
    ensure_branch_not_ahead "$repo_dir" "$BLOG_DEPLOY_BRANCH"
    fast_forward_branch "$repo_dir" "$BLOG_DEPLOY_BRANCH"
    previous_commit=$(git -C "$repo_dir" rev-parse HEAD)

    log "[Git 3/5] origin/${BLOG_DEPLOY_SOURCE_BRANCH} 미반영 커밋을 확인합니다."
    if git -C "$repo_dir" merge-base --is-ancestor \
        "origin/${BLOG_DEPLOY_SOURCE_BRANCH}" "$BLOG_DEPLOY_BRANCH"; then
        BLOG_RESOLVED_COMMIT=$previous_commit
        log "[Git 4/5] 신규 커밋 없음: 병합과 origin/${BLOG_DEPLOY_BRANCH} push를 생략합니다."
        log "[Git 5/5] 현재 ${BLOG_DEPLOY_BRANCH} 커밋을 재배포합니다: ${BLOG_RESOLVED_COMMIT}"
        return
    else
        ancestor_status=$?
    fi

    [ "$ancestor_status" = "1" ] \
        || die "신규 커밋 확인에 실패했습니다: ${component} origin/${BLOG_DEPLOY_SOURCE_BRANCH} -> ${BLOG_DEPLOY_BRANCH}"

    BLOG_PROMOTION_HAS_CHANGES=1
    log "[Git 4/5] origin/${BLOG_DEPLOY_SOURCE_BRANCH} 을 ${BLOG_DEPLOY_BRANCH} 에 --no-ff 로 병합합니다."
    if ! git -C "$repo_dir" merge --no-ff "origin/${BLOG_DEPLOY_SOURCE_BRANCH}" \
        -m "Merge origin/${BLOG_DEPLOY_SOURCE_BRANCH} into ${BLOG_DEPLOY_BRANCH} for deployment"; then
        rollback_server_merge "$repo_dir" "$BLOG_DEPLOY_BRANCH" "$previous_commit"
        die "서버 브랜치 병합에 실패했습니다: ${component} origin/${BLOG_DEPLOY_SOURCE_BRANCH} -> ${BLOG_DEPLOY_BRANCH}"
    fi

    BLOG_RESOLVED_COMMIT=$(git -C "$repo_dir" rev-parse HEAD)
    log "[Git 5/5] 병합 커밋을 origin/${BLOG_DEPLOY_BRANCH} 으로 push 합니다: ${BLOG_RESOLVED_COMMIT}"
    if ! git -C "$repo_dir" push origin "${BLOG_DEPLOY_BRANCH}:${BLOG_DEPLOY_BRANCH}"; then
        rollback_server_merge "$repo_dir" "$BLOG_DEPLOY_BRANCH" "$previous_commit"
        BLOG_RESOLVED_COMMIT=""
        die "원격 브랜치 push에 실패했습니다: ${component} origin/${BLOG_DEPLOY_BRANCH}"
    fi
}

ensure_branch_not_ahead() {
    local repo_dir=$1
    local branch=${2:-$BLOG_DEPLOY_BRANCH}
    local counts=""
    local ahead_count=""

    counts=$(git -C "$repo_dir" rev-list --left-right --count "${branch}...origin/${branch}")
    ahead_count=${counts%%[[:space:]]*}

    [ "$ahead_count" = "0" ] || die "서버 ${branch} 브랜치가 origin/${branch} 보다 앞서 있습니다. 먼저 정리하세요: $repo_dir"
}

sync_repo_to_branch() {
    local repo_dir=$1
    local branch=${2:-$BLOG_DEPLOY_BRANCH}

    fetch_origin_branch "$repo_dir" "$branch"
    checkout_branch "$repo_dir" "$branch"
    ensure_branch_not_ahead "$repo_dir" "$branch"
    fast_forward_branch "$repo_dir" "$branch"
    git -C "$repo_dir" rev-parse HEAD
}

create_and_push_deploy_tag() {
    local component=$1
    local repo_dir=$2
    local commit_sha=$3
    local deployed_at=$4
    local tag_name="${BLOG_DEPLOY_TAG_PREFIX}/${component}/${BLOG_DEPLOY_SESSION_TIMESTAMP}"
    local remote_tag_output

    git -C "$repo_dir" rev-parse --verify --quiet "refs/tags/${tag_name}" >/dev/null 2>&1 \
        && die "로컬 배포 태그가 이미 존재합니다: ${tag_name}"

    remote_tag_output=$(git -C "$repo_dir" ls-remote --tags --refs \
        "$BLOG_DEPLOY_TAG_REMOTE" "refs/tags/${tag_name}") \
        || die "원격 배포 태그 확인에 실패했습니다: ${tag_name}"
    [ -z "$remote_tag_output" ] || die "원격 배포 태그가 이미 존재합니다: ${tag_name}"

    log "배포 태그를 생성합니다: ${tag_name} commit=${commit_sha}"
    git -C "$repo_dir" tag -a "$tag_name" "$commit_sha" \
        -m "Deploy ${BLOG_DEPLOY_TAG_ENV} ${component} ${BLOG_DEPLOY_SESSION_TIMESTAMP}" \
        -m "environment: ${BLOG_DEPLOY_TAG_ENV}" \
        -m "component: ${component}" \
        -m "branch: ${BLOG_DEPLOY_BRANCH}" \
        -m "commit: ${commit_sha}" \
        -m "deployed_at: ${deployed_at}"

    if ! git -C "$repo_dir" push "$BLOG_DEPLOY_TAG_REMOTE" "refs/tags/${tag_name}"; then
        git -C "$repo_dir" tag -d "$tag_name" >/dev/null 2>&1 || true
        die "배포는 완료됐지만 태그 push에 실패했습니다: ${component} ${tag_name}"
    fi

    log "배포 태그 push 완료: ${tag_name}"
}

record_deploy_state() {
    local component=$1
    local deploy_branch=$2
    local commit_sha=$3
    local deployed_at=${4:-$(date -Iseconds)}
    local state_file="${BLOG_STATE_DIR}/${component}.last_deploy"

    cat > "$state_file" <<EOF
deploy_branch=$deploy_branch
commit_sha=$commit_sha
deployed_at=$deployed_at
EOF
}

wait_for_http() {
    local check_name=$1
    local url=$2
    shift 2

    local attempt

    for ((attempt = 1; attempt <= BLOG_HEALTHCHECK_ATTEMPTS; attempt += 1)); do
        if curl -fsS --max-time 10 "$@" "$url" >/dev/null; then
            log "헬스체크 통과: $check_name"
            return 0
        fi

        log "헬스체크 재시도 ${attempt}/${BLOG_HEALTHCHECK_ATTEMPTS}: $check_name"
        sleep "$BLOG_HEALTHCHECK_DELAY_SECONDS"
    done

    die "헬스체크 실패: $check_name ($url)"
}

run_sudo() {
    if ! sudo -n "$@"; then
        die "sudo 명령에 실패했습니다. 비밀번호 없는 sudo 권한이 필요합니다: $*"
    fi
}

load_node_toolchain() {
    export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
    export PM2_HOME="${PM2_HOME:-$HOME/.pm2}"

    if [ -s "$NVM_DIR/nvm.sh" ]; then
        # shellcheck disable=SC1090
        . "$NVM_DIR/nvm.sh"
    fi

    command -v node >/dev/null 2>&1 || die "node 명령을 찾을 수 없습니다."
    command -v corepack >/dev/null 2>&1 || die "corepack 명령을 찾을 수 없습니다."
    command -v pm2 >/dev/null 2>&1 || die "pm2 명령을 찾을 수 없습니다."
}

run_yarn() {
    corepack yarn "$@"
}
