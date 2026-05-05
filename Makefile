# ===============================
# 🐳 Blog Docker Makefile (Local Dev, v7: Octane BG + Attach)
# ===============================

# Colima / macOS 호환 Compose Wrapper
# (v2가 없으면 v1 명령으로 fallback)
DC = $(shell if docker compose version >/dev/null 2>&1; then echo "docker compose"; else echo "docker-compose"; fi)
COMPOSE_FILE = ./docker-compose.yml
DOCKER_BUILD_ENV = DOCKER_BUILDKIT=0 COMPOSE_DOCKER_CLI_BUILD=0
BACKEND_DIR = ../blog.backend
FRONTEND_DIR = ../blog.frontend
BLOG_ENV_SECRET ?= $(shell echo $$BLOG_ENV_SECRET)
COLIMA_CPU ?= 4
COLIMA_MEMORY ?= 8
COLIMA_DISK ?= 60
ARTISAN_GOALS := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
ARTISAN_CMD := $(strip $(if $(CMD),$(CMD),$(ARTISAN_GOALS)))
.DEFAULT_GOAL := help

.PHONY: colima colima-start colima-start-custom colima-status colima-stop \
        check-env-secret check-repos \
        up down \
        build clean reset-docker \
        sh-laravel sh-nextjs artisan migrate seed yarn \
        logs laravel-log-clear laravel-log-error \
        env-encrypt-local env-encrypt-production \
        decrypt-docker-local decrypt-backend-local decrypt-backend-production \
        decrypt-frontend-local decrypt-frontend-production \
        restart-docker restart-all \
        restart-laravel restart-nextjs restart-mariadb \
        status verify-env backup-env help

ifeq ($(firstword $(MAKECMDGOALS)),artisan)
%:
	@:
endif

help:
	@echo "📚 Blog Docker 환경 명령어 안내"
	@echo "──────────────────────────────────────────────"
	@echo "🧊 Colima Runtime:"
	@echo "  make colima             → Colima 자동 실행 (켜져있으면 상태만 표시)"
	@echo "  make colima-start       → config.yaml 기반 Colima 실행"
	@echo "  make colima-start-custom → 환경변수로 리소스 지정 후 실행"
	@echo "  make colima-status      → Colima 현재 상태 출력"
	@echo "  make colima-stop        → Colima 종료"
	@echo ""
	@echo "🎬 실행 및 종료:"
	@echo "  make up                → 로컬 컨테이너 실행 (Octane :4000)"
	@echo "  make down              → 로컬 컨테이너 중지 및 정리"
	@echo ""
	@echo "🔁 재시작:"
	@echo "  make restart-docker      → Docker(Colima) 런타임 재시작"
	@echo "  make restart-all         → Docker 재시작 후 모든 컨테이너 재시작"
	@echo "  make restart-nextjs      → Next.js 컨테이너 재시작"
	@echo "  make restart-laravel     → Laravel 컨테이너 재시작"
	@echo "  make restart-mariadb     → MariaDB 컨테이너 재시작"
	@echo ""
	@echo "🧹 빌드 및 정리:"
	@echo "  make build              → 로컬 이미지 재빌드"
	@echo "  make clean              → 모든 컨테이너/볼륨 정리"
	@echo "  make reset-docker       → 관련 이미지·볼륨·네트워크 초기화"
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
	@echo "  make logs             → docker-compose 로그 tail + Octane 로그 tail (기본: laravel compose 로그 제외, SERVICE=이름 으로 단일 서비스 지정 가능)"
	@echo "  make laravel-log-clear  → Octane 로그 초기화"
	@echo "  make laravel-log-error  → Octane 로그에서 ERROR 검색"
	@echo ""
	@echo "🔐 ENV 암·복호화:"
	@echo "  [LOCAL]"
	@echo "  make env-encrypt-local          → docker/backend/frontend .env → .env.local.enc"
	@echo "  make decrypt-docker-local       → docker .env.local.enc → .env"
	@echo "  make decrypt-backend-local      → backend .env.local.enc → .env"
	@echo "  make decrypt-frontend-local     → frontend .env.local.enc → .env"
	@echo ""
	@echo "  [PRODUCTION]"
	@echo "  make env-encrypt-production     → backend/frontend .env → .env.production.enc"
	@echo "  make decrypt-backend-production → backend .env.production.enc → .env"
	@echo "  make decrypt-frontend-production → frontend .env.production.enc → .env"
	@echo ""
	@echo "🧠 상태 및 백업:"
	@echo "  make verify-env         → 컨테이너 환경변수 확인"
	@echo "  make status             → 도커 상태 리포트"
	@echo "  make backup-env         → 암호화된 env 파일 iCloud 백업"
	@echo "  make check-repos        → 필수 repo 경로 확인"
	@echo "  make check-env-secret   → BLOG_ENV_SECRET 설정 확인"
	@echo ""
	@echo "👉 원하는 명령어를 make 뒤에 입력하세요. (예: make up)"

