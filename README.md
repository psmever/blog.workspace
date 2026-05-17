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
| `make prod-up` | 프로덕션 컨테이너 실행 (Nginx :80) |
| `make prod-down` | 프로덕션 컨테이너 중지 |
| `make restart-all` | 모든 컨테이너 재시작 |
| `make build` | 이미지 캐시 없이 재빌드 |
| `make prod-build` | 프로덕션 이미지 재빌드 |
| `make status` | 컨테이너, 환경, env 상태 요약 표시 |
| `make prod-status` | 프로덕션 compose 상태 표시 |
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
| `make env-encrypt-production` | docker/backend/frontend `.env → .env.production.enc` 암호화 |
| `make decrypt-docker-production` | docker `.env.production.enc → .env` 복호화 |
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
| `make prod-logs` | 프로덕션 Docker Compose 로그 보기 |

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

1. `blog.workspace/.env.local.enc`, `blog.backend/.env.local.enc`, `blog.frontend/.env.local.enc` 준비
2. `~/.zshrc` 에 `BLOG_ENV_SECRET` 추가 후 `source ~/.zshrc`
3. 시스템에서 Docker 호환 런타임 실행
4. `cd blog.workspace`
5. `make up`
6. 브라우저에서 `http://localhost:3000` (frontend), `http://localhost:4000` (backend) 확인

---

## ☁️ AWS EC2 배포

프로덕션 배포용 구성은 `docker-compose.prod.yml` 기준입니다.

1. EC2 보안 그룹에서 `22/tcp`, `80/tcp`를 열기
2. 인스턴스에 Docker Engine + Docker Compose Plugin 설치
3. 서버에 `blog.backend`, `blog.frontend`, `blog.workspace`를 같은 부모 디렉터리에 clone
4. 로컬에서 `blog.workspace/.env`, `blog.backend/.env`, `blog.frontend/.env`를 프로덕션 값으로 만든 뒤 `make env-encrypt-production`
5. 서버에 `BLOG_ENV_SECRET` 설정
6. `cd blog.workspace && make prod-up`
7. `curl http://<퍼블릭IP>/api/health` 로 확인

상세 절차는 [docs/aws-ec2.md](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/docs/aws-ec2.md) 를 참고하세요.

Docker 없이 EC2에 직접 배포할 경우에는 [docs/aws-ec2-no-docker.md](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/docs/aws-ec2-no-docker.md) 를 참고하세요.
현재 상용 기준은 `/var/www/jaubi.co.kr/blog/{backend,frontend}` 구조와 `Laravel Octane/systemd + Next.js/PM2(nvm) + Nginx + Certbot` 입니다.

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
