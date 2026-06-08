# Workspace 저장소 가이드

## 기본 원칙

- 모든 대화와 작업 보고는 한글로 작성한다.
- 이 저장소는 공용 개발 환경, Docker Compose, Makefile, 배포 문서, 보조 스크립트 전용이다.
- 애플리케이션 기능 수정은 기본적으로 여기서 하지 않는다.
  - Laravel 코드 수정: `../blog.backend`
  - Next.js 코드 수정: `../blog.frontend`
- 이 프로젝트 채팅은 조정 및 인프라 전용으로 운영한다.
- 이 프로젝트 채팅에서는 `../blog.backend`, `../blog.frontend` 코드를 직접 수정하지 않는다.
- 사용자가 백엔드 또는 프런트 수정 요청을 하면, 실제 수정 대신 해당 프로젝트 채팅에서 작업하라고 안내한다.

## 작업 범위

- 수정 대상:
  - `Makefile`
  - `docker-compose.yml`
  - `scripts/`
  - `deploy/`
  - `docs/`
  - `nginx/`, `php/`, `node/`, `mariadb/`
- 기본적으로 수정하지 않는 대상:
  - `../blog.backend` 애플리케이션 코드
  - `../blog.frontend` 애플리케이션 코드

## 자주 쓰는 명령

- 로컬 컨테이너 시작: `make up`
- 로컬 컨테이너 중지: `make down`
- 상태 확인: `make status`
- 이미지 빌드 + 마이그레이션 + 시드: `make docker-build`
- 컨테이너/볼륨 정리: `make docker-clean`
- 마이그레이션: `make migrate`
- 시더 실행: `make seed`
- Backend 셸 접속: `make sh-backend`
- Frontend 셸 접속: `make sh-frontend`
- Artisan 직접 실행: `./scripts/artisan.sh route:list`
- Yarn 직접 실행: `./scripts/yarn.sh lint`

## 운영 규칙

- 환경 제어, 배포, 컨테이너, 공용 문서 변경만 이 저장소에서 처리한다.
- 백엔드/프런트 코드 변경이 필요하면 해당 저장소로 이동해서 수정한다.
- 여러 저장소에 걸친 작업이어도 소스 수정, Git 커밋, Git 푸시는 저장소별로 각각 분리한다.
- 다른 저장소 변경을 현재 저장소 작업에 섞어서 수정하거나, 한 커밋/한 푸시로 함께 처리하지 않는다.
- 루트 `../AGENTS.md`, `../PROJECT_MAP.md`의 템플릿 원본은 개인 Git 경로 `/Users/sm/Workspaces/System/private_configure/myproject/myblog`에서 관리한다.
- 여러 PC에서는 개인 Git 저장소의 `myproject/myblog` 내용을 기준으로 루트 Codex 파일을 직접 동기화한다.
- 사용자가 이 채팅에서 백엔드/프런트 코드 수정을 요청해도 여기서는 수정하지 않는다.
- 안내 문구는 명확하게 작성한다.
  - 백엔드 요청: `이 작업은 Blog Backend 프로젝트 채팅에서 요청해주세요.`
  - 프런트 요청: `이 작업은 Blog Frontend 프로젝트 채팅에서 요청해주세요.`
  - 둘 다 필요한 요청: `Backend와 Frontend 채팅에 나눠서 각각 요청해주세요.`

## 안전 규칙

- `.env`, `.env.*`, `*.enc` 파일은 꼭 필요한 경우에만 열람하거나 수정한다.
- 암복호화나 배포 스크립트 변경 시 영향 범위를 먼저 명시한다.
- `Makefile` 또는 `docker-compose` 변경 시 로컬 개발 흐름이 깨지지 않는지 확인한다.
- 새 Git 브랜치를 만들기 전에는 먼저 사용자에게 확인한다.
- 브랜치 생성이 필요하다고 판단되면 이유와 대상 브랜치를 짧게 설명한 뒤 진행 여부를 묻는다.

## 검증 기준

- Docker 관련 변경 후에는 최소한 `make status` 기준 흐름을 확인한다.
- 스크립트 변경 후에는 대상 명령 1회 이상 직접 실행해 본다.
- 배포 문서 변경은 실제 경로와 명령어 표기가 현재 구조와 일치하는지 검토한다.

## 커밋 규칙

- 커밋 메시지는 짧은 한 줄 한국어 요약을 우선한다.
- 워크스페이스 변경만 담긴 커밋을 유지하고, 백엔드/프런트 코드 변경과 섞지 않는다.
- 워크스페이스 저장소에서의 커밋과 푸시는 이 저장소 변경만 대상으로 하고, 다른 저장소 작업은 해당 저장소에서 별도로 처리한다.
