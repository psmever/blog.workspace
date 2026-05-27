# Blog Backend PHP 8.5 대응 인계 문서

이 문서는 `Ubuntu 26.04 + PHP 8.5` 운영 기준으로 배포를 진행하려고 할 때, `blog.backend` 저장소에서 먼저 처리해야 할 작업을 정리한 인계 문서입니다.

이 워크스페이스에서는 backend 애플리케이션 코드를 수정하지 않습니다. 실제 수정은 Blog Backend 프로젝트 채팅에서 진행해야 합니다.

## 현재 상황

- 운영 서버 OS: `Ubuntu 26.04`
- 서버 PHP: `8.5.4`
- 배포 시도 명령:

```bash
composer install --no-dev --optimize-autoloader
```

- 실제 오류:

```text
nette/schema v1.3.2 requires php 8.1 - 8.4
your php version (8.5.4) does not satisfy that requirement
```

## 원인 요약

- [../blog.backend/composer.json](/Users/sm/Workspaces/Development/MyProject/blog/blog.backend/composer.json:12) 의 루트 조건은 `php ^8.2` 입니다.
- 하지만 실제 설치는 [../blog.backend/composer.lock](/Users/sm/Workspaces/Development/MyProject/blog/blog.backend/composer.lock:2735) 의 고정 버전을 따릅니다.
- 현재 lock 파일에는 `nette/schema v1.3.2` 가 들어 있고, [../blog.backend/composer.lock](/Users/sm/Workspaces/Development/MyProject/blog/blog.backend/composer.lock:2750) 기준으로 `php 8.1 - 8.4` 만 허용합니다.
- 또 [../blog.backend/composer.lock](/Users/sm/Workspaces/Development/MyProject/blog/blog.backend/composer.lock:1962) 의 `league/config v1.2.0` 은 `nette/schema ^1.2` 를 요구합니다.

정리하면:

- 루트 `composer.json` 만 보면 `PHP 8.5` 도 가능해 보입니다.
- 하지만 현재 `composer.lock` 기준으로는 `PHP 8.5`에서 `composer install` 이 실패합니다.
- 따라서 backend 저장소에서 의존성 갱신과 lock 파일 재생성이 먼저 필요합니다.

## backend 저장소에서 해야 할 일

1. `PHP 8.5` 환경에서 `composer update` 로 관련 의존성을 다시 해석합니다.
2. 최소 범위로는 `nette/schema`, `league/config` 부터 점검합니다.
3. 갱신된 lock 파일 기준으로 테스트와 부트 확인을 합니다.
4. 문제 없으면 `composer.lock` 변경을 포함해 커밋합니다.

## backend 채팅에 전달할 작업 범위

- 목표: `Ubuntu 26.04 / PHP 8.5` 에서 `composer install --no-dev --optimize-autoloader` 가 성공해야 함
- 우선 점검 패키지:
  - `nette/schema`
  - `league/config`
- 기대 결과:
  - `composer install` 성공
  - `php artisan` 기본 부트 성공
  - 테스트 또는 최소 스모크 체크 성공
  - 갱신된 `composer.lock` 커밋

## backend 채팅에 그대로 보낼 문구

아래 문구를 Blog Backend 프로젝트 채팅에 그대로 보내면 됩니다.

```text
Ubuntu 26.04 / PHP 8.5 기준으로 운영 배포를 진행하려고 합니다.

현재 EC2 서버에서 composer install --no-dev --optimize-autoloader 실행 시 아래 오류가 납니다.

nette/schema v1.3.2 requires php 8.1 - 8.4
your php version (8.5.4) does not satisfy that requirement

확인한 내용:
- composer.json 루트 조건은 php ^8.2
- composer.lock 에 nette/schema v1.3.2 가 고정되어 있고 php 8.1 - 8.4 만 허용
- league/config v1.2.0 이 nette/schema ^1.2 를 요구

요청:
1. PHP 8.5 환경에서 composer 의존성 갱신
2. nette/schema, league/config 포함 lock 파일 재생성
3. composer install 성공 확인
4. php artisan 부트와 테스트 또는 최소 스모크 체크
5. 변경 내용 커밋

이 작업은 Ubuntu 26.04 / PHP 8.5 서버 배포를 위한 선행 작업입니다.
```

## backend 쪽에서 확인하면 좋은 명령

이 명령은 backend 저장소에서 실행하는 기준입니다.

```bash
composer show nette/schema league/config
composer update nette/schema league/config --with-all-dependencies
composer install
php artisan --version
php artisan route:list > /dev/null
composer test
```

주의:

- 어떤 패키지가 같이 올라갈지는 `composer` 해결 결과에 따라 달라질 수 있습니다.
- 따라서 이 문서에서는 특정 최종 버전을 고정해서 지시하지 않습니다.
- 핵심은 `PHP 8.5`에서 설치 가능한 lock 파일을 backend 저장소에서 다시 만드는 것입니다.

## 워크스페이스 쪽 후속 작업

backend 저장소에서 `composer.lock` 갱신이 끝나면, 이 워크스페이스에서는 아래만 다시 확인하면 됩니다.

1. EC2 서버에서 `git pull`
2. `composer install --no-dev --optimize-autoloader`
3. `php artisan migrate --force`
4. `php artisan db:seed --force`
5. `sudo systemctl restart blog-backend`

이 이후 절차는 [docs/aws-ec2.md](/Users/sm/Workspaces/Development/MyProject/blog/blog.workspace/docs/aws-ec2.md:1) 기준을 그대로 따르면 됩니다.
