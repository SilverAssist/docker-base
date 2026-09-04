# wp-base

nginx + PHP 8.3 + php-fpm + supervisor + Composer + WP-CLI.

## Pinned contents

| Component | Version | Pinning |
|---|---|---|
| nginx | 1.31-alpine | base image digest |
| PHP | 8.3 | Alpine repository |
| Composer | 2.10.3 | version + sha256 |
| WP-CLI | 2.12.0 | version + sha256 |

## PHP extensions

bcmath, ctype, curl, dom, exif, fileinfo, ftp, gd, iconv, igbinary, imagick,
intl, json, mbstring, msgpack, mysqli, mysqlnd, opcache, openssl, pdo,
pdo_mysql, phar, redis, session, simplexml, sodium, tokenizer, xml, xmlreader,
xmlwriter, zip, zlib.

igbinary and msgpack arrive as dependencies of the redis extension and are what
make its serializers usable; they are listed because a project may rely on them.

## Paths

| Path | Purpose |
|---|---|
| `/var/www/html` | webroot, `WORKDIR` |
| `/etc/nginx/conf.d/` | drop the site's server block here |
| `/etc/php83/conf.d/99-*.ini` | PHP overrides |
| `/etc/php83/php-fpm.d/99-*.conf` | pool overrides |
| `/etc/supervisor/conf.d/*.conf` | extra supervisor programs (wp-cron, workers) |
| `/usr/local/bin/composer-install` | retrying `composer install` |

## Not included

WordPress core, the site server block, project dependencies, `wp-content`,
`wp-config.php`. All of these vary per project or per deploy.

WordPress core is deliberately excluded: `WP_VERSION` is a per-project build
arg and core ships security releases on its own cadence. Baking it in would
couple every core update to a base image release.

## Defaults worth knowing

`memory_limit=756M`, `max_execution_time=600`, `max_input_time=120`,
`upload_max_filesize=15M`, `post_max_size=15M`, `pm=dynamic` with
`pm.max_children=10`, `request_terminate_timeout=300`.

Override with a drop-in rather than replacing the file.

## Adding a supervisor program

```ini
; /etc/supervisor/conf.d/wp-cron.conf
[program:wp-cron]
command = /bin/sh -c "while true; do curl -s 'http://localhost/wp-cron.php?doing_wp_cron' > /dev/null 2>&1; sleep 300; done"
autostart = true
autorestart = true
stdout_logfile = /dev/stdout
stdout_logfile_maxbytes = 0
```
