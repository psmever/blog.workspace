# AWS EC2 배포 가이드

이 문서는 EC2에 SSH 접속을 마친 뒤, 서버 안에서 실제 배포 작업을 어떤 순서로 진행하는지 정리한 운영 기준입니다.

```text
/var/www/jaubi.co.kr/blog/
├── blog.backend
└── blog.frontend
```

현재 서버 기준:

- OS: Ubuntu 26.04 LTS
- CPU: 2 vCPU
- Memory: 3.7 GiB RAM
- Root volume: 40 GiB `gp3`
- Data volume: 80 GiB `gp3` (`MariaDB` 전용)
- 현재 `blog.backend` lock 파일 호환 PHP 범위: `8.1 - 8.4`
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

이 문서는 보안 그룹, 키 페어, IAM, 비밀값 보관 정책 같은 보안 항목은 다루지 않습니다. 배포 순서와 서버 반영 절차만 정리합니다.

## 운영 원칙

- 실제 배포 로직은 서버 `/opt/deploy/blog/*.sh` 에 둡니다.
- 표준 실행 경로는 로컬 `make deploy-*` 가 SSH로 서버 배포 스크립트를 호출하는 방식입니다.
- 필요하면 서버에 접속해서 `/opt/deploy/blog/*.sh` 를 직접 실행할 수도 있습니다.
- `backend`와 `frontend`는 서로 독립된 배포 단위이지만, 현재 운영 배포는 두 저장소 모두 `origin/main` 만 pull 하는 방식입니다.
- 전체 반영이 필요할 때의 기본 순서는 `backend -> frontend` 입니다.
- `deploy-backend.sh`, `deploy-frontend.sh`, `deploy-all.sh` 는 인자를 받지 않고 각 저장소의 `main` 브랜치를 반영합니다.
- 배포 스크립트가 바뀌면 먼저 `make deploy-sync` 로 서버 `/opt/deploy/blog` 를 갱신합니다.
- `make deploy-backend`, `make deploy-frontend`, `make deploy-all` 이 성공하면 로컬 래퍼가 앱 저장소 `origin` 에 `deploy/prod/<app>/<timestamp>` annotated tag를 자동 push 합니다.
- PM2 실행 기준 파일은 서버의 `blog.frontend/ecosystem.config.cjs` 입니다.

## 전체 순서

1. timezone을 `Asia/Seoul`로 맞춥니다.
2. `apt update/upgrade` 후 기본 패키지와 PHP 런타임을 설치합니다.
3. Composer, Node.js, Yarn, PM2, Swoole을 설치하고 런타임을 확인합니다.
4. 추가 EBS data 볼륨을 MariaDB 전용 볼륨으로 마운트합니다.
5. 서버 디렉터리를 만들고 backend/frontend 저장소를 배치합니다.
6. MariaDB를 기동하고 DB/사용자를 초기화합니다.
7. backend/frontend `.env`를 작성합니다.
8. backend 의존성 설치, 마이그레이션, 시드, 캐시를 수행합니다.
9. frontend 의존성 설치와 프로덕션 빌드를 수행합니다.
10. systemd, Nginx, 배포 스크립트 파일을 서버에 배치합니다.
11. backend, scheduler, frontend, Nginx를 순서대로 기동합니다.
12. Certbot으로 인증서를 발급합니다.
13. 헬스체크와 서비스 상태를 검증합니다.
14. 이후 재배포는 `backend -> frontend` 순서로 직접 실행합니다.

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

## 2. 기본 패키지 설치

Ubuntu LTS 계열에서는 배포판에 따라 PHP minor 버전이 달라질 수 있으므로 `php8.x-*` 대신 메타 패키지를 사용합니다.

중요:

- 현재 [../blog.backend/composer.lock](/Users/sm/Workspaces/Development/MyProject/blog/blog.backend/composer.lock:2735) 은 `nette/schema v1.3.2` 를 고정하고 있고, 이 버전은 `php 8.1 - 8.4` 만 허용합니다.
- 그래서 Ubuntu `26.04` 기본 PHP `8.5` 환경에서는 `composer install` 이 실패할 수 있습니다.
- 운영 기준으로 가장 안전한 경로는 `PHP 8.4 이하` 환경을 쓰는 것입니다.
- Ubuntu `26.04` 서버를 유지하려면 backend 저장소에서 의존성 업데이트와 `composer.lock` 재생성이 먼저 필요합니다.
- `PHP 8.5` 유지 전제로 backend에 전달할 작업은 [docs/backend-php85-handoff.md](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/docs/backend-php85-handoff.md:1) 에 따로 정리했습니다.

