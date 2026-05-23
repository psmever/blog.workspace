# AWS EC2 배포 가이드

이 문서는 EC2에 애플리케이션을 직접 배치하는 현재 상용 운영 기준입니다.

```text
/var/www/jaubi.co.kr/blog/
├── blog.backend
└── blog.frontend
```

현재 서버 스펙:

- OS: Ubuntu 24.04.4 LTS
- CPU: 2 vCPU
- Memory: 3.7 GB RAM
- Disk: 48 GB SSD
- Runtime: Node.js, PM2
- 업로드 스토리지: AWS S3
- CDN: CloudFront 예정

운영 역할은 아래처럼 고정합니다.

- `blog.jaubi.co.kr` -> `Next.js` frontend (`127.0.0.1:3000`)
- `blog.api.jaubi.co.kr` -> `Laravel Octane` backend (`127.0.0.1:4000`)
- `Nginx` -> `/etc/nginx/sites-available/blog`
- `systemd` -> backend / scheduler
- `PM2` -> frontend
- `Node.js` -> `nvm`
- `Yarn` -> `corepack`
- `SSL` -> `certbot`

`blog.manager`는 운영 계획에 포함되어 있지만, 현재 이 워크스페이스에는 저장소와 배포 템플릿이 없습니다. 이 문서는 `backend`와 `frontend`만 다룹니다.

이 저장소의 `deploy/ec2` 파일은 로컬 참고용 템플릿입니다. 서버에는 `blog.workspace`를 clone 하지 않습니다.

## 1. 서버 timezone 설정

서버 접속 직후 가장 먼저 timezone을 `Asia/Seoul`로 맞춥니다.

```bash
sudo timedatectl set-timezone Asia/Seoul
timedatectl status
date
```

확인 기준:

- `Time zone: Asia/Seoul (KST, +0900)` 로 표시되면 정상입니다.
- 이후 `systemd`, `pm2`, `nginx`, `certbot` 로그와 스케줄 확인이 훨씬 직관적입니다.

## 2. 보안 그룹

- `22/tcp`
- `80/tcp`
- `443/tcp`

외부에는 `3000`, `4000`, `3306`을 열지 않습니다.

## 3. 서버 패키지 설치

Ubuntu `24.04` 기준:

```bash
sudo apt update
sudo apt install -y \
  nginx mariadb-server unzip git curl build-essential pkg-config libssl-dev \
  php8.3-cli php8.3-common php8.3-opcache php8.3-mysql php8.3-mbstring \
  php8.3-xml php8.3-curl php8.3-zip php8.3-bcmath php8.3-intl php8.3-dev php-pear
```

### 3-1. Swoole 설치

```bash
sudo pecl channel-update pecl.php.net
sudo pecl install swoole
```

설치 중 프롬프트는 아래처럼 입력합니다.

| 프롬프트 | 입력값 |
|------|------|
| `enable sockets support? [no] :` | `yes` |
| `specify openssl installation directory (requires openssl 1.1.0 or later)? [no] :` | `Enter` |
| `enable mysqlnd support? [no] :` | `Enter` |
| `enable curl support? [no] :` | `Enter` |
| `enable cares support? [no] :` | `Enter` |
| `enable brotli support? [yes] :` | `no` |
| `specify brotli installation directory? [no] :` | `Enter` |
| `enable zstd support (requires zstd 1.4.0 or later)? [no] :` | `Enter` |
| `enable PostgreSQL database support? [no] :` | `Enter` |
| `enable ODBC database support? [no] :` | `Enter` |
| `enable Oracle database support? [no] :` | `Enter` |
| `enable Sqlite database support? [no] :` | `Enter` |
| `enable Firebird database support? [no] :` | `Enter` |
| `enable swoole thread support (need php zts support)? [no] :` | `Enter` |
| `enable iouring for file async support? [no] :` | `Enter` |
| `specify liburing installation directory (requires liburing 2.8 or later)? [no] :` | `Enter` |
| `enable iouring for http coroutine server support? [no] :` | `Enter` |
| `enable async ssh2 client support? [no] :` | `Enter` |
| `enable async ftp client support? [no] :` | `Enter` |

경로를 묻는 질문은 커스텀 라이브러리 설치 경로를 따로 잡아둔 게 아니라면 대부분 `Enter`로 비워두면 됩니다.

가장 단순한 설치 기준은 `curl=no`, `brotli=no`, `iouring=no` 입니다. 현재 배포 구조에서는 이 옵션들이 필수는 아닙니다.

자주 나는 오류:

- `Package requirements (libcurl >= 7.56.0) were not met`
  - 원인: `enable curl support?` 에서 `yes` 선택
  - 조치: 다시 설치하면서 `Enter` 로 `no` 유지
