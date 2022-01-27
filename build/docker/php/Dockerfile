ARG GOLANG_VERSION="1.17.3"
ARG PHP_VERSION="8.1"

#FROM "golang:${GOLANG_VERSION}-alpine" AS rrbuilder
#
#ARG ROADRUNNER_VERSION="2.7.4"
#RUN    set -x \
#    && apk add --no-cache --virtual '.roadrunner-build-deps' build-base gcc git musl-dev \
#    && mkdir -p '/tmp/rr' \
#    && git clone 'git://github.com/spiral/roadrunner-binary.git' --branch "v${ROADRUNNER_VERSION}" '/tmp/rr' \
#    && cd '/tmp/rr' \
#    && git tag --points-at HEAD \
#    && CGO_ENABLED=0 GOOS="linux" go build -trimpath -a \
#        -o "/sbin/rr" \
#        -ldflags "-X github.com/spiral/roadrunner-binary/v2/internal/meta.version=${ROADRUNNER_VERSION} \
#                  -X github.com/spiral/roadrunner-binary/v2/internal/meta.buildTime=$(date +%FT%T%z) \
#                  -linkmode external \
#                  -extldflags -static \
#                  -s" \
#        './cmd/rr/main.go' \
#    && "/sbin/rr" -v \
#    && rm -rf '/tmp/rr' \
#    && apk del '.roadrunner-build-deps'

FROM "php:${PHP_VERSION}-fpm-alpine" AS development
MAINTAINER Zan Baldwin "hello@zanbaldwin.com"

## Compiles a statically-linked version of the init (PID 1) process bundled with Docker since v1.13 (API v1.25).
## Alpine uses musl instead of glibc, so it's best not to use the dynamically-linked version.
## See https://github.com/krallin/tini/issues/8#issuecomment-146135930
RUN    apk add --no-cache --virtual .tini-build-deps cmake gcc git libc-dev make \
    && git clone 'git://github.com/krallin/tini.git' '/tmp/tini' \
    && ( \
        cd '/tmp/tini'; \
        git checkout "$(git describe --tags)"; \
        export CFLAGS='-DPR_SET_CHILD_SUBREAPER=36 -DPR_GET_CHILD_SUBREAPER=37'; \
        cmake . && make; \
    ) \
    && mv '/tmp/tini/tini-static' '/tini' && chmod +x '/tini' \
    && rm -rf '/tmp/tini' \
    && apk del '.tini-build-deps'
ENTRYPOINT [ "/tini", "--" ]

## Install all standardised PHP extensions (zip files, image manipulation, caching, database access, etc) that
## WordPress plugins are likely to use.
## Runtime dependencies detection snippet from dunglas/symfony-docker.
RUN    apk add --no-cache --virtual '.extension-build-deps' \
        $PHPIZE_DEPS giflib-dev gmp-dev icu-dev imagemagick-dev libffi-dev \
        libjpeg-turbo-dev libpng-dev libwebp-dev libzip-dev rabbitmq-c-dev zlib-dev \
    && docker-php-ext-configure gd --with-jpeg --with-webp \
    && docker-php-ext-configure zip \
    && docker-php-ext-install -j$(nproc) \
        exif ffi gd gmp intl pdo_mysql zip \
    && pecl install amqp && docker-php-ext-enable amqp \
    && pecl install imagick && docker-php-ext-enable imagick \
    && pecl install redis && docker-php-ext-enable redis \
    && docker-php-ext-enable opcache \
    && { \
        echo 'opcache.enable_cli = 1'; \
    } > '/usr/local/etc/php/conf.d/cli-opcache.ini' \
    && apk del '.extension-build-deps' \
    && EXT_RUN_DEPS="$(scanelf --needed --nobanner --format '%n#p' --recursive /usr/local/lib/php/extensions \
        | tr ',' '\n' | sort -u \
        | awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
    )" \
    && apk add --no-cache --upgrade --virtual '.extension-runtime-deps' $EXT_RUN_DEPS ca-certificates gnu-libiconv