```bash
sudo apt update
sudo apt -y upgrade
sudo apt install -y \
  nginx mariadb-server unzip git curl rsync build-essential pkg-config libssl-dev \
  php-cli php-common php-mysql php-mbstring \
  php-xml php-curl php-zip php-bcmath php-intl php-dev php-pear
```

패키지 업그레이드 뒤 커널이나 기본 라이브러리 갱신이 함께 들어갔다면, 필요한 시점에 한 번 재부팅한 뒤 나머지 배포 작업을 진행합니다.

설치 확인:

```bash
lsb_release -a
php -v
php -m | grep -E 'mbstring|pdo_mysql|curl|zip|bcmath|intl|openssl'
php -i | grep -i opcache
```

정리 기준:

- `php -v` 에 현재 서버 기준 PHP minor 버전이 보이면 정상입니다.
- `mbstring`, `pdo_mysql`, `curl`, `zip`, `bcmath`, `intl` 이 모두 로드되어야 합니다.
- `Zend OPcache` 가 이미 활성화되어 있으면 별도 `php-opcache` 패키지는 필요하지 않습니다.

### 2-0. PHP 8.5 호환성 점검

`composer install --no-dev --optimize-autoloader` 에서 아래와 비슷한 오류가 나면 현재 서버 PHP가 너무 새로운 상태입니다.

```text
nette/schema v1.3.2 requires php 8.1 - 8.4
your php version (8.5.x) does not satisfy that requirement
```

정리:

- [../blog.backend/composer.json](/Users/sm/Workspaces/Development/MyProject/blog/blog.backend/composer.json:12) 의 루트 조건은 `php ^8.2` 라서 넓게 허용합니다.
- 하지만 실제 설치는 lock 파일에 고정된 패키지 버전을 따르므로, [../blog.backend/composer.lock](/Users/sm/Workspaces/Development/MyProject/blog/blog.backend/composer.lock:2750) 의 `nette/schema v1.3.2` 가 상한을 `8.4`로 막고 있습니다.
- [league/config v1.2.0](/Users/sm/Workspaces/Development/MyProject/blog/blog.backend/composer.lock:1962) 은 `nette/schema ^1.2` 를 요구하므로, backend 저장소에서 lock만 갱신하면 `nette/schema` 를 더 새 버전으로 올릴 수 있습니다.

실행 선택지는 두 가지입니다.

1. 현재 배포를 빨리 끝내려면
   - 서버 PHP를 `8.4 이하`로 맞춥니다.
   - 가장 단순한 운영 경로는 `Ubuntu 24.04 LTS` 기반 서버에서 다시 진행하는 것입니다.
2. Ubuntu `26.04` / PHP `8.5`를 유지하려면
   - backend 저장소에서 의존성을 업데이트하고 `composer.lock` 을 다시 생성해야 합니다.
   - 이 작업은 이 워크스페이스가 아니라 Blog Backend 프로젝트 채팅에서 진행하는 것이 맞습니다.
   - 전달용 문구는 [docs/backend-php85-handoff.md](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/docs/backend-php85-handoff.md:1) 를 사용합니다.

### 2-1. Composer 설치

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

### 2-2. Node / NVM / Yarn / PM2 설치

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

### 2-3. Swoole 설치

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

자주 나는 오류:

- `Package requirements (libcurl >= 7.56.0) were not met`
  - 원인: `enable curl support?` 에서 `yes` 선택
  - 조치: 다시 설치하면서 `Enter` 로 `no` 유지
- `Package requirements (libbrotlienc) were not met`
  - 원인: `enable brotli support? [yes] :` 에서 `Enter` 를 눌러 기본값 `yes` 선택
  - 조치: 다시 설치하면서 반드시 `no` 입력

설치가 끝나면 현재 PHP minor 버전에 맞춰 확장을 활성화합니다.

```bash
PHP_MM=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
echo "extension=swoole.so" | sudo tee /etc/php/${PHP_MM}/mods-available/swoole.ini
sudo phpenmod swoole
php -m | grep -i swoole
php --ri swoole
```

정상 확인:

- 출력에 `swoole` 이 보이면 정상입니다.
- `blog-backend.service` 템플릿은 현재 서버 스펙 기준으로 `--workers=2` 입니다.

## 3. MariaDB 데이터 볼륨 준비

이 단계는 `mariadb-server` 패키지 설치 뒤, 실제 DB 초기화 전에 1회만 수행합니다.

먼저 연결된 디스크를 확인합니다.

```bash
lsblk
sudo file -s /dev/nvme1n1
```

확인 기준:

