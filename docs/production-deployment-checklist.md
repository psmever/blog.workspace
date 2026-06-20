# 상용 배포 체크리스트

이 문서는 EC2에 SSH 접속을 마친 뒤 실제 배포 작업을 순서대로 확인하는 빠른 체크리스트입니다.

키 페어, 보안 그룹, IAM, 비밀값 보관 정책 같은 보안 항목은 여기서 다루지 않습니다.

## 현재 기준

- frontend: `blog.jaubi.co.kr` -> Next.js (`127.0.0.1:3000`)
- backend: `blog.api.jaubi.co.kr` -> Laravel Octane (`127.0.0.1:4000`)
- reverse proxy: `Nginx`
- backend process: `systemd`
- frontend process: `PM2`
- TLS: `Certbot`
- 배포 경로: `/var/www/jaubi.co.kr/blog/{blog.backend,blog.frontend}`
- 서버 스펙: `2 vCPU / 3.7 GiB RAM / Ubuntu 26.04 / root 40 GiB gp3 / data 80 GiB gp3`
- 현재 backend lock 호환 PHP 범위: `8.1 - 8.4`
- 업로드 스토리지: `AWS S3`
- CDN: `CloudFront 예정`

## 운영 원칙

- 실제 배포 로직은 서버 `/opt/deploy/blog/*.sh` 에 둡니다.
- 로컬 `make deploy-*` 를 SSH 진입점으로 사용합니다.
- `backend`, `frontend` 모두 서버에서 `origin/develop` 을 `main` 에 `--no-ff` 로 병합하고 `origin/main` 으로 push한 뒤 배포합니다.
- 서버 병합 충돌 또는 push 실패 시 서버 `main` 을 병합 전 커밋으로 원복하고 빌드 전에 배포를 중단합니다.
- `origin/develop` 에 `main` 미반영 커밋이 없으면 병합, push, 배포 태그 생성을 생략하고 현재 서버 `main` 커밋을 재배포합니다.
- 서버 Git remote는 backend/frontend 각 저장소에 대한 fetch, `main` push, tag push 권한이 필요합니다.
- 실행 중에는 전체 순서도와 단계별 분기 사유를 화면에 출력합니다.
- 둘 다 반영할 때는 `backend -> frontend` 순서로 배포합니다.
- PM2 실행 기준 파일은 `blog.frontend/ecosystem.config.cjs` 입니다.
- 워크스페이스의 [deploy/ec2/pm2/ecosystem.config.cjs](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/deploy/ec2/pm2/ecosystem.config.cjs:1) 는 참고용 템플릿입니다.
- `deploy-backend.sh`, `deploy-frontend.sh` 는 각 저장소에서 `develop` 을 `main` 으로 승격한 뒤 배포합니다.
- `deploy-all.sh` 는 인자를 받지 않고 backend, frontend 순서로 각 저장소의 `main` 브랜치를 반영합니다.

## 준비 자료

- 상세 운영 가이드: [docs/aws-ec2.md](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/docs/aws-ec2.md:1)
- backend env 템플릿: [deploy/ec2/env/backend.production.env.example](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/deploy/ec2/env/backend.production.env.example:1)
- frontend env 템플릿: [deploy/ec2/env/frontend.production.env.example](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/deploy/ec2/env/frontend.production.env.example:1)
- Nginx 템플릿: [deploy/ec2/nginx/blog.conf](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/deploy/ec2/nginx/blog.conf:1)
- backend service: [deploy/ec2/systemd/blog-backend.service](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/deploy/ec2/systemd/blog-backend.service:1)
- scheduler service: [deploy/ec2/systemd/blog-scheduler.service](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/deploy/ec2/systemd/blog-scheduler.service:1)
- scheduler timer: [deploy/ec2/systemd/blog-scheduler.timer](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/deploy/ec2/systemd/blog-scheduler.timer:1)
- deploy scripts: [deploy/ec2/scripts/common.sh](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/deploy/ec2/scripts/common.sh:1), [deploy/ec2/scripts/deploy-all.sh](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/deploy/ec2/scripts/deploy-all.sh:1), [deploy/ec2/scripts/deploy-backend.sh](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/deploy/ec2/scripts/deploy-backend.sh:1), [deploy/ec2/scripts/deploy-frontend.sh](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/deploy/ec2/scripts/deploy-frontend.sh:1), [deploy/ec2/scripts/deploy-status.sh](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/deploy/ec2/scripts/deploy-status.sh:1)
- PHP 8.5 backend 인계 문서: [docs/backend-php85-handoff.md](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/docs/backend-php85-handoff.md:1)

## 첫 배포 순서

