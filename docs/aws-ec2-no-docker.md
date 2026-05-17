# AWS EC2 배포 가이드 (비도커, Jaubi 운영 기준)

이 문서는 `blog.workspace`를 서버에 배포하지 않고, 아래 구조로 직접 운영하는 기준입니다.

```text
/var/www/jaubi.co.kr/blog/
├── backend
└── frontend
```

운영 역할은 아래처럼 고정합니다.

- `blog.jaubi.co.kr` → `Next.js` frontend (`127.0.0.1:3000`)
- `blog.api.jaubi.co.kr` → `Laravel Octane` backend (`127.0.0.1:4000`)
- `Nginx` → `/etc/nginx/sites-available/blog`
- `systemd` → backend / scheduler
- `PM2` → frontend
- `Node.js` → `nvm`
- `Yarn` → `corepack`
- `SSL` → `certbot`

이 저장소의 `deploy/ec2` 파일은 로컬 참고/배포 템플릿입니다. 서버에는 `blog.workspace`를 clone 하지 않습니다.

## 1. 보안 그룹

- `22/tcp`
- `80/tcp`
- `443/tcp`

외부에는 `3000`, `4000`, `3306`을 열지 않습니다.

## 2. 서버 패키지 설치

Ubuntu `24.04` 기준:

```bash
sudo apt update
sudo apt install -y \
  nginx mariadb-server unzip git curl build-essential pkg-config libssl-dev \
  php8.3-cli php8.3-common php8.3-opcache php8.3-mysql php8.3-mbstring \
  php8.3-xml php8.3-curl php8.3-zip php8.3-bcmath php8.3-intl php8.3-dev php-pear
```

Swoole:

```bash
sudo pecl install swoole
echo "extension=swoole.so" | sudo tee /etc/php/8.3/mods-available/swoole.ini
sudo phpenmod swoole
php -m | grep swoole
```

Composer:

```bash
cd ~
curl -sS https://getcomposer.org/installer -o composer-setup.php
EXPECTED_CHECKSUM="$(curl -fsSL https://composer.github.io/installer.sig)"
ACTUAL_CHECKSUM="$(php -r "echo hash_file('sha384', 'composer-setup.php');")"
[ "$EXPECTED_CHECKSUM" = "$ACTUAL_CHECKSUM" ] || { echo "Composer checksum mismatch"; rm composer-setup.php; exit 1; }
sudo php composer-setup.php --install-dir=/usr/local/bin --filename=composer
rm composer-setup.php
composer --version
```

Node / NVM / Yarn / PM2:

```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

nvm install 20
nvm alias default 20
nvm use 20

corepack enable
corepack prepare yarn@4.14.1 --activate

npm install -g pm2

node -v
npm -v
yarn -v
pm2 -v
```

`~/.bashrc` 확인:

```bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
```

## 3. 서버 디렉토리 준비

```bash
sudo mkdir -p /var/www/jaubi.co.kr/blog
sudo chown -R ubuntu:ubuntu /var/www/jaubi.co.kr
sudo chmod -R 755 /var/www/jaubi.co.kr
```

서버에는 두 저장소만 둡니다.

```bash
cd /var/www/jaubi.co.kr/blog

git clone <backend-repo-url> backend
git clone <frontend-repo-url> frontend
```

## 4. MariaDB 준비

```bash
sudo systemctl enable --now mariadb
sudo mysql
```

MariaDB 콘솔:

```sql
CREATE DATABASE blog CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'blog'@'localhost' IDENTIFIED BY '강한비밀번호';
GRANT ALL PRIVILEGES ON blog.* TO 'blog'@'localhost';
FLUSH PRIVILEGES;
EXIT;
```

## 5. backend 환경 변수

경로: `/var/www/jaubi.co.kr/blog/backend/.env`

핵심 값:

```dotenv
APP_ENV=production
APP_DEBUG=false
APP_URL=https://blog.api.jaubi.co.kr

DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=blog
DB_USERNAME=blog
DB_PASSWORD=강한비밀번호

SESSION_DRIVER=database
CACHE_STORE=database
QUEUE_CONNECTION=database

CORS_ALLOWED_ORIGINS=https://blog.jaubi.co.kr
SESSION_DOMAIN=.jaubi.co.kr
SESSION_SECURE_COOKIE=true
SANCTUM_STATEFUL_DOMAINS=blog.jaubi.co.kr,blog.api.jaubi.co.kr
```

## 6. frontend 환경 변수

경로: `/var/www/jaubi.co.kr/blog/frontend/.env`

핵심 값:

