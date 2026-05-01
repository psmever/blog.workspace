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
| `make colima` | Colima 런타임 자동 실행(이미 켜져 있으면 상태만 표시) |
| `make colima-start` | `~/.colima/default/config.yaml` 기반으로 Colima 실행 |
| `make colima-start-custom` | 환경변수로 지정한 리소스로 Colima 수동 실행 |
| `make colima-status` | Colima 현재 상태 출력 |
| `make colima-stop` | Colima 종료 |
| `make up` | 로컬 컨테이너 실행 (Octane :4000) |
| `make down` | 로컬 컨테이너 중지 및 정리 |
| `make restart-docker` | Docker(Colima) 런타임 재시작 |
| `make restart-all` | Docker 재시작 후 모든 컨테이너 재시작 |
| `make build` | 이미지 캐시 없이 재빌드 |
| `make status` | 컨테이너, 환경, env 상태 요약 표시 |

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
- Colima + Docker CLI (`brew install colima docker docker-compose`)
- Make (macOS 기본 내장)
- OpenSSL (`brew install openssl`)

---

## 🐧 Colima 기반 Docker 런타임

며칠 전부터 Docker Desktop 대신 [Colima](https://github.com/abiosoft/colima)를 사용하도록 환경을 전환했습니다. `docker compose` 명령 자체는 그대로지만, Colima가 백그라운드에서 Docker 데몬을 제공하므로 make 명령을 실행하기 전에 Colima가 켜져 있어야 합니다.

### 설치

```bash
brew install colima docker docker-compose
```

### 실행 / 상태 / 종료

```bash
colima start --cpu 4 --memory 8 --disk 60   # 자원 값은 필요에 맞게 조정
colima status
colima stop
```

필요 시 `colima nerdctl` 등을 활용해 개별 VM 자원을 재조정할 수 있으며, Colima가 실행 중일 때만 `make up` 명령이 정상 동작합니다.

### Makefile 헬퍼

Colima 제어용 Make 타겟을 제공하여 반복 작업을 줄일 수 있습니다.

- `make colima` : Colima가 꺼져 있으면 config 기반 `colima start` 실행 후 상태 표시, 켜져 있으면 상태만 표시
- `make colima-start` : `~/.colima/default/config.yaml` 설정대로 Colima 실행
- `make colima-start-custom` : `COLIMA_CPU`/`COLIMA_MEMORY`/`COLIMA_DISK` 값으로 리소스를 지정해 Colima 실행
- `make colima-status` : 현재 상태만 빠르게 확인
- `make colima-stop` : Colima 종료

커스텀 시작(target `colima-start-custom`)은 환경변수를 통해 리소스를 조절합니다. 기본값은 4·8·60이지만 필요 시 다음처럼 조정할 수 있습니다.

```bash
COLIMA_CPU=6 COLIMA_MEMORY=16 COLIMA_DISK=80 make colima-start-custom
```

---

## ✅ 초기 세팅 순서

1. `blog.docker/.env.local.enc`, `blog.backend/.env.local.enc`, `blog.frontend/.env.local.enc` 준비
2. `~/.zshrc` 에 `BLOG_ENV_SECRET` 추가 후 `source ~/.zshrc`
3. `colima start` 로 Docker 런타임 실행 (최초 실행 후 계속 켜두면 됨)
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
