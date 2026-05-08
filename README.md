# 🐳 Blog Docker Development Environment

Laravel (Backend) + Next.js (Frontend) + MariaDB
로컬 개발을 위한 Docker 환경이며, `.env` 파일을 암호화하여 관리할 수 있습니다.

---

## 📂 디렉토리 구조

```
blog/
├── blog.backend/       # Laravel 백엔드
├── blog.frontend/      # Next.js 프론트엔드
└── blog.docker/        # Docker 설정 및 관리 (현재 디렉토리)
```

위 폴더 이름과 상대 위치는 고정입니다. (`blog.docker` 기준으로 `../blog.backend`, `../blog.frontend`)

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

#### Production

| 명령어 | 설명 |
|--------|------|
| `make env-encrypt-production` | backend/frontend `.env → .env.production.enc` 암호화 |
| `make decrypt-backend-production` | backend `.env.production.enc → .env` 복호화 |
| `make decrypt-frontend-production` | frontend `.env.production.enc → .env` 복호화 |

#### Common

| 명령어 | 설명 |
|--------|------|
| `make backup-env` | 암호화된 env 파일을 iCloud에 백업 |

🔑 암호화 키는 macOS `~/.zshrc` 에 설정:
```bash
export BLOG_ENV_SECRET="EKckuME1QJavOkoLE3ZlMOeqz8Kxzi4Jje7vyvms1s8="
```

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

이 디렉토리에 `.env.*.enc` 파일이 자동 백업됩니다.

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

1. `blog.docker/.env.local.enc`, `blog.backend/.env.local.enc`, `blog.frontend/.env.local.enc` 준비
2. `~/.zshrc` 에 `BLOG_ENV_SECRET` 추가 후 `source ~/.zshrc`
3. 시스템에서 Docker 호환 런타임 실행
4. `cd blog.docker`
5. `make up`
6. 브라우저에서 `http://localhost:3000` (frontend), `http://localhost:4000` (backend) 확인

---

## 📦 관련 디렉토리

| 디렉토리 | 설명 |
|-----------|------|
| `blog.backend` | Laravel 11.x |
| `blog.frontend` | Next.js 14 |
| `blog.docker` | Docker Compose 환경 |
| `scripts/` | 초기화 및 유틸 스크립트 |
| `Makefile` | 전반적 제어 중심 |

---

🧡 Created with love by **ChatGPT + sm**
