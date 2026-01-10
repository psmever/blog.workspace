#!/usr/bin/env bash
set -euo pipefail

# 루트 경로 계산
PROJ_ROOT=$(cd "$(dirname "$0")/.." && pwd)
COMPOSE_FILE="$PROJ_ROOT/docker-compose.yml"
SERVICE_NAME="laravel"

# docker compose wrapper (plugin or legacy) detection
if docker compose version >/dev/null 2>&1; then
  DC_CMD=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  DC_CMD=(docker-compose)
else
  echo "❌ docker compose / docker-compose를 찾을 수 없습니다." >&2
  exit 1
fi

# 실행 중인 laravel 컨테이너 ID 확인
LARAVEL_CONTAINER=$("${DC_CMD[@]}" -f "$COMPOSE_FILE" ps -q $SERVICE_NAME || true)

if [ -n "$LARAVEL_CONTAINER" ] && [ "$(docker inspect -f '{{.State.Running}}' "$LARAVEL_CONTAINER" 2>/dev/null)" = "true" ]; then
  echo "🚀 Executing artisan command in running $SERVICE_NAME container..."
  "${DC_CMD[@]}" -f "$COMPOSE_FILE" exec $SERVICE_NAME php artisan "$@"
else
  echo "⚙️ Laravel container not running — starting temporary container..."
  "${DC_CMD[@]}" -f "$COMPOSE_FILE" run --rm $SERVICE_NAME php artisan "$@"
fi
