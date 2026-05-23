# 🧰 Blog Workspace Development Environment

Laravel (Backend) + Next.js (Frontend) + MariaDB
로컬 개발을 위한 Docker 환경이며, `.env` 파일을 암호화하여 관리할 수 있습니다.

---

## 📂 디렉토리 구조

```
blog/
├── blog.backend/       # Laravel 백엔드
├── blog.frontend/      # Next.js 프론트엔드
└── blog.workspace/     # 공용 개발/배포 워크스페이스 (현재 디렉토리)
```

위 폴더 이름과 상대 위치는 고정입니다. (`blog.workspace` 기준으로 `../blog.backend`, `../blog.frontend`)

---

## 🚀 주요 명령어 (Makefile)

### 🧱 컨테이너 제어

| 명령어 | 설명 |
|--------|------|
| `make up` | 로컬 컨테이너 실행 (Octane :4000) |
| `make down` | 로컬 컨테이너 중지 및 정리 |
| `make restart-all` | 모든 컨테이너 재시작 |
| `make build` | 이미지 캐시 없이 재빌드 |
| `make status` | 컨테이너, 환경, env 상태 요약 표시 |
| `make check-docker` | Docker 런타임 연결 상태 확인 |

---

### 🔐 환경 파일 관리 (.env)

#### Local

| 명령어 | 설명 |
|--------|------|
| `make env-encrypt-local` | docker/backend/frontend `.env → .env.local.enc` 암호화 |
| `make decrypt-docker-local` | docker `.env.local.enc → .env` 복호화 |
| `make decrypt-backend-local` | backend `.env.local.enc → .env` 복호화 |
| `make decrypt-frontend-local` | frontend `.env.local.enc → .env` 복호화 |

#### Common

| 명령어 | 설명 |
|--------|------|
| `make backup-env` | 암호화된 local env 파일 백업용. 운영 env에는 사용하지 않음 |

🔑 로컬 암호화 키는 macOS `~/.zshrc` 에 설정:
```bash
export BLOG_ENV_LOCAL_SECRET="$(openssl rand -base64 48)"
```

운영 env 암호화 키는 로컬 키와 분리합니다. 문서, 저장소, iCloud 동기화 폴더에 남기지 말고 배포 작업을 수행하는 셸에서만 주입합니다.

```bash
export BLOG_ENV_PRODUCTION_SECRET="<password-manager-or-secrets-manager-value>"
```

이미 공유된 `BLOG_ENV_SECRET` 또는 같은 키로 암호화된 `.env.production.enc`가 있었다면 유출된 것으로 보고 폐기합니다. 새 운영 env는 새 `APP_KEY`, DB 비밀번호, 관리자 비밀번호, AWS 키를 발급한 뒤 `BLOG_ENV_PRODUCTION_SECRET`로 다시 암호화합니다.

---

### ⚙️ Laravel 명령어

| 명령어 | 설명 |
|--------|------|
| `make migrate` | DB 마이그레이션 실행 |
| `make seed` | DB 시더 실행 |
| `make sh-laravel` | Laravel 컨테이너 접속 |
| `make sh-nextjs` | Next.js 컨테이너 접속 |

---

### 📜 Laravel 로그 관리

| 명령어 | 설명 |
|--------|------|
| `make laravel-log` | Laravel 로그 마지막 50줄 출력 |
| `make laravel-log tail=100` | 마지막 100줄 출력 |
| `make laravel-log follow=true` | 실시간 로그 보기 (Ctrl+C 종료) |
| `make laravel-log-clear` | Laravel 로그 파일 초기화 |
| `make laravel-log-error` | `ERROR`만 필터링 출력 |

예시:
```bash
make laravel-log tail=100 follow=true
```

---

### ☁️ iCloud 백업 경로

```
~/Library/Mobile Documents/com~apple~CloudDocs/blog_envs/
```

이 디렉토리에는 로컬 개발용 `.env.local.enc`만 백업합니다. 운영용 `.env.production.enc`는 iCloud 동기화 대상에 두지 않습니다.

---

## 🧩 상태 확인 (Status 예시)

```bash
make status
```

출력 예시:

```
🟢 Docker Containers:
  - <project>-laravel-1   running
  - <project>-nextjs-1    running
  - <project>-mariadb-1   running

⚙️ Environment Summary:
Backend .env → ../blog.backend/.env (updated: 2025-10-10)
Frontend .env → ../blog.frontend/.env (updated: 2025-10-10)

🧩 PHP APP_ENV: local
🧩 Node NODE_ENV: development
```

---

## 🧰 개발 환경 요구사항

- macOS (zsh 환경)
- Docker 호환 런타임 + Docker CLI
- Make (macOS 기본 내장)
- OpenSSL (`brew install openssl`)

---

## ✅ 초기 세팅 순서

1. `blog.workspace/.env.local.enc`, `blog.backend/.env.local.enc`, `blog.frontend/.env.local.enc` 준비
2. `~/.zshrc` 에 `BLOG_ENV_LOCAL_SECRET` 추가 후 `source ~/.zshrc`
3. 시스템에서 Docker 호환 런타임 실행
4. `cd blog.workspace`
5. `make up`
6. 브라우저에서 `http://localhost:3000` (frontend), `http://localhost:4000` (backend) 확인

---

## ☁️ AWS EC2 배포

상용 배포는 EC2 직접 배포 기준으로 진행합니다.

1. 서버 접속 직후 timezone을 `Asia/Seoul`로 설정
2. EC2 보안 그룹에서 `22/tcp`, `80/tcp`, `443/tcp`를 열기
3. 서버에 `Nginx`, `mariadb`, `PHP 8.3`, `Node 20`, `PM2`, `Certbot` 설치
4. 서버에 `backend`, `frontend` 저장소 배치
5. 프로덕션 환경 변수 반영
6. `systemd`, `PM2`, `Nginx` 설정 적용
7. HTTPS 발급 후 헬스체크 확인

현재 운영 기준은 `/var/www/jaubi.co.kr/blog/{blog.backend,blog.frontend}` 구조와 `Laravel Octane/systemd + Next.js/PM2(nvm) + Nginx + Certbot` 입니다.

상세 절차는 [docs/aws-ec2.md](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/docs/aws-ec2.md) 를 참고하세요.
빠른 순서 확인은 [docs/production-deployment-checklist.md](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/docs/production-deployment-checklist.md) 를 참고하세요.

---

## 📦 관련 디렉토리

| 디렉토리 | 설명 |
|-----------|------|
| `blog.backend` | Laravel 11.x |
| `blog.frontend` | Next.js 14 |
| `blog.workspace` | 공용 개발/배포 워크스페이스 |
| `scripts/` | 초기화 및 유틸 스크립트 |
| `Makefile` | 전반적 제어 중심 |

---

🧡 Created with love by **ChatGPT + sm**
