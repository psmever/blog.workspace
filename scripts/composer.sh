#!/usr/bin/env bash
set -euo pipefail
PROJ_ROOT=$(cd "$(dirname "$0")/.." && pwd)

if docker compose version >/dev/null 2>&1; then
  DC_CMD=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  DC_CMD=(docker-compose)
else
  echo "❌ docker compose / docker-compose 명령을 찾을 수 없습니다." >&2
  exit 1
fi

"${DC_CMD[@]}" -f "$PROJ_ROOT/docker-compose.yml" run --rm --entrypoint composer laravel "$@"
