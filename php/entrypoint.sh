#!/usr/bin/env sh
set -e

if [ "$#" -ge 2 ] && [ "$1" = "php" ] && [ "$2" = "artisan" ]; then
    shift 2
    echo "🎯 Running artisan command (one-off): php artisan $*"
    exec php artisan "$@"
fi

echo "🚀 Laravel Octane Entrypoint Starting..."

# --- 환경파일 검사 ---
if [ ! -f /var/www/html/.env ]; then
    echo "❌ .env 파일이 존재하지 않습니다!"
    exit 1
else
    echo "✅ .env 파일 감지됨"
fi

# --- 의존성 설치 (최초 1회) ---
if [ ! -f /var/www/html/vendor/autoload.php ]; then
    echo "📦 Installing composer dependencies..."
    export COMPOSER_ALLOW_SUPERUSER=1
    if ! composer install --no-interaction --prefer-dist; then
        echo "❌ composer install 이 실패했습니다."
        echo "   PHP 8.5 이미지에서 nette/schema 또는 php 8.1 - 8.4 오류가 보이면 blog.backend composer.lock 갱신이 먼저 필요합니다."
        exit 1
    fi
fi

echo "🔎 Checking Composer platform requirements..."
if ! composer check-platform-reqs; then
    echo "❌ Composer platform requirements 확인에 실패했습니다."
    echo "   현재 blog.backend 의존성 또는 vendor 상태가 PHP 8.5 workspace 이미지와 맞지 않습니다."
    exit 1
fi

# --- 로컬 환경은 명시적으로 artisan migrate 실행 ---
if [ "${APP_ENV:-local}" = "local" ]; then
    echo "⏭️ Skipping startup migrations in local environment."
    echo "   Run './scripts/artisan.sh migrate' when you need to apply migrations."
else
    echo "🧩 Running migrations..."
    php artisan migrate --force
fi

# --- 최적화 캐시 초기화 ---
if [ "${APP_ENV:-local}" = "local" ]; then
    echo "⏭️ Skipping startup optimize:clear in local environment."
else
    echo "🧹 Clearing bootstrap caches..."
    php artisan optimize:clear || true
fi

# --- Octane 실행 (백그라운드) ---
echo "⚡ Starting Laravel Octane (Swoole) on port 4000..."
mkdir -p /var/log
touch /var/log/octane.log
nohup php artisan octane:start --server=swoole --host=0.0.0.0 --port=4000 > /var/log/octane.log 2>&1 &

# --- 컨테이너 유지 ---
echo "🕐 Laravel Octane is running in background. Attaching log..."
tail -f /var/log/octane.log