- 루트 볼륨은 보통 `nvme0n1` 로 보입니다.
- 추가 data 볼륨은 보통 `nvme1n1` 로 보입니다.
- 새 볼륨이면 `sudo file -s /dev/nvme1n1` 결과가 `data` 로 나옵니다.
- EC2에서 `/dev/sdb` 로 연결했더라도 Ubuntu 안에서는 `nvme1n1` 처럼 보일 수 있습니다.

새 data 볼륨을 `ext4`로 포맷하고 `/data/mysql` 에 마운트한 뒤, MariaDB 데이터 경로로 bind mount 합니다.

```bash
sudo mkfs.ext4 /dev/nvme1n1

sudo mkdir -p /data/mysql
UUID=$(sudo blkid -s UUID -o value /dev/nvme1n1)
echo "UUID=${UUID} /data/mysql ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab

sudo mount -a
df -h /data/mysql

sudo systemctl stop mariadb || true
sudo rsync -av /var/lib/mysql/ /data/mysql/

sudo mv /var/lib/mysql /var/lib/mysql.bak
sudo mkdir -p /var/lib/mysql
echo "/data/mysql /var/lib/mysql none bind 0 0" | sudo tee -a /etc/fstab

sudo mount /var/lib/mysql
sudo chown -R mysql:mysql /data/mysql
sudo chmod 750 /var/lib/mysql

findmnt /data/mysql
findmnt /var/lib/mysql
```

정리 기준:

- `UUID=... /data/mysql ext4 ...` 항목이 `fstab`에 있어야 재부팅 후에도 data 볼륨이 다시 붙습니다.
- `/data/mysql /var/lib/mysql none bind 0 0` 항목이 있어야 MariaDB가 data 볼륨을 그대로 사용합니다.
- `findmnt /var/lib/mysql` 결과가 나오면 bind mount가 정상입니다.
- MariaDB가 정상 기동하는 걸 확인한 뒤 `sudo rm -rf /var/lib/mysql.bak` 로 백업 디렉터리를 정리합니다.

## 4. 서버 디렉터리 준비

```bash
sudo mkdir -p /var/www/jaubi.co.kr/blog
sudo chown -R ubuntu:ubuntu /var/www/jaubi.co.kr
sudo chmod -R 755 /var/www/jaubi.co.kr
```

서버에는 두 저장소만 두고, 첫 clone 시에는 원격 `main` 브랜치만 가져옵니다.

```bash
cd /var/www/jaubi.co.kr/blog

git clone --branch main --single-branch <backend-repo-url> blog.backend
git clone --branch main --single-branch <frontend-repo-url> blog.frontend
```

기본 브랜치가 `main` 이 아닌 저장소라면 해당 브랜치 이름으로 바꿉니다.

## 5. MariaDB 준비

```bash
sudo systemctl enable --now mariadb
systemctl status mariadb --no-pager
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
POST_IMAGE_MAX_KB=204800

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

- 위 예시는 `CREATE USER 'blog'@'localhost'` 기준입니다.
- `DB_HOST=127.0.0.1` 로 바꾸면 MariaDB에서는 `'blog'@'127.0.0.1'` 접속으로 처리될 수 있어서 권한 오류가 날 수 있습니다.
- 같은 서버에서 붙는 기본 운영 기준은 `DB_HOST=localhost` 가 안전합니다.
- 이미지 업로드 제한을 `200M` 으로 맞추려면 `POST_IMAGE_MAX_KB=204800` 을 유지합니다.

### 6-1. 이미지 업로드 200M 설정

운영 서버에서 이미지 업로드를 `200M` 기준으로 맞추려면 아래 3군데를 함께 확인해야 합니다.

1. backend `.env`

```dotenv
POST_IMAGE_MAX_KB=204800
```

2. Nginx

경로: `/etc/nginx/sites-available/blog`

```nginx
client_max_body_size 200M;
```

3. PHP CLI

경로: `/etc/php/8.5/cli/php.ini`

```ini
upload_max_filesize = 200M
post_max_size = 200M
memory_limit = 512M
max_execution_time = 120
```

주의:

- Ubuntu 기본 PHP 설정은 `upload_max_filesize = 2M`, `post_max_size = 8M` 인 경우가 많습니다.
- 이 값이 기본값으로 남아 있으면 backend 검증값이 `200M` 이더라도 업로드는 먼저 PHP 단계에서 막힙니다.
- backend 코드는 [../blog.backend/app/Http/Controllers/Api/V1/PostController.php](/Users/sm/Workspaces/Development/MyProject/blog/blog.backend/app/Http/Controllers/Api/V1/PostController.php:166) 에서 `config('posts.image_upload_max_kb')` 를 사용합니다.

적용 후 반영:

```bash
grep -E 'upload_max_filesize|post_max_size|memory_limit|max_execution_time' /etc/php/8.5/cli/php.ini
php -i | grep -E 'upload_max_filesize|post_max_size|memory_limit|max_execution_time'