# ===============================
# 🧊 Colima Runtime Helpers
# ===============================

colima:
	@if colima status >/dev/null 2>&1; then \
		echo "✅ Colima already running. Showing status..."; \
		$(MAKE) colima-status; \
	else \
		echo "🚀 Colima not running. Booting up (config.yaml)..."; \
		$(MAKE) colima-start; \
		$(MAKE) colima-status; \
	fi

colima-start:
	@echo "🚀 Starting Colima using ~/.colima/default/config.yaml (colima start)..."
	@colima start
	@echo "✅ Colima start command finished."

colima-start-custom:
	@echo "🚀 Starting Colima with custom resources (cpu=$(COLIMA_CPU), memory=$(COLIMA_MEMORY)GB, disk=$(COLIMA_DISK)GB)..."
	@colima start --cpu $(COLIMA_CPU) --memory $(COLIMA_MEMORY) --disk $(COLIMA_DISK)
	@echo "✅ Colima custom start command finished."

colima-status:
	@echo "🧊 Checking Colima status..."
	@colima status || echo "⚠️ Colima가 실행 중이 아닙니다."

colima-stop:
	@echo "🛑 Stopping Colima..."
	@colima stop || echo "⚠️ Colima가 이미 중지 상태일 수 있습니다."
	@echo "✅ Colima stop command finished."

# ===============================
# ✅ Preflight Checks
# ===============================

check-env-secret:
	@if [ -z "$(BLOG_ENV_SECRET)" ]; then \
		echo "❌ BLOG_ENV_SECRET이 설정되어 있지 않습니다."; \
		echo "   ~/.zshrc에 export BLOG_ENV_SECRET=... 추가 후 다시 실행하세요."; \
		exit 1; \
	fi

check-repos:
	@if [ ! -d "$(BACKEND_DIR)" ]; then \
		echo "❌ 백엔드 경로가 없습니다: $(BACKEND_DIR)"; \
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
	@$(MAKE) check-repos
	$(MAKE) decrypt-docker-local
	$(MAKE) decrypt-backend-local
	$(MAKE) decrypt-frontend-local
	$(DOCKER_BUILD_ENV) APP_ENV=local NODE_ENV=development $(DC) -f $(COMPOSE_FILE) up -d --build
	@echo "✅ Local containers running (Octane direct on :4000)"

down:
	@echo "🛑 Stopping LOCAL containers..."
	$(DC) -f $(COMPOSE_FILE) down -v
	rm -f $(BACKEND_DIR)/.env $(FRONTEND_DIR)/.env
	@echo "✅ Local containers stopped."

# ===============================
# 🔁 Restart
# ===============================

restart-docker:
	@echo "♻️ Restarting Docker runtime (Colima)..."
	@if command -v colima >/dev/null 2>&1; then \
		if colima status >/dev/null 2>&1; then \
			colima restart || { echo "⚠️ colima restart failed, trying stop/start..."; colima stop && colima start; }; \
		else \
			echo "⚠️ Colima not running; starting Colima..."; \
			colima start; \
		fi; \
		echo "✅ Docker runtime ready."; \
	else \
		echo "⚠️ Colima not found. Skipping runtime restart."; \
	fi

restart-all:
	@echo "🔄 Restarting Docker runtime + ALL containers..."
	@$(MAKE) restart-docker
	$(DC) -f $(COMPOSE_FILE) restart
	@echo "✅ Docker runtime + all containers restarted."

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

build:
	@echo "🔧 Building Docker images..."
	$(DOCKER_BUILD_ENV) $(DC) -f $(COMPOSE_FILE) build --no-cache

clean:
	@echo "🧹 Cleaning environment..."
	$(DC) -f $(COMPOSE_FILE) down -v || true
	rm -f $(BACKEND_DIR)/.env $(FRONTEND_DIR)/.env
	@echo "✅ Clean complete."

