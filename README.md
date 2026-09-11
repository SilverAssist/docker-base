# SilverAssist Docker base images

Base images for the SilverAssist WordPress and Next.js sites, following the
same `silverassist/*` namespace already used on Packagist.

| Image | Tag | Contents |
|---|---|---|
| `wp-base` | `ghcr.io/silverassist/wp-base:1` | nginx 1.31, PHP 8.3 + 32 extensions, php-fpm, supervisor, Composer, WP-CLI |
| `next-base` | `ghcr.io/silverassist/next-base:1` | nginx, Node 24, supervisor — the runtime stage |
| `next-base` (builder) | `ghcr.io/silverassist/next-base:1-builder` | Node 24 + native-module toolchain — the build stage |

Published to **GHCR** (canonical, public) and, once AWS is wired up, mirrored
to **Amazon ECR** in the build region.

**The ECR mirror is optional.** Releases publish to GHCR alone until
`AWS_ECR_ROLE_ARN` is set, and a public GHCR image needs no authentication to
pull and has no rate limit — so CodeBuild can consume it today.

**A GHCR package does not inherit the repository's visibility.** Packages are
created private even in a public repository, and an anonymous pull returns
`401 Unauthorized` until an org owner changes it. This is a one-time step per
package; see "First-time GHCR setup" below.

Prefer ECR once it exists: it is in-region, so pulls are faster and cost no
egress, and it keeps a third-party registry out of every production build's
critical path. See [docs/AWS-ACCESS-REQUEST.md](docs/AWS-ACCESS-REQUEST.md) for
what IT needs to provision.

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
COPY package.json package-lock.json .npmrc ./
RUN --mount=type=secret,id=npm_github_token \
    NPM_GITHUB_TOKEN="$(cat /run/secrets/npm_github_token)" npm ci --omit=dev
COPY . .
RUN npm run build && rm -rf .next/cache

FROM <account>.dkr.ecr.us-east-1.amazonaws.com/next-base:1.0.0
ARG GIT_COMMIT=unknown
ENV GIT_COMMIT=$GIT_COMMIT
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

### Installing `@silverassist/*` packages (GitHub Packages, private)

Any site that depends on `@silverassist/nextjs-core` or another private
`@silverassist/*` package needs a `.npmrc` scoping that namespace to GitHub
Packages:

```ini
# .npmrc — commit this; it reads the token from the environment
@silverassist:registry=https://npm.pkg.github.com
//npm.pkg.github.com/:_authToken=${NPM_GITHUB_TOKEN}
```

A bare `npm ci` in the builder stage above **will 401** without it — the build
context has no `.npmrc` and no token by default, unlike a developer's local
shell (which usually has `NPM_GITHUB_TOKEN` exported already, masking the gap
until the first CI/CodeBuild build). Do not pass the token as an `ARG`/`ENV`:
that bakes it into the image's layer history permanently, readable by anyone
with pull access to the image. The `RUN --mount=type=secret` form in the
example above reads it only for that one command and it never touches a
layer.

Wire it into the build invocation with `--secret id=npm_github_token,env=VAR`,
naming whichever environment variable the pipeline already has the token in:

```bash
# CodeBuild / local — the token must already be in the environment as $NPM_GITHUB_TOKEN
docker build --secret id=npm_github_token,env=NPM_GITHUB_TOKEN -t "$IMAGE" .
```

Confirmed against `senioradvice-nextjs` and `nextjs-boilerplate` (2026-09-11):
both project Dockerfiles previously copied only `package.json`/
`package-lock.json` and ran a bare `npm ci`, exactly as this README's own
example did — every site that followed it verbatim would 401 the moment it
tried to install `@silverassist/nextjs-core`. Local builds happened to work
only because the developer's shell already had `NPM_GITHUB_TOKEN` exported;
neither site's actual CI pipeline has the `--secret` wiring yet — see
`nextjs-boilerplate/docs/NEXTJS_CORE_PACKAGE_PLAN.md`'s "Docker/CodeBuild
registry auth" for that remaining half.

### Exposing the deployed commit

`next-base` declares `ARG GIT_COMMIT=unknown` in its runtime stage so a plain
`FROM next-base:1.0.0` doesn't leave `GIT_COMMIT` unset, but that default only
covers next-base's own build — `ARG` values don't propagate through a
downstream `FROM`, so it never carries a site's actual commit. Every
consuming Dockerfile re-declares the two lines above, and its CodeBuild
buildspec passes the real value:

```bash
docker build --build-arg GIT_COMMIT=$CODEBUILD_RESOLVED_SOURCE_VERSION ...
```

Read it back over HTTP with the `/api/deploy-info` route shipped in
`@silverassist/nextjs-core/environment` — this is how a developer without AWS
access checks which commit is live in an environment. Wiring it in a site
only takes two lines (`src/app/api/deploy-info/route.ts`):

```typescript
export { GET } from "@silverassist/nextjs-core/environment";
export const dynamic = "force-dynamic";
```

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

Nothing is required to publish to GHCR — `GITHUB_TOKEN` covers it.

### First-time GHCR setup

After the first release of each image, an org owner must make its package
public — once per package, not per release:

1. <https://github.com/orgs/SilverAssist/packages> → select the package
2. **Package settings** → **Danger Zone** → **Change visibility** → **Public**

While it is still private, consumers must authenticate:

```bash
echo "$GITHUB_TOKEN" | docker login ghcr.io -u <user> --password-stdin
```

Confirm it worked from an unauthenticated client:

```bash
docker buildx imagetools inspect ghcr.io/silverassist/wp-base:1.0.0
```

Also link each package to this repository (Package settings → **Connect
repository**) so it inherits the README and appears on the repo page.

The ECR mirror needs two Actions **variables** (not secrets):

| Variable | Purpose |
|---|---|
| `AWS_ECR_ROLE_ARN` | IAM role assumed via OIDC to push to ECR |
| `AWS_REGION` | ECR region; match the CodeBuild region |

Leave them unset and every ECR step is skipped. The full provisioning request
for IT — roles, trust policies, permissions — is in
[docs/AWS-ACCESS-REQUEST.md](docs/AWS-ACCESS-REQUEST.md).

## Local development

```bash
docker build -t wp-base:test images/wp-base
./tests/smoke-wp.sh wp-base:test
```