sudo nginx -t
sudo systemctl reload nginx

cd /var/www/jaubi.co.kr/blog/blog.backend
php artisan optimize:clear
php artisan config:cache
sudo systemctl restart blog-backend
```

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
```

`MEDIA_DISK=s3` 기준이라면 `storage:link`는 업로드 파일 제공에 필수는 아닙니다.

주의:

- `db:seed --force` 는 생략하지 않습니다.
- `CommonCodeSeeder` 가 `common_codes` 테이블에 `client.type`, `post.status`, `post.category` 등을 채웁니다.
- 이 데이터가 없으면 `Client-Type: CT04P` 검증과 `/api/v1/base-data` 응답이 정상 동작하지 않습니다.
- 이 단계에서는 아직 `blog-backend.service` 파일을 배치하지 않았을 수 있으므로 `sudo systemctl restart blog-backend` 를 호출하지 않습니다.
- 최초 기동은 11단계에서 수행하고, 이후 `.env`, DB, 캐시를 바꾼 재배포에서는 `sudo systemctl restart blog-backend` 를 함께 수행합니다.

## 9. frontend 초기화

```bash
cd /var/www/jaubi.co.kr/blog/blog.frontend

yarn install --immutable
yarn build
```

## 10. 서버 설정 파일 배치

이 저장소에서 아래 파일 내용을 서버에 반영합니다.

- [deploy/ec2/systemd/blog-backend.service](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/deploy/ec2/systemd/blog-backend.service)
- [deploy/ec2/systemd/blog-scheduler.service](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/deploy/ec2/systemd/blog-scheduler.service)
- [deploy/ec2/systemd/blog-scheduler.timer](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/deploy/ec2/systemd/blog-scheduler.timer)
- [deploy/ec2/nginx/blog.conf](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/deploy/ec2/nginx/blog.conf)
- [deploy/ec2/scripts/common.sh](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/deploy/ec2/scripts/common.sh)
- [deploy/ec2/scripts/deploy-all.sh](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/deploy/ec2/scripts/deploy-all.sh)
- [deploy/ec2/scripts/deploy-backend.sh](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/deploy/ec2/scripts/deploy-backend.sh)
- [deploy/ec2/scripts/deploy-frontend.sh](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/deploy/ec2/scripts/deploy-frontend.sh)
- [deploy/ec2/scripts/deploy-status.sh](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/deploy/ec2/scripts/deploy-status.sh)

반영 위치:

- `/etc/systemd/system/blog-backend.service`
- `/etc/systemd/system/blog-scheduler.service`
- `/etc/systemd/system/blog-scheduler.timer`
- `/etc/nginx/sites-available/blog`
- `/opt/deploy/blog/common.sh`
- `/opt/deploy/blog/deploy-all.sh`
- `/opt/deploy/blog/deploy-backend.sh`
- `/opt/deploy/blog/deploy-frontend.sh`
- `/opt/deploy/blog/deploy-status.sh`

참고:

- PM2 실행 기준 파일은 서버의 `blog.frontend/ecosystem.config.cjs` 입니다.
- 배포 스크립트 동기화는 로컬 `make deploy-sync` 를 기본으로 사용합니다.

로컬에서 `scp` 업로드:

`~/.ssh/config` 에서 서버 별칭이 `jaubi-prod-app` 이고, 로컬 준비 파일 위치가 `~/Workspace/deploy/**` 라고 가정합니다.

```bash
cd ~/Workspace/deploy
scp -r ./ec2 jaubi-prod-app:~/Workspace/deploy/
```

서버에서 배치:

```bash
sudo cp ~/Workspace/deploy/ec2/systemd/blog-backend.service /etc/systemd/system/blog-backend.service
sudo cp ~/Workspace/deploy/ec2/systemd/blog-scheduler.service /etc/systemd/system/blog-scheduler.service
sudo cp ~/Workspace/deploy/ec2/systemd/blog-scheduler.timer /etc/systemd/system/blog-scheduler.timer
sudo cp ~/Workspace/deploy/ec2/nginx/blog.conf /etc/nginx/sites-available/blog
sudo mkdir -p /opt/deploy/blog
sudo cp ~/Workspace/deploy/ec2/scripts/common.sh /opt/deploy/blog/common.sh
sudo cp ~/Workspace/deploy/ec2/scripts/deploy-all.sh /opt/deploy/blog/deploy-all.sh
sudo cp ~/Workspace/deploy/ec2/scripts/deploy-backend.sh /opt/deploy/blog/deploy-backend.sh
sudo cp ~/Workspace/deploy/ec2/scripts/deploy-frontend.sh /opt/deploy/blog/deploy-frontend.sh
sudo cp ~/Workspace/deploy/ec2/scripts/deploy-status.sh /opt/deploy/blog/deploy-status.sh
sudo chown -R ubuntu:ubuntu /opt/deploy/blog
sudo chmod 755 /opt/deploy/blog/*.sh
```

주의:

- `deploy-backend.sh` 는 `sudo -n systemctl restart blog-backend` 를 사용합니다.
- 배포 계정에 비밀번호 없는 sudo 권한이 없다면 최소 권한으로 sudoers를 추가해야 합니다.

## 11. 서비스 기동

### 11-1. backend / scheduler

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

### 11-2. frontend PM2 등록

실제 실행 기준 파일은 `blog.frontend` 저장소 루트의 `ecosystem.config.cjs` 입니다.

이 워크스페이스의 [deploy/ec2/pm2/ecosystem.config.cjs](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/deploy/ec2/pm2/ecosystem.config.cjs:1) 는 참고용 템플릿입니다.

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

현재 서버는 root `40 GiB` 볼륨에서 PM2 로그를 관리하므로 위 값이면 충분합니다.

### 11-3. Nginx 반영

```bash
sudo ln -sf /etc/nginx/sites-available/blog /etc/nginx/sites-enabled/blog
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl enable --now nginx
sudo systemctl reload nginx
```

## 12. Certbot

```bash
sudo apt-get remove -y certbot
sudo apt install -y snapd
sudo systemctl enable --now snapd.socket
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

## 13. 배포 후 점검

```bash
ls -ld /var/www/jaubi.co.kr/blog
namei -l /var/www/jaubi.co.kr/blog/blog.backend
findmnt /data/mysql
findmnt /var/lib/mysql

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

## 14. 이후 재배포 절차

운영 재배포는 로컬 `make deploy-*` 를 기본 진입점으로 사용하고, 실제 배포는 서버 `/opt/deploy/blog/*.sh` 가 수행합니다.

기본 원칙:

- 배포 기준은 두 저장소 모두 `origin/main` 입니다.
- 둘 다 재배포할 때는 `backend -> frontend` 순서로 진행합니다.

권장 순서:

```bash
# 서버 배포 스크립트 동기화
make deploy-sync

# backend만 재배포
make deploy-backend

# frontend만 재배포
make deploy-frontend

# 둘 다 재배포
make deploy-all

# 마지막 배포 상태 확인
make deploy-status
```

자동 태그:

- `make deploy-backend` 성공 시 `../blog.backend` 에 `deploy/prod/backend/<timestamp>` 태그를 생성하고 `origin` 으로 push 합니다.
- `make deploy-frontend` 성공 시 `../blog.frontend` 에 `deploy/prod/frontend/<timestamp>` 태그를 생성하고 `origin` 으로 push 합니다.
- `make deploy-all` 은 같은 timestamp로 backend/frontend 태그를 각각 생성합니다.
- 배포는 성공했지만 태그 생성 또는 push가 실패하면 명령은 실패로 끝나며, 배포 자체는 롤백하지 않습니다.

서버에서 직접 실행해야 할 때:

```bash
/opt/deploy/blog/deploy-backend.sh
/opt/deploy/blog/deploy-frontend.sh
/opt/deploy/blog/deploy-all.sh
/opt/deploy/blog/deploy-status.sh
```

참고:

- 로컬 `make deploy-*` 는 내부적으로 [scripts/deploy-prod.sh](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/scripts/deploy-prod.sh:1) 를 호출합니다.
- Git 배포 태그 자동 생성은 로컬 `make deploy-*` 경로에서만 수행됩니다. 서버에서 `/opt/deploy/blog/*.sh` 를 직접 실행하면 태그는 남지 않습니다.

## 15. 운영 메모

- `blog-backend.service`는 현재 2 vCPU 서버 기준으로 Octane worker 수를 `2`로 맞췄습니다.
- 메모리 3.7 GiB에 swap이 꺼져 있으므로, 서버에서 직접 `yarn build`를 수행할 때 메모리 압박이 생기면 swap 2 GiB 추가나 CI 빌드 아티팩트 배포를 검토하는 편이 안전합니다.
