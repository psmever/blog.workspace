# ===============================
# 🧰 Blog Workspace Makefile (Local Dev, v7: Octane BG + Attach)
# ===============================

# Docker Compose Wrapper
# (v2가 없으면 v1 명령으로 fallback)
DC = $(shell if docker compose version >/dev/null 2>&1; then echo "docker compose"; else echo "docker-compose"; fi)
COMPOSE_FILE = ./docker-compose.yml
DOCKER_BUILD_ENV = DOCKER_BUILDKIT=0 COMPOSE_DOCKER_CLI_BUILD=0
BACKEND_DIR = ../blog.backend
FRONTEND_DIR = ../blog.frontend
ARTISAN_GOALS := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
ARTISAN_CMD := $(strip $(if $(CMD),$(CMD),$(ARTISAN_GOALS)))
DEPLOY_SCRIPT = ./scripts/deploy-prod.sh
.DEFAULT_GOAL := help

.PHONY: check-docker check-env-files check-repos \
        up down \
        build build-images clean reset-project \
        sh-laravel sh-nextjs artisan migrate seed yarn \
        logs laravel-log-clear laravel-log-error \
        restart-all \
        restart-laravel restart-nextjs restart-mariadb \
        status verify-env help \
        deploy-sync deploy-backend deploy-frontend deploy-all deploy-status

ifeq ($(firstword $(MAKECMDGOALS)),artisan)
%:
	@:
endif

help:
	@echo "📚 Blog Workspace 환경 명령어 안내"
	@echo "──────────────────────────────────────────────"
	@echo "🎬 실행 및 종료:"
	@echo "  make up                → 로컬 컨테이너 실행 (Octane :4000)"
	@echo "  make down              → 로컬 컨테이너 중지 및 정리"
	@echo ""
	@echo "🔁 재시작:"
	@echo "  make restart-all         → 모든 컨테이너 재시작"
	@echo "  make restart-nextjs      → Next.js 컨테이너 재시작"
	@echo "  make restart-laravel     → Laravel 컨테이너 재시작"
	@echo "  make restart-mariadb     → MariaDB 컨테이너 재시작"
	@echo ""
	@echo "🧹 빌드 및 정리:"
	@echo "  make reset-project      → 모든 컨테이너/볼륨 정리"
	@echo "  make build              → 로컬 이미지 재빌드 후 migrate/seed 실행"
	@echo "  make clean              → 모든 컨테이너/볼륨 정리"
	@echo ""
	@echo "🧩 개발 유틸리티:"
	@echo "  make artisan route:list      → Laravel Artisan 임의 명령 실행"
	@echo "  make artisan CMD=\"route:list\" → 기존 방식도 계속 사용 가능"
	@echo "  make migrate            → Laravel 마이그레이션 실행"
	@echo "  make seed               → DB 시드 실행"
	@echo "  make yarn               → Next.js 패키지 설치"
	@echo "  make sh-laravel         → Laravel 컨테이너 쉘 접속"
	@echo "  make sh-nextjs          → Next.js 컨테이너 쉘 접속"
	@echo ""
	@echo "📜 로그:"
	@echo "  make logs             → docker-compose 전체 로그 출력 (SERVICE=이름 으로 단일 서비스 지정 가능)"
	@echo "  make laravel-log-clear  → Octane 로그 초기화"
	@echo "  make laravel-log-error  → Octane 로그에서 ERROR 검색"
	@echo ""
	@echo "🧠 상태:"
	@echo "  make check-docker     → Docker 런타임 연결 상태 확인"
	@echo "  make check-env-files  → 수동 관리 .env 파일 존재 확인"
	@echo "  make verify-env         → 컨테이너 환경변수 확인"
	@echo "  make status             → 도커 상태 리포트"
	@echo "  make check-repos        → 필수 repo 경로 확인"
	@echo ""
	@echo "☁️ 상용 배포:"
	@echo "  make deploy-sync       → 서버 /opt/deploy/blog 배포 스크립트 동기화"
	@echo "  make deploy-backend    → 서버 blog.backend main 브랜치 pull 배포"
	@echo "  make deploy-frontend   → 서버 blog.frontend main 브랜치 pull 배포"
	@echo "  make deploy-all        → backend -> frontend 순서로 main 브랜치 배포"
	@echo "  make deploy-status     → 서버 마지막 배포 상태/헬스체크 확인"
	@echo ""
	@echo "👉 원하는 명령어를 make 뒤에 입력하세요. (예: make up)"

