# syntax=docker/dockerfile:1.7
#
# silverassist/next-base — build and runtime platforms for the Next.js sites.
#
# Two targets, published as two tags:
#
#   next-base:<v>-builder   node + the native-module toolchain, for `npm ci`
#                           and `next build`
#   next-base:<v>           nginx + a real node runtime + supervisor, for the
#                           final stage
#
# The runtime target starts from node and adds nginx, rather than starting from
# nginx and copying /usr/lib and /usr/local/bin out of a node stage the way the
# project Dockerfiles do today. That copy moves an unversioned pile of shared
# objects between images and breaks quietly whenever either base shifts; here
# the node runtime is the one apk/npm installed and nothing is smuggled across.

ARG NODE_IMAGE=node:24.20.0-alpine3.24@sha256:e67514e5d0f6c46656005e1b693b2ec9d52e80b641307de684d4a015ba7a4eaf

# ---------------------------------------------------------------------------
# builder — dependency install and `next build`
# ---------------------------------------------------------------------------
FROM ${NODE_IMAGE} AS builder

ARG IMAGE_VERSION=dev
ARG VCS_REF=unknown
ARG BUILD_DATE=unknown

LABEL org.opencontainers.image.title="silverassist/next-base (builder)" \
      org.opencontainers.image.description="Node 24 + native module toolchain for building SilverAssist Next.js sites" \
      org.opencontainers.image.vendor="SilverAssist" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.source="https://github.com/SilverAssist/docker-base" \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.created="${BUILD_DATE}"

# libc6-compat: glibc shim the Next.js SWC binaries need on musl.
# git + openssh: git-referenced and private npm dependencies.
# python3/make/g++: node-gyp, for any dependency without a musl prebuild.
RUN apk add --no-cache \
        libc6-compat git bash openssh \
        python3 make g++

ENV NEXT_TELEMETRY_DISABLED=1
WORKDIR /app

# ---------------------------------------------------------------------------
# runtime — nginx in front of the Next.js server, both under supervisor
# ---------------------------------------------------------------------------
FROM ${NODE_IMAGE} AS runtime

ARG IMAGE_VERSION=dev
ARG VCS_REF=unknown
ARG BUILD_DATE=unknown

LABEL org.opencontainers.image.title="silverassist/next-base" \
      org.opencontainers.image.description="nginx + Node 24 + supervisor runtime for SilverAssist Next.js sites" \
      org.opencontainers.image.vendor="SilverAssist" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.source="https://github.com/SilverAssist/docker-base" \
      org.opencontainers.image.documentation="https://github.com/SilverAssist/docker-base/blob/main/images/next-base/README.md" \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.created="${BUILD_DATE}"

# findutils: the cache-rotation scripts rely on GNU find, not busybox find.
# vips: sharp's runtime, needed by next/image on musl.
RUN apk add --no-cache \
        nginx supervisor bash findutils libc6-compat vips \
    && mkdir -p /run/nginx /var/log/supervisor /var/www/html \
    && ln -sf /dev/stdout /var/log/nginx/access.log \
    && ln -sf /dev/stderr /var/log/nginx/error.log

# nginx installed from apk ships no default server block, so there is nothing
# to disable here — the project drops its own into /etc/nginx/conf.d/.

ENV NODE_ENV=production \
    NEXT_TELEMETRY_DISABLED=1

WORKDIR /app
EXPOSE 80 3000