- `Package requirements (libbrotlienc) were not met`
  - 원인: `enable brotli support? [yes] :` 에서 `Enter` 를 눌러 기본값 `yes` 선택
  - 조치: 다시 설치하면서 반드시 `no` 입력

설치가 끝나면:

```bash
echo "extension=swoole.so" | sudo tee /etc/php/8.3/mods-available/swoole.ini
sudo phpenmod swoole
php -m | grep -i swoole
```

정상 확인:

- 출력에 `swoole` 이 보이면 정상입니다.
- `blog-backend.service` 템플릿은 현재 서버 스펙 기준으로 `--workers=2` 입니다.

### 3-2. Composer 설치

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

### 3-3. Node / NVM / Yarn / PM2 설치

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

## 4. 서버 디렉터리 준비

```bash
sudo mkdir -p /var/www/jaubi.co.kr/blog
sudo chown -R ubuntu:ubuntu /var/www/jaubi.co.kr
sudo chmod -R 755 /var/www/jaubi.co.kr
```

서버에는 두 저장소만 둡니다.

```bash
cd /var/www/jaubi.co.kr/blog

git clone <backend-repo-url> blog.backend
git clone <frontend-repo-url> blog.frontend
```

## 5. mariadb 준비

```bash
sudo systemctl enable --now mariadb
sudo mariadb
```

`mariadb` 콘솔:

```sql
CREATE DATABASE blog CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'blog'@'localhost' IDENTIFIED BY '강한비밀번호';
GRANT ALL PRIVILEGES ON blog.* TO 'blog'@'localhost';
FLUSH PRIVILEGES;
EXIT;
```

Laravel에서는 `DB_CONNECTION=mysql`을 그대로 사용합니다. 드라이버 이름이 `mysql`이어도 대상 DB는 mariadb여도 정상입니다.

## 6. backend 환경 변수

경로: `/var/www/jaubi.co.kr/blog/blog.backend/.env`

기본 템플릿:

- [deploy/ec2/env/backend.production.env.example](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/deploy/ec2/env/backend.production.env.example:1)

핵심 값:

```dotenv
APP_ENV=production
APP_KEY=base64:...
APP_DEBUG=false
APP_URL=https://blog.api.jaubi.co.kr

DB_CONNECTION=mysql
DB_HOST=localhost
DB_PORT=3306
DB_DATABASE=blog
DB_USERNAME=blog
DB_PASSWORD=강한비밀번호

SESSION_DRIVER=database
CACHE_STORE=database
QUEUE_CONNECTION=database
MEDIA_DISK=s3

CORS_ALLOWED_ORIGINS=https://blog.jaubi.co.kr
SESSION_DOMAIN=.jaubi.co.kr
SESSION_SECURE_COOKIE=true
SANCTUM_STATEFUL_DOMAINS=blog.jaubi.co.kr,blog.api.jaubi.co.kr

AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...
AWS_DEFAULT_REGION=ap-northeast-2
AWS_BUCKET=...
# CloudFront 도입 시 CDN 도메인 사용
# AWS_URL=https://cdn.jaubi.co.kr
```

주의:

- 새 인스턴스 재배포 시 `APP_KEY`는 반드시 새로 생성합니다. 기존 서버가 침해되었거나 env 암호화 키가 노출되었다면 기존 `APP_KEY`를 재사용하지 않습니다.
- `APP_KEY`는 Laravel 암호화, 쿠키, 서명 데이터의 루트 키입니다. 유출 가능성이 있으면 현재 세션/토큰을 모두 폐기하고, 필요한 경우 암호화 저장 데이터 영향도 확인 후 회전합니다.
- 운영 `.env.production.enc`를 Git, iCloud, 문서 저장소에 올리지 않습니다. 운영 암호화 키는 `BLOG_ENV_PRODUCTION_SECRET`처럼 로컬 키와 분리해서 관리합니다.
- 운영 env에는 `ADMIN_LOGIN_PASSWORD`, `DB_PASSWORD`, `AWS_SECRET_ACCESS_KEY`, `APP_KEY`가 함께 들어가므로, env 암호화 키가 노출되면 모두 유출된 것으로 간주합니다.
- 위 예시는 `CREATE USER 'blog'@'localhost'` 기준입니다.
- `DB_HOST=127.0.0.1` 로 바꾸면 MariaDB에서는 `'blog'@'127.0.0.1'` 접속으로 처리될 수 있어서 권한 오류가 날 수 있습니다.
- 같은 서버에서 붙는 기본 운영 기준은 `DB_HOST=localhost` 가 안전합니다.