# ===============================
# ✅ Preflight Checks
# ===============================

check-docker:
	@if ! command -v docker >/dev/null 2>&1; then \
		echo "❌ Docker CLI를 찾을 수 없습니다."; \
		echo "   시스템에 Docker 호환 런타임과 Docker CLI를 설치한 뒤 다시 실행하세요."; \
		exit 1; \
	fi
	@if ! docker compose version >/dev/null 2>&1 && ! command -v docker-compose >/dev/null 2>&1; then \
		echo "❌ docker compose 또는 docker-compose를 찾을 수 없습니다."; \
		echo "   Docker Compose를 사용할 수 있는 환경인지 확인하세요."; \
		exit 1; \
	fi
	@if ! docker info >/dev/null 2>&1; then \
		echo "❌ Docker daemon에 연결할 수 없습니다."; \
		echo "   시스템에서 Docker 호환 런타임을 실행한 뒤 다시 시도하세요."; \
		exit 1; \
	fi
	@echo "✅ Docker runtime is available."

check-repos:
	@if [ ! -d "$(BACKEND_DIR)" ]; then \
		echo "❌ 백엔드 경로가 없습니다: $(BACKEND_DIR)"; \
		exit 1; \
	fi

check-env-files:
	@if [ ! -f ./.env ]; then \
		echo "❌ workspace .env 파일이 없습니다. .env.example을 참고해 직접 작성하세요."; \
		exit 1; \
	fi
	@if [ ! -f "$(BACKEND_DIR)/.env" ]; then \
		echo "❌ backend .env 파일이 없습니다. $(BACKEND_DIR)/.env.example을 참고해 직접 작성하세요."; \
		exit 1; \
	fi
	@if [ ! -f "$(FRONTEND_DIR)/.env" ]; then \
		echo "❌ frontend .env 파일이 없습니다. $(FRONTEND_DIR)/.env.local.example을 참고해 직접 작성하세요."; \
		exit 1; \
	fi
	@if [ ! -d "$(FRONTEND_DIR)" ]; then \
		echo "❌ 프런트 경로가 없습니다: $(FRONTEND_DIR)"; \
		exit 1; \
	fi

# ===============================
# 🚀 UP / DOWN
# ===============================

up:
	@echo "🚀 Starting LOCAL containers (Octane direct on :4000)..."
	@$(MAKE) check-docker
	@$(MAKE) check-repos
	@$(MAKE) check-env-files
	$(DOCKER_BUILD_ENV) APP_ENV=local NODE_ENV=development $(DC) -f $(COMPOSE_FILE) up -d --build
	@echo "✅ Local containers running (Octane direct on :4000)"

down:
	@echo "🛑 Stopping LOCAL containers..."
	$(DC) -f $(COMPOSE_FILE) down -v
	@echo "✅ Local containers stopped."

# ===============================
# 🔁 Restart
# ===============================

restart-all:
	@echo "🔄 Restarting ALL containers..."
	@$(MAKE) check-docker
	$(DC) -f $(COMPOSE_FILE) restart
	@echo "✅ All containers restarted."

restart-nextjs:
	@echo "🔄 Restarting Next.js container..."
	$(DC) -f $(COMPOSE_FILE) restart nextjs
	@echo "✅ Next.js restarted."

restart-laravel:
	@echo "🔄 Restarting Laravel container..."
	$(DC) -f $(COMPOSE_FILE) restart laravel
	@echo "✅ Laravel restarted."

restart-mariadb:
	@echo "🔄 Restarting MariaDB container..."
	$(DC) -f $(COMPOSE_FILE) restart mariadb
	@echo "✅ MariaDB restarted."

# ===============================
# 🧩 Build / Clean / Reset
# ===============================

build-images:
	@echo "🔧 Building Docker images..."
	@$(MAKE) check-docker
	$(DOCKER_BUILD_ENV) $(DC) -f $(COMPOSE_FILE) build --no-cache

