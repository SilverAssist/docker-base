# SilverAssist Docker base images

Base images for the SilverAssist WordPress and Next.js sites, following the
same `silverassist/*` namespace already used on Packagist.

| Image | Tag | Contents |
|---|---|---|
| `wp-base` | `ghcr.io/silverassist/wp-base:1` | nginx 1.31, PHP 8.3 + 32 extensions, php-fpm, supervisor, Composer, WP-CLI |
| `next-base` | `ghcr.io/silverassist/next-base:1` | nginx, Node 24, supervisor — the runtime stage |
| `next-base` (builder) | `ghcr.io/silverassist/next-base:1-builder` | Node 24 + native-module toolchain — the build stage |

Published to **GHCR** (canonical, public) and mirrored to **Amazon ECR** in the
build region. Consume from ECR: it is in-region, has no pull rate limit, and
keeps a third-party registry out of every production build's critical path.

## Why

The 12 WordPress Dockerfiles were near-identical across ~90 lines: the same 41
apk packages in 11 of them, a byte-identical `php-fpm.conf` in all 12, and
`nginx.conf` and `supervisord.conf` byte-identical in 11 of 12 each. `php.ini`
and `www.conf` differ only in three timeout values, across three groupings.
Every fix had to be made twelve times.

The single-repo deviations are as informative as the duplication:
`carechanges-wp-website` is the one `nginx.conf` missing the CloudFront
`set_real_ip_from` block the other 11 carry, so that site does not resolve real
client IPs. Nobody noticed, because there was no shared file for it to drift
from.

More importantly, they installed Composer and WP-CLI **unpinned**:

```dockerfile
RUN curl -sS https://getcomposer.org/installer | php -- ...
```

In September 2026 that line pulled Composer 2.10.3, whose release notes say:

> Disabled automatic fallback to source checkout if dist/zip install fails

An intermittent `504` from `api.github.com` — previously absorbed by that
fallback — began failing production builds with `exit code: 100`. No commit
caused it. A third party's release changed the behaviour of a build nobody
had touched.

Every external artifact here is pinned by digest or verified by checksum, so
that cannot happen again without a commit in this repository.

## Using wp-base

```dockerfile
FROM <account>.dkr.ecr.us-east-1.amazonaws.com/wp-base:1.0.0@sha256:...

ARG WP_VERSION=6.9.1
RUN curl -o /tmp/wp.zip -fSL "https://downloads.wordpress.org/release/wordpress-${WP_VERSION}-no-content.zip" \
    && unzip -q /tmp/wp.zip -d /tmp \
    && cp -r /tmp/wordpress/* /var/www/html/ \
    && rm -rf /tmp/wordpress /tmp/wp.zip

COPY docker/conf/mysite.conf /etc/nginx/conf.d/mysite.conf

COPY composer.json composer.lock ./
RUN composer-install --no-dev --optimize-autoloader

COPY wp-content/ /var/www/html/wp-content/
COPY wp-config.php robots.txt /var/www/html/
RUN chown -R nginx:nginx /var/www/html \
    && ln -sf /dev/stderr /var/www/html/wp-content/debug.log
```

That is the whole project Dockerfile — roughly 20 lines instead of 90.

### Overriding PHP settings

Do not copy the full `php.ini`. Drop in only what differs:

```dockerfile
# /etc/php83/conf.d/99-mysite.ini
COPY docker/conf/99-mysite.ini /etc/php83/conf.d/99-mysite.ini
```

```ini
max_execution_time = 900
max_input_time = 60
```

php-fpm pool settings work the same way — `php-fpm.conf` globs
`/etc/php83/php-fpm.d/*.conf`, so a project drops a `99-mysite.conf` with just
its `request_terminate_timeout`.

### `composer-install`

Use it instead of `composer install`. It forwards every argument and retries
the whole install with linear backoff, which is what makes a transient
registry `504` a slow build rather than a failed one.

## Using next-base

```dockerfile
FROM <account>.dkr.ecr.us-east-1.amazonaws.com/next-base:1.0.0-builder AS builder
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev
COPY . .
RUN npm run build && rm -rf .next/cache

FROM <account>.dkr.ecr.us-east-1.amazonaws.com/next-base:1.0.0
COPY --from=builder /app/.next ./.next
COPY --from=builder /app/node_modules ./node_modules
COPY docker/conf/mysite.conf /etc/nginx/conf.d/mysite.conf
ENTRYPOINT ["/app/entrypoint.sh"]
```

The runtime target is Node with nginx installed on top, so the project no
longer copies `/usr/lib`, `/usr/local/bin` and `/usr/local/include` out of the
builder into an nginx image. That copy moved an unversioned set of shared
objects between two independently-updated bases; the node runtime here is the
one that was actually installed.

## Releasing

Tag and push:

```bash
git tag wp-base/v1.0.0 && git push origin wp-base/v1.0.0
git tag next-base/v1.0.0 && git push origin next-base/v1.0.0
```

Each release publishes `1.0.0`, `1.0`, `1` and `latest` to both registries,
signed with cosign. See [docs/VERSIONING.md](docs/VERSIONING.md).

To rebuild an unchanged version against a fresh Alpine — the usual response to
a CVE — run the workflow manually with the same version number.

## Repository setup

Required GitHub Actions variables:

| Variable | Purpose |
|---|---|
| `AWS_ECR_ROLE_ARN` | IAM role assumed via OIDC to push to ECR |
| `AWS_REGION` | ECR region; match the CodeBuild region |

The ECR repositories `wp-base` and `next-base` must
exist, and the CodeBuild service role needs `ecr:GetDownloadUrlForLayer`,
`ecr:BatchGetImage` and `ecr:GetAuthorizationToken` on them.

## Local development

```bash
docker build -t wp-base:test images/wp-base
./tests/smoke-wp.sh wp-base:test
```
