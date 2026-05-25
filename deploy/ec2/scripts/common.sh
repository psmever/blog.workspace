#!/usr/bin/env bash
set -Eeuo pipefail

: "${BLOG_DEPLOY_ROOT:=/opt/deploy/blog}"
: "${BLOG_DEPLOY_BRANCH:=main}"
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
    log "ERROR: $*"
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

    git -C "$repo_dir" fetch --prune origin "+refs/heads/${branch}:refs/remotes/origin/${branch}"
}

checkout_branch() {
    local repo_dir=$1
    local branch=${2:-$BLOG_DEPLOY_BRANCH}

    if git -C "$repo_dir" show-ref --verify --quiet "refs/heads/${branch}"; then
        git -C "$repo_dir" checkout "$branch"
    else
        git -C "$repo_dir" checkout -b "$branch" --track "origin/${branch}"
    fi
}

fast_forward_branch() {
    local repo_dir=$1
    local branch=${2:-$BLOG_DEPLOY_BRANCH}

    git -C "$repo_dir" merge --ff-only "origin/${branch}"
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

record_deploy_state() {
    local component=$1
    local deploy_branch=$2
    local commit_sha=$3
    local state_file="${BLOG_STATE_DIR}/${component}.last_deploy"

    cat > "$state_file" <<EOF
deploy_branch=$deploy_branch
commit_sha=$commit_sha
deployed_at=$(date -Iseconds)
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
