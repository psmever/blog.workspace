FROM php:8.3-fpm-alpine

# 필수 패키지 및 확장 설치
RUN apk add --no-cache \
    git unzip zip curl icu-dev libzip-dev openssl-dev autoconf g++ make oniguruma-dev brotli-dev \
    && docker-php-ext-install pdo pdo_mysql mbstring intl zip bcmath pcntl \
    && pecl install swoole \
    && docker-php-ext-enable swoole \
    && rm -rf /var/cache/apk/* /tmp/*

# 타임존 설정
RUN apk add --no-cache tzdata \
    && ln -snf /usr/share/zoneinfo/Asia/Seoul /etc/localtime \
    && echo "Asia/Seoul" > /etc/timezone

# Composer 복사
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# PHP 설정 복사
COPY php.ini /usr/local/etc/php/conf.d/99-custom.ini

# 워킹 디렉토리 설정
WORKDIR /var/www/html

# Entrypoint 추가 (Octane 실행)
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