## 7. frontend 환경 변수

경로: `/var/www/jaubi.co.kr/blog/blog.frontend/.env`

기본 템플릿:

- [deploy/ec2/env/frontend.production.env.example](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/deploy/ec2/env/frontend.production.env.example:1)

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

## 8. backend 초기화

```bash
cd /var/www/jaubi.co.kr/blog/blog.backend

composer install --no-dev --optimize-autoloader
php artisan key:generate
php artisan migrate --force
php artisan db:seed --force
php artisan optimize:clear
php artisan config:cache
php artisan route:cache
sudo systemctl restart blog-backend
```

`MEDIA_DISK=s3` 기준이라면 `storage:link`는 업로드 파일 제공에 필수는 아닙니다.

주의:

- `db:seed --force` 는 생략하지 않습니다.
- `CommonCodeSeeder` 가 `common_codes` 테이블에 `client.type`, `post.status`, `post.category` 등을 채웁니다.
- 이 데이터가 없으면 `Client-Type: CT04P` 검증과 `/api/v1/base-data` 응답이 정상 동작하지 않습니다.
- `Laravel Octane` 은 장수 프로세스라서 `.env`, `config:cache`, 마이그레이션, 시드 반영 후에는 `sudo systemctl restart blog-backend` 로 워커를 새로 띄우는 것이 안전합니다.

## 9. frontend 초기화

```bash
cd /var/www/jaubi.co.kr/blog/blog.frontend

yarn install --immutable
yarn build
```

## 10. frontend PM2 등록

`ecosystem.config.cjs`는 `blog.frontend` 소스 루트에 포함되어 함께 배포된다고 가정합니다.

```bash
cd /var/www/jaubi.co.kr/blog/blog.frontend
pm2 start ecosystem.config.cjs
pm2 install pm2-logrotate
pm2 set pm2-logrotate:max_size 50M
pm2 set pm2-logrotate:retain 7
pm2 set pm2-logrotate:compress true
pm2 set pm2-logrotate:dateFormat YYYY-MM-DD_HH-mm-ss
pm2 set pm2-logrotate:rotateInterval '0 0 * * *'
pm2 set pm2-logrotate:workerInterval 30
pm2 set pm2-logrotate:rotateModule true
pm2 status
pm2 logs blog-frontend
pm2 conf pm2-logrotate
pm2 save
pm2 startup
```

`pm2 startup`이 출력하는 `sudo ... pm2 startup ...` 명령을 그대로 한 번 실행한 뒤 다시:

```bash
pm2 save
```

Node 메이저 버전을 바꾼 뒤에는 `pm2 unstartup`, `pm2 startup`, `pm2 save`를 다시 실행합니다.

권장 기준:

- `max_size=50M`
- `retain=7`
- `compress=true`
- `rotateInterval='0 0 * * *'`

현재 서버는 디스크 48 GB이고 PM2 서비스 수가 많지 않으므로 위 값이면 충분합니다.

## 11. 서버 설정 파일 배치

이 저장소에서 아래 파일 내용을 서버에 반영합니다.

- [deploy/ec2/systemd/blog-backend.service](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/deploy/ec2/systemd/blog-backend.service)
- [deploy/ec2/systemd/blog-scheduler.service](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/deploy/ec2/systemd/blog-scheduler.service)
- [deploy/ec2/systemd/blog-scheduler.timer](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/deploy/ec2/systemd/blog-scheduler.timer)
- [deploy/ec2/nginx/blog.conf](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/deploy/ec2/nginx/blog.conf)
- [deploy/ec2/scripts/common.sh](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/deploy/ec2/scripts/common.sh)
- [deploy/ec2/scripts/deploy-backend.sh](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/deploy/ec2/scripts/deploy-backend.sh)
- [deploy/ec2/scripts/deploy-frontend.sh](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/deploy/ec2/scripts/deploy-frontend.sh)
- [deploy/ec2/scripts/deploy-all.sh](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/deploy/ec2/scripts/deploy-all.sh)

반영 위치:

- `/etc/systemd/system/blog-backend.service`
- `/etc/systemd/system/blog-scheduler.service`
- `/etc/systemd/system/blog-scheduler.timer`
- `/etc/nginx/sites-available/blog`
- `/opt/deploy/blog/common.sh`
- `/opt/deploy/blog/deploy-backend.sh`
- `/opt/deploy/blog/deploy-frontend.sh`
- `/opt/deploy/blog/deploy-all.sh`

로컬에서 `scp` 업로드:

`~/.ssh/config` 에서 서버 별칭이 `blog-prod` 이고, 로컬 준비 파일 위치가 `~/Workspace/deploy/**` 라고 가정합니다.

