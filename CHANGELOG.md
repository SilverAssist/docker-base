# Changelog

All notable changes to these images are documented here. Each image versions
independently; entries are grouped by image.

## wp-base

### 1.0.0 — unreleased

Initial release. Consolidates the runtime that was duplicated across the 12
WordPress project Dockerfiles.

- nginx 1.31-alpine, pinned by digest
- PHP 8.3 with the 32-extension set common to all sites
- Composer 2.10.3 and WP-CLI 2.12.0, pinned by version and verified by sha256
- `composer-install`, which retries transient registry failures
- `git`, so Composer can clone a package when a dist archive is unavailable
- Shared `nginx.conf`, `php-fpm.conf` and `supervisord.conf`, byte-identical
  to what every project shipped
- `php.ini` and `www.conf` defaults, overridable via conf.d drop-ins
- `supervisord.conf` with an `[include]` of `/etc/supervisor/conf.d/*.conf`,
  so a site can add a wp-cron poller without replacing the file

## next-base

### 1.0.0 — unreleased

Initial release.

- Node 24.20.0 on Alpine 3.24, pinned by digest
- `builder` target with the native-module toolchain
- `runtime` target with nginx and supervisor on top of Node, replacing the
  copy of `/usr/lib` and `/usr/local/bin` from builder into an nginx image