```dotenv
NODE_ENV=production
NEXT_PUBLIC_SITE_URL=https://blog.jaubi.co.kr
NEXT_PUBLIC_API_URL=https://blog.api.jaubi.co.kr
NEXT_PUBLIC_API_BASE_CLIENT_HEADER_CODE=CT04P
NEXT_PUBLIC_APP_NAME=My Blog
NEXT_PUBLIC_APP_ENV=production
NEXT_PUBLIC_API_TIMEOUT=10000
NEXT_PUBLIC_DEBUG_MODE=false
```

## 7. backend 초기화

```bash
cd /var/www/jaubi.co.kr/blog/backend

composer install --no-dev --optimize-autoloader
php artisan key:generate
php artisan migrate --force
php artisan storage:link || true
php artisan optimize:clear
php artisan config:cache
php artisan route:cache
```

## 8. frontend 초기화

```bash
cd /var/www/jaubi.co.kr/blog/frontend

yarn install --immutable
yarn build
```

## 9. 서버 설정 파일 배치

이 저장소에서 아래 파일 내용을 서버에 반영합니다.

- [deploy/ec2/systemd/blog-backend.service](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/deploy/ec2/systemd/blog-backend.service)
- [deploy/ec2/systemd/blog-scheduler.service](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/deploy/ec2/systemd/blog-scheduler.service)
- [deploy/ec2/systemd/blog-scheduler.timer](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/deploy/ec2/systemd/blog-scheduler.timer)
- [deploy/ec2/pm2/ecosystem.config.cjs](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/deploy/ec2/pm2/ecosystem.config.cjs)
- [deploy/ec2/nginx/blog.conf](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/deploy/ec2/nginx/blog.conf)

반영 위치:

- `/etc/systemd/system/blog-backend.service`
- `/etc/systemd/system/blog-scheduler.service`
- `/etc/systemd/system/blog-scheduler.timer`
- `/var/www/jaubi.co.kr/blog/frontend/ecosystem.config.cjs`
- `/etc/nginx/sites-available/blog`

## 10. backend / scheduler 등록

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now blog-backend
sudo systemctl enable --now blog-scheduler.timer
```

확인:

```bash
systemctl status blog-backend
systemctl status blog-scheduler.timer
```

## 11. frontend PM2 등록

```bash
cd /var/www/jaubi.co.kr/blog/frontend
pm2 start ecosystem.config.cjs
pm2 status
pm2 logs blog-frontend
pm2 save
pm2 startup
```

`pm2 startup`이 출력하는 `sudo ... pm2 startup ...` 명령을 그대로 한 번 실행한 뒤 다시:

```bash
pm2 save
```

Node 메이저 버전을 바꾼 뒤에는 `pm2 unstartup`, `pm2 startup`, `pm2 save`를 다시 실행합니다.

## 12. Nginx 반영

```bash
sudo ln -sf /etc/nginx/sites-available/blog /etc/nginx/sites-enabled/blog
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl reload nginx
```

## 13. Certbot

```bash
sudo apt-get remove -y certbot
sudo snap install core
sudo snap refresh core
sudo snap install --classic certbot
sudo ln -sf /snap/bin/certbot /usr/local/bin/certbot
certbot --version
```

인증서 발급:

```bash
sudo certbot --nginx -d blog.jaubi.co.kr -d blog.api.jaubi.co.kr
```

갱신 점검:

```bash
sudo certbot renew --dry-run
```

## 14. 배포 후 점검

```bash
ls -ld /var/www/jaubi.co.kr/blog
namei -l /var/www/jaubi.co.kr/blog/backend

systemctl status blog-backend
curl http://127.0.0.1:4000/api/health

systemctl status blog-scheduler.timer
journalctl -u blog-scheduler.service -n 50

pm2 status
curl http://127.0.0.1:3000

sudo nginx -t
curl -H "Host: blog.jaubi.co.kr" http://127.0.0.1
curl -H "Host: blog.api.jaubi.co.kr" http://127.0.0.1/api/health

curl https://blog.jaubi.co.kr
curl https://blog.api.jaubi.co.kr/api/health
```

로그:

```bash
journalctl -u blog-backend -f
journalctl -u blog-scheduler.service -f
pm2 logs blog-frontend
sudo tail -f /var/log/nginx/access.log /var/log/nginx/error.log
```

## 15. 이후 배포 절차

backend:

```bash
cd /var/www/jaubi.co.kr/blog/backend
git pull
composer install --no-dev --optimize-autoloader
php artisan migrate --force
php artisan optimize:clear
php artisan config:cache
php artisan route:cache
sudo systemctl restart blog-backend
```

frontend:

```bash
cd /var/www/jaubi.co.kr/blog/frontend
git pull
yarn install --immutable
yarn build
pm2 restart blog-frontend
```