```bash
cd ~/Workspace/deploy
scp -r ./ec2 blog-prod:~/Workspace/deploy/
```

서버에서 배치:

```bash
sudo cp ~/Workspace/deploy/ec2/systemd/blog-backend.service /etc/systemd/system/blog-backend.service
sudo cp ~/Workspace/deploy/ec2/systemd/blog-scheduler.service /etc/systemd/system/blog-scheduler.service
sudo cp ~/Workspace/deploy/ec2/systemd/blog-scheduler.timer /etc/systemd/system/blog-scheduler.timer
sudo cp ~/Workspace/deploy/ec2/nginx/blog.conf /etc/nginx/sites-available/blog
sudo mkdir -p /opt/deploy/blog
sudo cp ~/Workspace/deploy/ec2/scripts/common.sh /opt/deploy/blog/common.sh
sudo cp ~/Workspace/deploy/ec2/scripts/deploy-backend.sh /opt/deploy/blog/deploy-backend.sh
sudo cp ~/Workspace/deploy/ec2/scripts/deploy-frontend.sh /opt/deploy/blog/deploy-frontend.sh
sudo cp ~/Workspace/deploy/ec2/scripts/deploy-all.sh /opt/deploy/blog/deploy-all.sh
sudo chown -R ubuntu:ubuntu /opt/deploy/blog
sudo chmod 755 /opt/deploy/blog/*.sh
```

주의:

- `deploy-backend.sh` 는 `sudo -n systemctl restart blog-backend` 를 사용합니다.
- 배포 계정에 비밀번호 없는 sudo 권한이 없다면 최소 권한으로 sudoers를 추가해야 합니다.

## 12. backend / scheduler 등록

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

## 13. Nginx 반영

```bash
sudo ln -sf /etc/nginx/sites-available/blog /etc/nginx/sites-enabled/blog
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl reload nginx
```

## 14. Certbot

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

## 15. 배포 후 점검

```bash
ls -ld /var/www/jaubi.co.kr/blog
namei -l /var/www/jaubi.co.kr/blog/blog.backend

systemctl status blog-backend
curl -H "Client-Type: CT04P" http://127.0.0.1:4000/api/health

systemctl status blog-scheduler.timer
journalctl -u blog-scheduler.service -n 50

pm2 status
curl http://127.0.0.1:3000

sudo nginx -t
curl -H "Host: blog.jaubi.co.kr" http://127.0.0.1
curl -H "Host: blog.api.jaubi.co.kr" -H "Client-Type: CT04P" http://127.0.0.1/api/health

curl https://blog.jaubi.co.kr
curl -H "Client-Type: CT04P" https://blog.api.jaubi.co.kr/api/health
```

주의:

- 현재 backend는 `/api/*` 요청에 `Client-Type` 헤더를 강제합니다.
- 헤더 없이 `/api/health` 를 호출하면 `400 Bad Request` 가 나오는 것이 정상일 수 있습니다.

로그:

```bash
journalctl -u blog-backend -f
journalctl -u blog-scheduler.service -f
pm2 logs blog-frontend
sudo tail -f /var/log/nginx/access.log /var/log/nginx/error.log
```

## 16. 이후 배포 절차

운영 배포는 서버 스크립트를 직접 실행하거나, 로컬 래퍼 스크립트로 트리거합니다.

서버에서 직접 실행:

```bash
/opt/deploy/blog/deploy-backend.sh v2026.05.21-1
/opt/deploy/blog/deploy-frontend.sh v2026.05.21-1
/opt/deploy/blog/deploy-all.sh v2026.05.21-1
```

로컬에서 실행:

```bash
cd blog.workspace
./scripts/deploy-prod.sh backend v2026.05.21-1
./scripts/deploy-prod.sh frontend v2026.05.21-1
./scripts/deploy-prod.sh all v2026.05.21-1
```

원칙:

- 배포 기준은 `branch` 대신 `tag` 또는 `commit SHA` 를 사용합니다.
- 실제 배포 로직은 서버 `/opt/deploy/blog/*.sh` 에만 둡니다.
- 로컬 스크립트는 `ssh blog-prod ...` 호출만 담당합니다.

## 17. 운영 메모

- `blog-backend.service`는 현재 2 vCPU 서버 기준으로 Octane worker 수를 `2`로 맞췄습니다.
- 메모리 3.7 GB에 swap이 꺼져 있으므로, 서버에서 직접 `yarn build`를 수행할 때 메모리 압박이 생기면 swap 2 GB 추가나 CI 빌드 아티팩트 배포를 검토하는 편이 안전합니다.