reset-docker:
	@echo "🔥 Resetting all containers & images for this project..."
	@$(DC) -f $(COMPOSE_FILE) down -v --remove-orphans || true
	@docker image prune -af
	@docker volume prune -f
	@docker network prune -f
	@echo "✅ Docker environment reset complete."

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
		$(DC) -f $(COMPOSE_FILE) logs -f --tail=100 $$SERVICE; \
	else \
		excluded_service=laravel; \
		echo "🧾 Viewing docker compose logs for all services (excluding $$excluded_service) + Laravel Octane log..."; \
		services=$$($(DC) -f $(COMPOSE_FILE) config --services | grep -v "^$$excluded_service$$"); \
		laravel_container=$$($(DC) -f $(COMPOSE_FILE) ps -q laravel); \
		compose_pid=; \
		octane_pid=; \
		cleanup() { \
			test -n "$$compose_pid" && kill "$$compose_pid" 2>/dev/null || true; \
			test -n "$$octane_pid" && kill "$$octane_pid" 2>/dev/null || true; \
		}; \
		trap cleanup INT TERM EXIT; \
		if [ -n "$$services" ]; then \
			$(DC) -f $(COMPOSE_FILE) logs -f --tail=100 $$services & \
			compose_pid=$$!; \
		else \
			echo "⚠️ No services to tail after applying exclusion."; \
		fi; \
		if [ -n "$$laravel_container" ]; then \
			$(DC) -f $(COMPOSE_FILE) exec laravel sh -c "tail -n 50 -f /var/log/octane.log" & \
			octane_pid=$$!; \
		else \
			echo "⚠️ Laravel container not running. Skipping Octane log tail."; \
		fi; \
		if [ -z "$$compose_pid$$octane_pid" ]; then \
			echo "⚠️ No log sources available."; \
			exit 0; \
		fi; \
		wait; \
	fi

laravel-log-clear:
	@$(DC) -f $(COMPOSE_FILE) exec laravel sh -c "echo '' > /var/log/octane.log"
	@echo "✅ Octane log cleared."

laravel-log-error:
	@$(DC) -f $(COMPOSE_FILE) exec laravel sh -c "grep -i 'ERROR' /var/log/octane.log || echo 'No errors found ✅'"

# ===============================
# 🔐 Encrypt / Decrypt ENV
# ===============================

env-encrypt-local: check-env-secret
	@echo "🔐 Encrypting docker .env → .env.local.enc..."
	@if [ -f ./.env ]; then \
		openssl enc -aes-256-cbc -pbkdf2 -salt \
			-in ./.env -out ./.env.local.enc -k "$(BLOG_ENV_SECRET)"; \
		echo "✅ Docker .env.local.enc 생성 완료."; \
	else echo "⚠️  Docker .env not found."; fi
	@echo "🔐 Encrypting backend .env → .env.local.enc..."
	@if [ -f $(BACKEND_DIR)/.env ]; then \
		cd $(BACKEND_DIR) && openssl enc -aes-256-cbc -pbkdf2 -salt \
			-in .env -out .env.local.enc -k "$(BLOG_ENV_SECRET)"; \
		echo "✅ Backend .env.local.enc 생성 완료."; \
	else echo "⚠️  Backend .env not found."; fi
	@echo "🔐 Encrypting frontend .env → .env.local.enc..."
	@if [ -f $(FRONTEND_DIR)/.env ]; then \
		cd $(FRONTEND_DIR) && openssl enc -aes-256-cbc -pbkdf2 -salt \
			-in .env -out .env.local.enc -k "$(BLOG_ENV_SECRET)"; \
		echo "✅ Frontend .env.local.enc 생성 완료."; \
	else echo "⚠️  Frontend .env not found."; fi

env-encrypt-production: check-env-secret
	@echo "🔐 Encrypting backend .env → .env.production.enc..."
	@if [ -f $(BACKEND_DIR)/.env ]; then \
		cd $(BACKEND_DIR) && openssl enc -aes-256-cbc -pbkdf2 -salt \
			-in .env -out .env.production.enc -k "$(BLOG_ENV_SECRET)"; \
		echo "✅ Backend .env.production.enc 생성 완료."; \
	else echo "⚠️  Backend .env not found."; fi
	@echo "🔐 Encrypting frontend .env → .env.production.enc..."
	@if [ -f $(FRONTEND_DIR)/.env ]; then \
		cd $(FRONTEND_DIR) && openssl enc -aes-256-cbc -pbkdf2 -salt \
			-in .env -out .env.production.enc -k "$(BLOG_ENV_SECRET)"; \
		echo "✅ Frontend .env.production.enc 생성 완료."; \
	else echo "⚠️  Frontend .env not found."; fi

