# AWS EC2 배포 가이드

이 문서는 `blog.backend`, `blog.frontend`, `blog.workspace` 3개 저장소를 같은 부모 디렉터리에 두고 EC2에서 배포하는 기준으로 작성되었습니다.

## 1. 보안 그룹

- 인바운드로 `22/tcp`(SSH), `80/tcp`(HTTP)만 우선 허용합니다.
- 도메인과 HTTPS를 붙일 계획이면 `443/tcp`도 함께 엽니다.
- `3000`, `4000`, `13306` 포트는 열지 않습니다. 프로덕션 구성은 Nginx만 외부에 공개합니다.
- Docker는 공개 포트를 열면 호스트 방화벽 규칙을 우회할 수 있으므로, 서버 방화벽보다 AWS 보안 그룹 기준으로 먼저 막는 편이 안전합니다.

## 2. Docker 설치

Docker 공식 Ubuntu 설치 문서 기준입니다.

```bash
sudo apt update
sudo apt install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc" | \
  sudo tee /etc/apt/sources.list.d/docker.sources > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker $USER
newgrp docker

docker --version
docker compose version
```

## 3. 디렉터리 구조 준비

`blog.workspace/README.md`에 적힌 상대 경로가 고정이라서 서버에서도 아래 구조를 맞춰야 합니다.

```text
~/apps/blog/
├── blog.backend
├── blog.frontend
└── blog.workspace
```

예시:

```bash
mkdir -p ~/apps/blog
cd ~/apps/blog

git clone <backend-repo-url> blog.backend
git clone <frontend-repo-url> blog.frontend
git clone <docker-repo-url> blog.workspace
```

## 4. 프로덕션 환경 변수 준비

### blog.workspace

`.env.production.example`을 기준으로 `blog.workspace/.env`를 만듭니다.

```dotenv
HTTP_PORT=80
NEXT_PUBLIC_API_URL=http://43.202.119.116
NEXT_PUBLIC_API_BASE_CLIENT_HEADER_CODE=CT04P
NEXT_PUBLIC_APP_NAME=My Blog
NEXT_PUBLIC_API_TIMEOUT=10000
NEXT_PUBLIC_DEBUG_MODE=false
NEXT_PUBLIC_SITE_URL=http://43.202.119.116
DB_DATABASE=blog
DB_USERNAME=blog
DB_PASSWORD=강한비밀번호
MARIADB_ROOT_PASSWORD=더강한루트비밀번호
```

### blog.backend

`blog.backend/.env` 주요 값은 최소한 아래를 맞춰야 합니다.

```dotenv
APP_ENV=production
APP_DEBUG=false
APP_URL=http://43.202.119.116

DB_CONNECTION=mysql
DB_HOST=mariadb
DB_PORT=3306
DB_DATABASE=blog
DB_USERNAME=blog
DB_PASSWORD=강한비밀번호

CORS_ALLOWED_ORIGINS=http://43.202.119.116
```

### blog.frontend

`blog.frontend/.env` 주요 값 예시:

```dotenv
NODE_ENV=production
NEXT_PUBLIC_API_URL=http://43.202.119.116
NEXT_PUBLIC_API_BASE_CLIENT_HEADER_CODE=CT04P
NEXT_PUBLIC_APP_NAME=My Blog
NEXT_PUBLIC_APP_ENV=production
NEXT_PUBLIC_API_TIMEOUT=10000
NEXT_PUBLIC_DEBUG_MODE=false
NEXT_PUBLIC_SITE_URL=http://43.202.119.116
```

## 5. 환경 파일 암호화

로컬에서 값을 채운 뒤 암호화 파일을 만들고 서버에 반영하는 흐름을 권장합니다.

```bash
cd blog.workspace
export BLOG_ENV_SECRET='여기에_강한_시크릿'
make env-encrypt-production
```

서버에서는 같은 `BLOG_ENV_SECRET` 값을 사용해야 합니다.

```bash
echo 'export BLOG_ENV_SECRET=여기에_강한_시크릿' >> ~/.bashrc
source ~/.bashrc
```

## 6. 실행

```bash
cd ~/apps/blog/blog.workspace
make prod-up
```

확인:

```bash
docker compose -f docker-compose.prod.yml ps
docker compose -f docker-compose.prod.yml logs -f
curl http://43.202.119.116/api/health
```

## 7. 운영 명령어

```bash
cd ~/apps/blog/blog.workspace

make prod-logs
make prod-build
make prod-down
```

## 8. 다음 단계

- 퍼블릭 IP 대신 도메인을 연결한 뒤 `APP_URL`, `NEXT_PUBLIC_API_URL`, `NEXT_PUBLIC_SITE_URL`, `CORS_ALLOWED_ORIGINS`를 도메인 기준으로 바꾸는 편이 낫습니다.
- HTTPS를 붙일 때는 `443/tcp`를 열고 리버스 프록시에 인증서를 연결하면 됩니다.