## Install gnu-libiconv and set LD_PRELOAD env to make iconv work fully on Alpine Linux.
## see https://github.com/docker-library/php/issues/240#issuecomment-763112749
ENV LD_PRELOAD "/usr/lib/preloadable_libiconv.so"

## See https://getcomposer.org/doc/03-cli.md#composer-allow-superuser
ENV COMPOSER_ALLOW_SUPERUSER=1
## See https://github.com/composer/docker/blob/master/1.8/Dockerfile
RUN    curl --silent --fail --location --retry 3 --output '/tmp/installer.sig' --url 'https://composer.github.io/installer.sig' \
    && curl --silent --fail --location --retry 3 --output '/tmp/installer.php' --url 'https://getcomposer.org/installer' \
    && php -r 'if (hash_file("sha384", "/tmp/installer.php") === file_get_contents("/tmp/installer.sig")) { echo "Installer verified." . PHP_EOL; } else { echo "Installer corrupt." . PHP_EOL; exit(1); }' \
    && php '/tmp/installer.php' --no-ansi --install-dir='/sbin' --filename='composer' \
    && rm -f '/tmp/installer.sig' '/tmp/installer.php'

## Install XDebug if enabled in the Docker build args
ARG ENABLE_XDEBUG=""
RUN if [ ! -z "${ENABLE_XDEBUG}" ]; then \
           apk add --no-cache --virtual '.xdebug-build-deps' $PHPIZE_DEPS \
        && pecl install xdebug && docker-php-ext-enable xdebug \
        && apk del '.xdebug-build-deps' \
        && { \
            echo '[XDebug]'; \
            echo 'xdebug.mode=develop,debug'; \
            echo 'xdebug.start_with_request=yes'; \
            echo 'xdebug.client_port=9003'; \
            echo 'xdebug.discover_client_host=1'; \
            echo 'xdebug.client_host=host.docker.internal'; \
        } > '/usr/local/etc/php/conf.d/xdebug-from-host.ini'; \
    fi

## Docker's internal container healthcheck.
COPY "./healthcheck.sh" "/sbin/healthcheck"
RUN apk add --no-cache --virtual '.healthcheck-runtime-deps' curl fcgi
HEALTHCHECK --interval=10s --timeout=3s --retries=3 CMD [ "sh", "/sbin/healthcheck" ]

## Create a new user with UID#1000 (the UID that the user on the host machine is likely to have).
## Instruct PHP to run as that user.
ARG PHP_USER="php"
ENV PHP_USER="${PHP_USER}"
RUN    apk add --no-cache --virtual .user-build-deps shadow \
    && (userdel 'www-data' || true) \
    && useradd --no-create-home --uid 1000 --user-group "${PHP_USER}" \
    && sed -i -e "s/www-data/${PHP_USER}/g" '/usr/local/etc/php-fpm.d/www.conf' \
    && apk del '.user-build-deps'
COPY './php.ini' '/usr/local/etc/php/php.ini'
COPY './emergency_restart.conf' '/usr/local/etc/php-fpm.d/emergency_restart.conf'
## Define the user to use *AFTER* we've copied over files as root.
USER "${PHP_USER}"
WORKDIR '/srv'

## Copy over the RoadRunner binary from the Golang Builder earlier.
# COPY './rr.yaml' '/etc/rr.yaml'
# COPY --from='rrbuilder' '/sbin/rr' '/sbin/rr'
## Expose RoadRunner over Proxy
# EXPOSE 80
## Example Command for RoadRunner
# CMD [ "/sbin/rr", "serve", "-w", "/srv", "-c", "/etc/rr.yaml", "--dotenv", "/srv/.env", "--debug" ]

## Expose PHP-FPM over FastCGI
EXPOSE 9000
CMD [ "php-fpm", "--nodaemonize" ]