build:
	@$(MAKE) build-images
	@echo "🗄️ Running migrations..."
	@$(MAKE) migrate
	@echo "🌱 Running seeders..."
	@$(MAKE) seed

clean:
	@echo "🧹 Cleaning environment..."
	$(DC) -f $(COMPOSE_FILE) down -v || true
	@echo "✅ Clean complete."

reset-project:
	@echo "♻️ Resetting this project..."
	@$(MAKE) clean
	@echo "✅ Project reset complete."

# ===============================
# 🧩 Laravel / Next.js Utilities
# ===============================

artisan:
	@if [ -z "$(ARTISAN_CMD)" ]; then \
		echo "❌ 사용법: make artisan route:list"; \
		echo "   또는: make artisan CMD=\"route:list\""; \
		exit 1; \
	fi
	./scripts/artisan.sh $(ARTISAN_CMD)

migrate:
	./scripts/artisan.sh migrate

seed:
	./scripts/artisan.sh db:seed

yarn:
	./scripts/yarn.sh

# ✅ Laravel attach 모드 (Octane 백그라운드 호환)
sh-laravel:
	@if [ -z "$$($(DC) -f $(COMPOSE_FILE) ps -q laravel)" ]; then \
		echo "⚙️ Laravel container not running — starting..."; \
		$(DC) -f $(COMPOSE_FILE) up -d laravel; \
	fi
	@echo "🧩 Attaching to Laravel container shell..."
	$(DC) -f $(COMPOSE_FILE) exec -it laravel /bin/sh || true

sh-nextjs:
	$(DC) -f $(COMPOSE_FILE) exec nextjs sh

# ===============================
# 📜 Laravel Log Commands
# ===============================

logs:
	@if [ -n "$$SERVICE" ]; then \
		echo "🧾 Viewing docker compose logs for service: $$SERVICE..."; \
		$(DC) -f $(COMPOSE_FILE) logs -f --tail=all $$SERVICE; \
	else \
		echo "🧾 Viewing full docker compose logs for all services..."; \
		$(DC) -f $(COMPOSE_FILE) logs -f --tail=all; \
	fi

laravel-log-clear:
	@$(DC) -f $(COMPOSE_FILE) exec laravel sh -c "echo '' > /var/log/octane.log"
	@echo "✅ Octane log cleared."

laravel-log-error:
	@$(DC) -f $(COMPOSE_FILE) exec laravel sh -c "grep -i 'ERROR' /var/log/octane.log || echo 'No errors found ✅'"

# ===============================
# 🧠 System Status
# ===============================

verify-env:
	@echo "\n🧠 Verifying Environment Variables..."
	-@$(DC) -f $(COMPOSE_FILE) exec laravel printenv | grep APP_ENV || echo "⚠️ Laravel not running."
	-@$(DC) -f $(COMPOSE_FILE) exec nextjs printenv | grep NODE_ENV || echo "⚠️ Next.js not running."
	@echo "✅ Environment 확인 완료."

status:
	@$(MAKE) check-docker
	@echo "\n🌍 BLOG SYSTEM STATUS REPORT"
	@echo "──────────────────────────────────────────────"
	@echo "📦 Docker Containers:"
	@docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
	@echo "\n⚙️ Environment Summary:"
	@echo "Backend .env →"
	@[ -f $(BACKEND_DIR)/.env ] && stat -f "%N (updated: %SB)" -t "%Y-%m-%d %H:%M" $(BACKEND_DIR)/.env || echo "❌ Not Found"
	@echo "Frontend .env →"
	@[ -f $(FRONTEND_DIR)/.env ] && stat -f "%N (updated: %SB)" -t "%Y-%m-%d %H:%M" $(FRONTEND_DIR)/.env || echo "❌ Not Found"
	@echo "──────────────────────────────────────────────"

# ===============================
# ☁️ Production Deploy
# ===============================

deploy-sync:
	$(DEPLOY_SCRIPT) sync

deploy-backend:
	$(DEPLOY_SCRIPT) backend

deploy-frontend:
	$(DEPLOY_SCRIPT) frontend

deploy-all:
	$(DEPLOY_SCRIPT) all

deploy-status:
	$(DEPLOY_SCRIPT) status