decrypt-docker-local: check-env-secret
	@echo "🔓 Decrypting docker .env.local.enc..."
	@if [ -f ./.env.local.enc ]; then \
		openssl enc -d -aes-256-cbc -pbkdf2 \
			-in ./.env.local.enc \
			-out ./.env -k "$(BLOG_ENV_SECRET)"; \
		echo "✅ Docker .env.local.enc 복호화 완료."; \
	else echo "⚠️  Docker .env.local.enc not found."; fi

decrypt-backend-local: check-env-secret
	@echo "🔓 Decrypting backend .env.local.enc..."
	@if [ -f $(BACKEND_DIR)/.env.local.enc ]; then \
		openssl enc -d -aes-256-cbc -pbkdf2 \
			-in $(BACKEND_DIR)/.env.local.enc \
			-out $(BACKEND_DIR)/.env -k "$(BLOG_ENV_SECRET)"; \
		echo "✅ Backend .env.local.enc 복호화 완료."; \
	else echo "⚠️  Backend .env.local.enc not found."; fi

decrypt-backend-production: check-env-secret
	@echo "🔓 Decrypting backend .env.production.enc..."
	@if [ -f $(BACKEND_DIR)/.env.production.enc ]; then \
		openssl enc -d -aes-256-cbc -pbkdf2 \
			-in $(BACKEND_DIR)/.env.production.enc \
			-out $(BACKEND_DIR)/.env -k "$(BLOG_ENV_SECRET)"; \
		echo "✅ Backend .env.production.enc 복호화 완료."; \
	else echo "⚠️  Backend .env.production.enc not found."; fi

decrypt-frontend-local: check-env-secret
	@echo "🔓 Decrypting frontend .env.local.enc..."
	@if [ -f $(FRONTEND_DIR)/.env.local.enc ]; then \
		openssl enc -d -aes-256-cbc -pbkdf2 \
			-in $(FRONTEND_DIR)/.env.local.enc \
			-out $(FRONTEND_DIR)/.env -k "$(BLOG_ENV_SECRET)"; \
		echo "✅ Frontend .env.local.enc 복호화 완료."; \
	else echo "⚠️  Frontend .env.local.enc not found."; fi

decrypt-frontend-production: check-env-secret
	@echo "🔓 Decrypting frontend .env.production.enc..."
	@if [ -f $(FRONTEND_DIR)/.env.production.enc ]; then \
		openssl enc -d -aes-256-cbc -pbkdf2 \
			-in $(FRONTEND_DIR)/.env.production.enc \
			-out $(FRONTEND_DIR)/.env -k "$(BLOG_ENV_SECRET)"; \
		echo "✅ Frontend .env.production.enc 복호화 완료."; \
	else echo "⚠️  Frontend .env.production.enc not found."; fi

# ===============================
# 🧠 System Status & Backup
# ===============================

verify-env:
	@echo "\n🧠 Verifying Environment Variables..."
	-@$(DC) -f $(COMPOSE_FILE) exec laravel printenv | grep APP_ENV || echo "⚠️ Laravel not running."
	-@$(DC) -f $(COMPOSE_FILE) exec nextjs printenv | grep NODE_ENV || echo "⚠️ Next.js not running."
	@echo "✅ Environment 확인 완료."

status:
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

backup-env:
	@mkdir -p ~/Library/Mobile\ Documents/com~apple~CloudDocs/blog_envs
	cp -v ./.env.*.enc ~/Library/Mobile\ Documents/com~apple~CloudDocs/blog_envs/ 2>/dev/null || true
	cp -v $(BACKEND_DIR)/.env.*.enc ~/Library/Mobile\ Documents/com~apple~CloudDocs/blog_envs/ 2>/dev/null || true
	cp -v $(FRONTEND_DIR)/.env.*.enc ~/Library/Mobile\ Documents/com~apple~CloudDocs/blog_envs/ 2>/dev/null || true
	@echo "✅ Encrypted envs backed up to iCloud."
