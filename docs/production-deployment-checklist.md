# 상용 배포 체크리스트

이 문서는 현재 상용 배포 기준과 실제 진행 순서를 한 번에 확인하기 위한 빠른 체크리스트입니다.

## 현재 기준

- frontend: `blog.jaubi.co.kr` -> Next.js (`127.0.0.1:3000`)
- backend: `blog.api.jaubi.co.kr` -> Laravel Octane (`127.0.0.1:4000`)
- reverse proxy: `Nginx`
- backend process: `systemd`
- frontend process: `PM2`
- TLS: `Certbot`
- 배포 경로: `/var/www/jaubi.co.kr/blog/{blog.backend,blog.frontend}`
- 서버 스펙: `2 vCPU / 3.7 GB RAM / 48 GB SSD / Ubuntu 24.04.4`
- 업로드 스토리지: `AWS S3`
- CDN: `CloudFront 예정`

## 기준 문서

- 전체 절차: [docs/aws-ec2.md](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/docs/aws-ec2.md:1)
- backend env 템플릿: [deploy/ec2/env/backend.production.env.example](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/deploy/ec2/env/backend.production.env.example:1)
- frontend env 템플릿: [deploy/ec2/env/frontend.production.env.example](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/deploy/ec2/env/frontend.production.env.example:1)
- Nginx 템플릿: [deploy/ec2/nginx/blog.conf](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/deploy/ec2/nginx/blog.conf:1)
- backend service: [deploy/ec2/systemd/blog-backend.service](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/deploy/ec2/systemd/blog-backend.service:1)
- scheduler service: [deploy/ec2/systemd/blog-scheduler.service](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/deploy/ec2/systemd/blog-scheduler.service:1)
- scheduler timer: [deploy/ec2/systemd/blog-scheduler.timer](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/deploy/ec2/systemd/blog-scheduler.timer:1)
- frontend PM2: [deploy/ec2/pm2/ecosystem.config.cjs](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/deploy/ec2/pm2/ecosystem.config.cjs:1)
- deploy scripts: [deploy/ec2/scripts/deploy-backend.sh](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/deploy/ec2/scripts/deploy-backend.sh:1), [deploy/ec2/scripts/deploy-frontend.sh](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/deploy/ec2/scripts/deploy-frontend.sh:1), [deploy/ec2/scripts/deploy-all.sh](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/deploy/ec2/scripts/deploy-all.sh:1)

## 사전 결정 사항

- backend URL: `https://blog.api.jaubi.co.kr`
- frontend URL: `https://blog.jaubi.co.kr`
- 첫 상용 배포의 업로드 디스크: `MEDIA_DISK=s3`
- 외부 오픈 포트: `22`, `80`, `443`
- 현재 문서 범위: `backend`, `frontend`
- `blog.manager`는 별도 저장소/배포 템플릿 준비 후 추가

## 진행 순서

1. 서버 접속 직후 timezone을 `Asia/Seoul`로 설정합니다.
2. EC2 인스턴스와 보안 그룹을 준비합니다.
3. 서버에 `Nginx`, `mariadb`, `PHP 8.3`, `Node 20`, `PM2`, `Certbot`을 설치합니다.
4. `/var/www/jaubi.co.kr/blog` 아래에 `blog.backend`, `blog.frontend` 저장소를 배치합니다.
5. env 템플릿을 기준으로 backend/frontend 프로덕션 환경 변수를 채웁니다.
6. backend에서 `composer install`, `key:generate`, `migrate`, `db:seed`, `config:cache`, `route:cache`, `blog-backend 재시작`을 수행합니다.
7. frontend에서 `yarn install --immutable`, `yarn build`를 수행합니다.
8. `systemd`, `PM2`, `pm2-logrotate`, `Nginx` 설정 파일을 서버에 반영합니다.
9. `blog-backend`, `blog-scheduler.timer`, `blog-frontend`를 기동합니다.
10. `certbot --nginx`로 인증서를 발급합니다.
11. 헬스체크와 서비스 상태를 검증합니다.

이후 운영 배포는 로컬 [scripts/deploy-prod.sh](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/scripts/deploy-prod.sh:1) 에서 SSH로 서버 `/opt/deploy/blog/*.sh` 를 호출하는 방식을 기준으로 합니다.

## 최종 점검

- 새 인스턴스 기준으로 `APP_KEY`, `DB_PASSWORD`, `ADMIN_LOGIN_PASSWORD`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`를 모두 새 값으로 교체
- 운영 env 암호화 키는 `BLOG_ENV_PRODUCTION_SECRET`로 별도 관리하고 로컬 env 암호화 키와 공유하지 않음
- `.env.production.enc`와 실제 `.env`가 Git 추적 대상이 아닌지 확인
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
`Laravel Octane` 은 `.env`/DB 변경 후 기존 워커가 예전 상태를 유지할 수 있으므로 `sudo systemctl restart blog-backend` 를 함께 수행합니다.
