# Migration plan

26 Dockerfiles exist across the workspace: 14 WordPress and 12 Next.js. Of
those, 12 WordPress and 12 Next.js migrate in the waves below; two WordPress
repositories are separate cases, covered at the end. Migrate in waves, and let
each wave sit in production before starting the next.

## Prerequisites

1. Create ECR repositories `wp-base` and `next-base`.
2. Create the GitHub OIDC role, set `AWS_ECR_ROLE_ARN` and `AWS_REGION`.
3. Grant each CodeBuild service role pull access to those ECR repositories.
4. Cut `wp-base/v1.0.0` and `next-base/v1.0.0`.

## Wave 1 — one WordPress site

Migrate `osa-wp-new-website` alone. It is the site whose build surfaced the
Composer failure, so it is the one whose fix is easiest to confirm.

Per repo:

1. Replace the Dockerfile with the `FROM wp-base` form in the README.
2. Delete `docker/conf/nginx.conf`, `php-fpm.conf`, `supervisord.conf` — now
   in the base and byte-identical to what the base ships.
3. Reduce `docker/conf/php.ini` to a `99-<site>.ini` drop-in and
   `docker/conf/www.conf` to a `99-<site>.conf` drop-in, holding only the values
   that differ from the base. There are exactly three groupings across the 12:

   | `exec` / `input` / `terminate` | Sites | Versus base |
   |---|---|---|
   | 600 / 120 / 300 | osa, aa-wp, memorycare, senioradvicecom-wpblog | matches the base — no drop-in needed |
   | 900 / 60 / 900 | familyassets, assistedlivingorg, homecareorg, medicalalertorg, seniorhousingnet, careerscaring, payingforseniorcare | drop-in required |
   | 300 / 60 / 300 | carechanges | drop-in required |

   The base ships the first grouping's values, so four of the twelve sites need
   no PHP drop-in at all.

4. Keep `docker/conf/<site>.conf` — the server block is genuinely per-site.
5. Swap `composer install` for `composer-install`.
6. Build locally, run `tests/smoke-wp.sh` against the project image, deploy to
   staging, compare against production before promoting.

## Wave 2 — remaining 11 WordPress sites

`aa-wp`, `assistedlivingorg-wp`, `carechanges-wp-website`,
`careerscaringcom-wp`, `familyassets-wp-website`, `homecareorg-wp`,
`medicalalertorg-wp`, `memorycare-wp-website`, `payingforseniorcarecom-wp`,
`seniorhousingnetcom-wp`, `senioradvicecom-wpblog`.

Four need something extra in their own layer:

- `careerscaringcom-wp` adds `libwebp-tools`, and adds a `[program:wp-cron]` to
  supervisor. Ship that as `/etc/supervisor/conf.d/wp-cron.conf` — the base's
  `supervisord.conf` globs that directory precisely so this does not require
  replacing the file.
- `carechanges-wp-website` is the site whose `nginx.conf` lacks the CloudFront
  `set_real_ip_from` block. Adopting the base's `nginx.conf` **changes its
  behaviour**: client IPs start resolving correctly. That is the intended fix,
  but verify anything reading `$remote_addr` — rate limiting, logging, security
  plugins — before promoting.
- `senioradvicecom-wpblog` lacks `php83-pecl-redis` and `php83-tokenizer`
  today. The base includes both; confirm nothing there depends on their
  absence.

## The two WordPress repositories outside the waves

- **`senioradvicecom-wp`** already uses a multi-stage `FROM composer:2.8` build
  and does not share the pattern the base image consolidates. Assess separately.
- **`elderlife-wp-website`** is a different shape: it installs PHP but no
  Composer and no WP-CLI, and its 54-line Dockerfile is still on an unpinned
  `FROM nginx:alpine`. That unpinned base is worth fixing regardless of this
  migration — it is the same class of exposure as the unpinned Composer
  installer. Decide whether it adopts `wp-base` (gaining Composer and WP-CLI it
  does not currently use) or simply gets its base pinned in place.

## Wave 3 — Next.js sites

Higher risk than the WordPress wave, because the runtime base changes shape:
the project stops copying `/usr/lib`, `/usr/local/lib`, `/usr/local/include`
and `/usr/local/bin` out of the builder into an nginx image.

Verify per site before promoting:

- `next/image` transforms (sharp against the base's `vips`)
- the cache-rotation scripts, which need GNU `findutils`, not busybox `find`
- `entrypoint.sh` and the Redis cache handler
- `.next/BUILD_ID` present in the final image

Sites needing extra packages in their own layer: `cc-nextjs` and `osa-nextjs`
(`vips-dev`), `homecare-nextjs` and `seniorhomes-nextjs` (`expat`,
`python3`, `py3-pip`), `aa-nextjs` (`python3`, `make`, `g++` at runtime —
confirm this is still needed).

`desarrollo-de-software` is on `node:20-alpine` and needs a Node 20 assessment
before it can move.

## Rollback

Each migration is one commit per repository. Reverting it restores the
standalone Dockerfile; nothing in the base image is required for a rolled-back
build to work.