1. timezone을 `Asia/Seoul`로 설정합니다.
2. `sudo apt update`, `sudo apt -y upgrade` 후 `Nginx`, `mariadb`, `PHP`, `Composer`, `Node 20`, `PM2`, `Swoole` 설치를 끝냅니다.
   현재 backend lock 기준으로는 `PHP 8.4 이하`가 바로 호환됩니다.
3. `lsblk` 로 추가 EBS data 볼륨을 확인하고 `ext4 -> /data/mysql -> /var/lib/mysql bind mount` 순서로 준비합니다.
4. `/var/www/jaubi.co.kr/blog` 아래에 `blog.backend`, `blog.frontend` 저장소를 원격 `main` 브랜치만 clone 해서 배치합니다.
5. MariaDB를 기동하고 DB/사용자를 초기화합니다.
6. backend/frontend 프로덕션 환경 변수를 작성합니다.
   이미지 업로드를 `200M` 로 운영할 경우 backend `.env`, Nginx, PHP 설정을 함께 맞춥니다.
7. backend에서 `composer install`, `key:generate`, `migrate`, `db:seed`, `config:cache`, `route:cache`를 수행합니다.
8. frontend에서 `yarn install --immutable`, `yarn build`를 수행합니다.
9. `systemd`, `Nginx`, 배포 스크립트 파일을 서버에 반영합니다.
10. `blog-backend`, `blog-scheduler.timer`, `blog-frontend`, `nginx`를 기동합니다.
11. `certbot --nginx`로 인증서를 발급합니다.
12. 헬스체크와 서비스 상태를 검증합니다.

## 이후 재배포

- 먼저 배포 스크립트 동기화: `make deploy-sync`
- backend만 배포: `make deploy-backend`
- frontend만 배포: `make deploy-frontend`
- 둘 다 배포: `make deploy-all`
- 마지막 배포 상태 확인: `make deploy-status`
- 신규 커밋 승격 배포가 성공하면 서버가 `deploy/prod/<app>/<timestamp>` Git tag를 해당 앱 저장소 `origin` 으로 push

```bash
make deploy-sync
make deploy-backend
make deploy-frontend
make deploy-all
make deploy-status
```

- 내부 구현은 [scripts/deploy-prod.sh](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/scripts/deploy-prod.sh:1) 가 맡고, 필요하면 서버에서 `/opt/deploy/blog/deploy-backend.sh`, `/opt/deploy/blog/deploy-frontend.sh`, `/opt/deploy/blog/deploy-all.sh`, `/opt/deploy/blog/deploy-status.sh` 를 직접 실행할 수도 있습니다.
- Git 배포 태그는 서버 배포 스크립트가 신규 승격 배포 성공 후 생성합니다.

## 최종 점검

- backend/frontend `.env` 작성 완료 확인
- `POST_IMAGE_MAX_KB=204800` 확인
- `grep -E 'upload_max_filesize|post_max_size' /etc/php/8.5/cli/php.ini`
- `grep client_max_body_size /etc/nginx/sites-available/blog`
- `findmnt /data/mysql`
- `findmnt /var/lib/mysql`
- `systemctl status mariadb --no-pager`
- `systemctl status blog-backend`
- `systemctl status blog-scheduler.timer`
- `pm2 status`
- `sudo nginx -t`
- `curl -H "Client-Type: CT04P" http://127.0.0.1:4000/api/health`
- `curl -H "Host: blog.jaubi.co.kr" http://127.0.0.1`
- `curl -H "Host: blog.api.jaubi.co.kr" -H "Client-Type: CT04P" http://127.0.0.1/api/health`
- `curl https://blog.jaubi.co.kr`
- `curl -H "Client-Type: CT04P" https://blog.api.jaubi.co.kr/api/health`

`/api/*` 요청은 `Client-Type` 헤더가 없으면 `400 Bad Request` 가 나오는 것이 정상입니다.
`common_codes` 시드가 없으면 `Client-Type` 검증과 `/api/v1/base-data` 가 정상 동작하지 않습니다.
최초 배포에서는 `blog-backend` 를 10단계에서 처음 기동하고, 이후 `.env` 또는 DB 설정을 바꾼 재배포에서는 `sudo systemctl restart blog-backend` 를 함께 수행합니다.
`composer install` 이 `nette/schema ... php 8.1 - 8.4` 오류로 실패하면 현재 서버 PHP가 `8.5`인 상태일 가능성이 큽니다. 이 경우 서버 PHP를 `8.4 이하`로 맞추거나, Backend 채팅에서 `composer.lock` 갱신 작업을 먼저 진행해야 합니다.
`PHP 8.5` 유지 전제로 진행할 때는 [docs/backend-php85-handoff.md](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/docs/backend-php85-handoff.md:1) 의 전달 문구를 그대로 backend 채팅에 보내면 됩니다.
