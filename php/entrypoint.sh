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
    composer install --no-interaction --prefer-dist
fi

# --- 최적화 캐시 초기화 ---
php artisan optimize:clear || true

# --- DB 마이그레이션 (비강제 실패 무시) ---
echo "🧩 Running migrations..."
php artisan migrate --force || true

# --- Octane 실행 (백그라운드) ---
echo "⚡ Starting Laravel Octane (Swoole) on port 4000..."
mkdir -p /var/log
touch /var/log/octane.log
nohup php artisan octane:start --server=swoole --host=0.0.0.0 --port=4000 > /var/log/octane.log 2>&1 &

# --- 컨테이너 유지 ---
echo "🕐 Laravel Octane is running in background. Attaching log..."
tail -f /var/log/octane.log
