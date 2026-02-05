#######################
# Stage 1: Build
#######################
FROM alpine:3.20 AS build

ENV PHP_VERSION=8.4.2

RUN apk add --no-cache \
    autoconf bison build-base curl curl-dev tar xz icu-dev libxml2-dev libzip-dev \
    oniguruma-dev libpng-dev libjpeg-turbo-dev freetype-dev gmp-dev bzip2-dev \
    gettext-dev libxslt-dev openssl-dev sqlite-dev libffi-dev zlib-dev readline-dev \
    imap-dev krb5-dev imagemagick-dev libwebp-dev libheif-dev librsvg-dev libc-dev \
    argon2-dev rabbitmq-c-dev linux-headers re2c pkgconf git libsodium-dev

RUN curl -fsSL https://www.php.net/distributions/php-${PHP_VERSION}.tar.xz -o php.tar.xz \
    && mkdir -p /usr/src/php \
    && tar -xf php.tar.xz -C /usr/src/php --strip-components=1

RUN cd /usr/src/php && ./configure \
    --prefix=/usr/local --enable-fpm --enable-bcmath --enable-intl --enable-mbstring \
    --enable-opcache --enable-soap --enable-sockets --enable-zts --with-xsl --with-zip \
    --with-openssl --with-imap --with-imap-ssl --with-pdo-mysql --with-mysqli \
    --with-jpeg --with-webp --with-freetype --with-curl --with-zlib --with-pear \
    --with-fpm-user=www-data --with-fpm-group=www-data --with-sodium --enable-gd \
    && make -j$(nproc) && make install

RUN git clone https://github.com/Imagick/imagick.git /tmp/imagick \
    && cd /tmp/imagick && phpize && ./configure && make -j$(nproc) && make install

RUN /usr/local/bin/pear config-set php_ini /usr/local/etc/php/php.ini \
    && /usr/local/bin/pecl channel-update pecl.php.net \
    && /usr/local/bin/pecl install redis-6.1.0 apcu-5.1.24 amqp-2.1.2


#######################
# Stage 2: Runtime
#######################
FROM alpine:3.20

RUN apk add --no-cache \
    curl icu-libs libxml2 libzip oniguruma libpng libjpeg-turbo freetype gmp \
    bzip2 gettext libxslt openssl sqlite-libs libffi zlib readline c-client \
    krb5-libs tini imagemagick ghostscript libwebp libheif librsvg argon2-libs \
    rabbitmq-c bash shadow ca-certificates libsodium

COPY --from=build /usr/local /usr/local

# Explizit die Extension-Dateien kopieren (falls sie woanders liegen)
COPY --from=build /usr/local/lib/php/extensions /usr/local/lib/php/extensions

RUN set -x \
    && addgroup -g 1000 -S www-data 2>/dev/null || true \
    && adduser -u 1000 -D -S -G www-data www-data 2>/dev/null || true

RUN mkdir -p /usr/local/etc/php/conf.d \
    && mkdir -p /usr/local/etc/php-fpm.d \
    && mkdir -p /var/run/php-fpm \
    && mkdir -p /var/log/php-fpm \
    && mkdir -p /var/www/html

COPY --chown=www-data:www-data ./config/php.ini /usr/local/etc/php/php.ini
COPY --chown=www-data:www-data ./config/php-fpm.conf /usr/local/etc/php-fpm.conf
COPY --chown=www-data:www-data ./config/www.conf /usr/local/etc/php-fpm.d/www.conf

RUN echo "extension=imagick.so" > /usr/local/etc/php/conf.d/20-imagick.ini \
    && echo "extension=redis.so" > /usr/local/etc/php/conf.d/20-redis.ini \
    && echo "extension=amqp.so" > /usr/local/etc/php/conf.d/20-amqp.ini \
    && echo "extension=apcu.so" > /usr/local/etc/php/conf.d/20-apcu.ini

RUN chown -R www-data:www-data /var/run/php-fpm /var/log/php-fpm /usr/local/etc/php /var/www/html

RUN curl -SsL https://github.com/boxboat/fixuid/releases/download/v0.6.0/fixuid-0.6.0-linux-amd64.tar.gz | tar -C /usr/local/bin -xzf - \
    && chown root:root /usr/local/bin/fixuid \
    && chmod 4755 /usr/local/bin/fixuid \
    && mkdir -p /etc/fixuid \
    && echo "user: www-data" > /etc/fixuid/config.yml \
    && echo "group: www-data" >> /etc/fixuid/config.yml

COPY --chown=www-data:www-data ./entrypoint/docker-entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /var/www/html

USER www-data:www-data

EXPOSE 9000

ENTRYPOINT ["fixuid", "-q", "/sbin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["php-fpm", "-F", "-R"]