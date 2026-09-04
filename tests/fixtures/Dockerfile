ARG BASE_IMAGE
FROM ${BASE_IMAGE}
COPY site.conf /etc/nginx/conf.d/site.conf
COPY 99-project.ini /etc/php83/conf.d/99-project.ini
COPY index.php /var/www/html/index.php
RUN chown -R nginx:nginx /var/www/html
