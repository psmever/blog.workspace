ARG PHP_BASE_IMAGE=php:8.5.4-cli-alpine

FROM ${PHP_BASE_IMAGE}

ARG SWOOLE_VERSION=6.2.1

# 필수 패키지 및 확장 설치
RUN apk add --no-cache \
    $PHPIZE_DEPS curl git icu-dev libzip-dev linux-headers openssl-dev \
    tzdata unzip zip \
    && docker-php-ext-install bcmath intl pcntl pdo_mysql sockets zip \
    && printf '%s\n' \
        'yes' \
        '' \
        '' \
        '' \
        '' \
        'no' \
        '' \
        '' \
        '' \
        '' \
        '' \
        '' \
        '' \
        '' \
        '' \
        '' \
        '' \
        '' \
        '' \
    | pecl install swoole-${SWOOLE_VERSION} \
    && docker-php-ext-enable swoole \
    && ln -snf /usr/share/zoneinfo/Asia/Seoul /etc/localtime \
    && echo "Asia/Seoul" > /etc/timezone \
    && rm -rf /tmp/pear /var/cache/apk/*

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
