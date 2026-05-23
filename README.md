# 🧰 Blog Workspace Development Environment

Laravel (Backend) + Next.js (Frontend) + MariaDB
로컬 개발을 위한 Docker 환경입니다. `.env` 파일은 예시 파일을 기준으로 각 환경에서 직접 작성하고 Git에 커밋하지 않습니다.

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
| `Makefile` | 전반적 제어 중심 |

---

🧡 Created with love by **ChatGPT + sm**
