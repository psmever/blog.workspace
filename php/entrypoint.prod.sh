#!/usr/bin/env sh
set -eu

cd /var/www/html

echo "🚀 Laravel Production Entrypoint Starting..."

if [ ! -f .env ]; then
    echo "❌ /var/www/html/.env 파일이 존재하지 않습니다."
    exit 1
fi

mkdir -p storage/framework/cache storage/framework/sessions storage/framework/views storage/logs bootstrap/cache
chmod -R ug+rwx storage bootstrap/cache || true

echo "🔎 Checking Composer platform requirements..."
if ! composer check-platform-reqs; then
    echo "❌ Composer platform requirements 확인에 실패했습니다."
    echo "   운영 이미지를 PHP 8.5로 유지하려면 blog.backend composer.lock 이 먼저 PHP 8.5와 호환되어야 합니다."
    exit 1
fi

echo "🧩 Running migrations..."
php artisan migrate --force

if [ ! -L public/storage ] && [ ! -e public/storage ]; then
    echo "🔗 Creating storage symlink..."
    php artisan storage:link || true
fi

echo "🧹 Clearing bootstrap caches..."
php artisan optimize:clear || true

echo "⚡ Starting Laravel Octane (Swoole) on port 4000..."
exec php artisan octane:start --server=swoole --host=0.0.0.0 --port=4000
