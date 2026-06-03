# 🧰 Blog Workspace Development Environment

Laravel (Backend) + Next.js (Frontend) + MariaDB
로컬 개발을 위한 Docker 환경입니다. `.env` 파일은 예시 파일을 기준으로 각 환경에서 직접 작성하고 Git에 커밋하지 않습니다.

현재 workspace 로컬 Laravel 런타임 이미지는 `PHP 8.5.4` 와 `Swoole 6.2.1` 기준입니다.

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

### 환경 파일 관리 (.env)

`.env` 파일은 자동 생성하지 않습니다. 값이 변경될 때마다 아래 예시 파일을 기준으로 각 환경의 `.env`를 직접 수정합니다.

| 위치 | 기준 파일 | 실제 파일 |
|--------|------|------|
| workspace | `.env.example` | `blog.workspace/.env` |
| backend | `blog.backend/.env.example` | `blog.backend/.env` |
| frontend | `blog.frontend/.env.local.example` | `blog.frontend/.env` |

운영 환경 변수는 서버의 실제 `.env` 또는 별도 Secret Manager에서만 관리합니다. 실제 환경 파일, 운영 키, 비밀번호는 Git, 문서, 동기화 폴더에 두지 않습니다.

로컬 Laravel 이미지 관련 기본값:

| 변수 | 기본값 | 설명 |
|--------|------|------|
| `PHP_CLI_BASE_IMAGE` | `php:8.5.4-cli-alpine` | 로컬 Octane CLI 베이스 |
| `PHP_SWOOLE_VERSION` | `6.2.1` | workspace Laravel 이미지에서 설치하는 Swoole 버전 |

---

### ⚙️ Laravel 명령어

| 명령어 | 설명 |
|--------|------|
| `make migrate` | DB 마이그레이션 실행 |
| `make seed` | DB 시더 실행 |
| `make sh-backend` | Backend 컨테이너 접속 |
| `make sh-frontend` | Frontend 컨테이너 접속 |

---

### 📜 Laravel 로그 관리

| 명령어 | 설명 |
|--------|------|
| `make backend-log-clear` | Backend 로그 파일 초기화 |
| `make backend-log-error` | `ERROR`만 필터링 출력 |

---

## 🧩 상태 확인 (Status 예시)

```bash
make status
```

출력 예시:

```
🟢 Docker Containers:
  - <project>-backend-1    running
  - <project>-frontend-1   running
  - <project>-database-1   running

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

---

## ✅ 초기 세팅 순서

1. `blog.workspace/.env.example`을 참고해 `blog.workspace/.env`를 직접 작성
2. `blog.backend/.env.example`을 참고해 `blog.backend/.env`를 직접 작성
3. `blog.frontend/.env.local.example`을 참고해 `blog.frontend/.env`를 직접 작성
4. 시스템에서 Docker 호환 런타임 실행
5. `cd blog.workspace`
6. `make up`
7. 브라우저에서 `http://localhost:3000` (frontend), `http://localhost:4000` (backend) 확인

---

## ☁️ AWS EC2 배포

상용 배포 문서는 이 워크스페이스에서 관리하고, 실제 배포 로직은 서버 `/opt/deploy/blog/*.sh` 에 둡니다. 로컬에서는 `make deploy-*` 명령으로 SSH 호출하는 방식을 기본 진입점으로 사용합니다.

- 상세 운영 가이드: [docs/aws-ec2.md](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/docs/aws-ec2.md)
- 빠른 실행 체크리스트: [docs/production-deployment-checklist.md](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/docs/production-deployment-checklist.md)
- 운영 기준: `backend`, `frontend` 모두 서버 저장소의 `main` 브랜치만 pull 해서 배포하며, 둘 다 반영할 때는 `backend -> frontend` 순서로 진행
- 기본 명령: `make deploy-sync`, `make deploy-backend`, `make deploy-frontend`, `make deploy-all`, `make deploy-status`
- 배포 성공 후 로컬 래퍼가 `../blog.backend`, `../blog.frontend` 에 `deploy/prod/<app>/<timestamp>` Git tag를 생성하고 `origin` 으로 push
- PM2 실행 기준 파일: `blog.frontend/ecosystem.config.cjs`
- `scripts/deploy-prod.sh` 는 `make deploy-*` 가 호출하는 내부 래퍼이며, 필요하면 서버에서 `/opt/deploy/blog/*.sh` 를 직접 실행할 수도 있음. 다만 Git tag 자동 생성은 로컬 `make deploy-*` 경로에서만 수행됨

---

## 📦 관련 디렉토리

| 디렉토리 | 설명 |
|-----------|------|
| `blog.backend` | Laravel 11.x |
| `blog.frontend` | Next.js 14 |
| `blog.workspace` | 공용 개발/배포 워크스페이스 |
| `Makefile` | 전반적 제어 중심 |

---

🧡 Created with love by **ChatGPT + sm**
