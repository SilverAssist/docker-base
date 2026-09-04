# syntax=docker/dockerfile:1.7
#
# silverassist/wp-base — runtime platform for the WordPress sites.
#
# Contains everything the 12 WordPress projects had duplicated in their own
# Dockerfiles: nginx, PHP 8.3 with the full extension set, php-fpm, supervisor,
# Composer and WP-CLI. It deliberately does NOT contain WordPress core, the
# site's nginx server block, or any project dependency — those differ per
# project and per deploy, so they stay in the consuming Dockerfile.
#
# Every external artifact is pinned by digest or verified by checksum. That is
# the whole point of this image: an upstream release must never be able to
# change a production build without a commit here first.

ARG NGINX_IMAGE=nginx:1.31-alpine@sha256:72ba65eb42c10344912a84ff42408db7d34f2feb642204570ab8fc5ffd29f1d3

FROM ${NGINX_IMAGE}

# Pinned tool versions. Bump these in a PR, never implicitly at build time.
ARG COMPOSER_VERSION=2.10.3
ARG COMPOSER_SHA256=7a2d379d5b8ffdaa028580ef26494c36d2feef4b178d3dd1473a4dbc5e17c8d6
ARG WP_CLI_VERSION=2.12.0
ARG WP_CLI_SHA256=ce34ddd838f7351d6759068d09793f26755463b4a4610a5a5c0a97b68220d85c

# Build metadata, injected by CI (see .github/workflows/build-wp-base.yml).
ARG IMAGE_VERSION=dev
ARG VCS_REF=unknown
ARG BUILD_DATE=unknown

LABEL org.opencontainers.image.title="silverassist/wp-base" \
      org.opencontainers.image.description="nginx + PHP 8.3 + Composer + WP-CLI base image for SilverAssist WordPress sites" \
      org.opencontainers.image.vendor="SilverAssist" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.source="https://github.com/SilverAssist/docker-base" \
      org.opencontainers.image.documentation="https://github.com/SilverAssist/docker-base/blob/main/images/wp-base/README.md" \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.created="${BUILD_DATE}"

# Fail a RUN when any stage of a pipe fails, not just the last one — the
# checksum verifications below pipe into sha256sum.
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]

# PHP 8.3 runtime and the extension set shared by all 12 sites.
#
# git is required by Composer to clone a package when a dist archive is
# unavailable; without it a single failed GitHub zipball aborts the install.
RUN apk add --no-cache \
        php83 php83-fpm php83-cli php83-common php83-pear php83-phar \
        php83-bcmath php83-ctype php83-curl php83-dom php83-exif php83-fileinfo \
        php83-ftp php83-gd php83-iconv php83-intl php83-json php83-mbstring \
        php83-mysqli php83-mysqlnd php83-opcache php83-openssl php83-pdo \
        php83-pdo_mysql php83-session php83-simplexml php83-sodium \
        php83-tokenizer php83-xml php83-xmlreader php83-xmlwriter php83-zip \
        php83-zlib \
        php83-pecl-imagick php83-pecl-redis \
        bash curl git libc6-compat pcre supervisor unzip \
    && ln -s /usr/bin/php83 /usr/bin/php

# Composer, pinned and checksum-verified.
#
# --retry: a transient TLS or gateway error here fails the whole base image
# build. That is the exact failure mode this image exists to remove, so it
# must not be reintroduced by its own bootstrap.
RUN curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors -o /tmp/composer.phar \
        "https://getcomposer.org/download/${COMPOSER_VERSION}/composer.phar" \
    && echo "${COMPOSER_SHA256}  /tmp/composer.phar" | sha256sum -c - \
    && mv /tmp/composer.phar /usr/local/bin/composer \
    && chmod +x /usr/local/bin/composer \
    && composer --version --no-interaction

# WP-CLI, pinned and checksum-verified.
RUN curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors -o /tmp/wp-cli.phar \
        "https://github.com/wp-cli/wp-cli/releases/download/v${WP_CLI_VERSION}/wp-cli-${WP_CLI_VERSION}.phar" \
    && echo "${WP_CLI_SHA256}  /tmp/wp-cli.phar" | sha256sum -c - \
    && mv /tmp/wp-cli.phar /usr/local/bin/wp \
    && chmod +x /usr/local/bin/wp \
    && wp --info --allow-root

# Platform defaults. Projects override without reproducing these whole files:
#   php.ini   -> drop /etc/php83/conf.d/99-<project>.ini
#   www.conf  -> drop /etc/php83/php-fpm.d/99-<project>.conf (php-fpm.conf globs it)
#   nginx     -> add the site server block at /etc/nginx/conf.d/<site>.conf
COPY conf/nginx.conf /etc/nginx/nginx.conf
COPY conf/php.ini /etc/php83/php.ini
COPY conf/php-fpm.conf /etc/php83/php-fpm.conf
COPY conf/www.conf /etc/php83/php-fpm.d/www.conf
COPY conf/supervisord.conf /etc/supervisord.conf

# Composer wrapper that retries transient registry failures. Projects call this
# instead of `composer install` so the retry policy lives in one place.
COPY bin/composer-install /usr/local/bin/composer-install
RUN chmod +x /usr/local/bin/composer-install

# The stock nginx image ships a default server block that would shadow the
# site's own; disable rather than delete so it stays inspectable.
RUN mv /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/default.conf.disabled \
    && mkdir -p /run/php-fpm /var/log/php-fpm /var/www/html /etc/supervisor/conf.d \
    && touch /run/php-fpm/php-fpm.pid \
    && ln -sf /dev/stdout /var/log/nginx/access.log \
    && ln -sf /dev/stderr /var/log/nginx/error.log \
    && ln -sf /dev/stdout /var/log/php-fpm/error.log \
    && ln -sf /dev/stderr /var/log/php-fpm/www-error.log

# Composer runs as root in an image build; silence the advisory rather than
# have every project's build log carry the warning.
ENV COMPOSER_ALLOW_SUPERUSER=1 \
    COMPOSER_NO_INTERACTION=1 \
    COMPOSER_HOME=/tmp/composer

WORKDIR /var/www/html
EXPOSE 80

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
