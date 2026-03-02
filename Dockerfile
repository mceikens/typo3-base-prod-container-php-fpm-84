#######################
# Stage 1: Build
#######################
FROM alpine:3.21 AS build

ENV PHP_VERSION=8.4.18
# Hier kannst du die exakte ImageMagick Version festlegen (z.B. 7.1.2-25)
ENV IMAGEMAGICK_VERSION=7.1.2-15
ENV LIBTIFF_VERSION=4.7.1

RUN apk update && apk upgrade && \
    apk add --no-cache \
    autoconf bison build-base curl curl-dev tar xz icu-dev libxml2-dev libzip-dev \
    oniguruma-dev libpng-dev libjpeg-turbo-dev freetype-dev gmp-dev bzip2-dev \
    gettext-dev libxslt-dev openssl-dev sqlite-dev libffi-dev zlib-dev readline-dev \
    imap-dev krb5-dev libwebp-dev libheif-dev librsvg-dev libc-dev \
    argon2-dev rabbitmq-c-dev linux-headers re2c pkgconf git libsodium-dev automake autoconf libtool m4 wget

# 1. Libtiff aus Source bauen
RUN curl -fsSL https://gitlab.com/libtiff/libtiff/-/archive/v${LIBTIFF_VERSION}/libtiff-v${LIBTIFF_VERSION}.tar.gz -o /tmp/libtiff.tar.gz && \
    mkdir -p /tmp/libtiff && \
    tar -xzf /tmp/libtiff.tar.gz -C /tmp/libtiff --strip-components=1 && \
    cd /tmp/libtiff && \
    mkdir -p config && \
    autoreconf -fiv && \
    ./configure --prefix=/usr/local --disable-static && \
    make -j$(nproc) && \
    make install && \
    rm -rf /tmp/libtiff /tmp/libtiff.tar.gz

# 2. ImageMagick aus Source bauen
RUN curl -fsSL https://github.com/ImageMagick/ImageMagick/archive/refs/tags/${IMAGEMAGICK_VERSION}.tar.gz -o /tmp/ImageMagick.tar.gz && \
    mkdir -p /tmp/ImageMagick && \
    tar -xzf /tmp/ImageMagick.tar.gz -C /tmp/ImageMagick --strip-components=1 && \
    cd /tmp/ImageMagick && \
    ./configure \
        --prefix=/usr/local \
        --with-tiff=yes \
        --with-magick-plus-plus=no \
        --with-perl=no \
        --with-webp=yes \
        --with-heic=yes \
        --with-gvc=no \
        --with-fontconfig=yes \
        --with-freetype=yes \
        --disable-docs && \
    make -j$(nproc) && \
    make install

# 3. PHP Source laden und konfigurieren
RUN curl -fsSL https://www.php.net/distributions/php-${PHP_VERSION}.tar.xz -o php.tar.xz \
    && mkdir -p /usr/src/php \
    && tar -xf php.tar.xz -C /usr/src/php --strip-components=1

RUN cd /usr/src/php && ./configure \
    --prefix=/usr/local \
    --with-config-file-path=/usr/local/etc/php \
    --with-config-file-scan-dir=/usr/local/etc/php/conf.d \
    --enable-fpm \
    --enable-bcmath \
    --enable-intl \
    --enable-mbstring \
    --enable-opcache \
    --enable-soap \
    --enable-sockets \
    --enable-zts \
    --with-xsl \
    --with-zip \
    --with-openssl \
    --with-imap \
    --with-imap-ssl \
    --with-pdo-mysql \
    --with-mysqli \
    --with-jpeg \
    --with-webp \
    --with-freetype \
    --with-curl \
    --with-zlib \
    --with-pear \
    --with-fpm-user=www-data \
    --with-fpm-group=www-data \
    --with-sodium \
    --enable-gd \
    && make -j$(nproc) \
    && make install

# 4. PECL Extensions
RUN /usr/local/bin/pear config-set php_ini /usr/local/etc/php/php.ini \
    && /usr/local/bin/pecl channel-update pecl.php.net \
    && /usr/local/bin/pecl install redis-6.1.0 apcu-5.1.24 amqp-2.1.2 imagick-3.8.1

#######################
# Stage 2: Runtime
#######################
FROM alpine:3.21

USER root

ENV GOLANG_VERSION=1.26.0

RUN echo "@edge https://dl-cdn.alpinelinux.org/alpine/edge/main" >> /etc/apk/repositories && \
    echo "@edge https://dl-cdn.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories

# Runtime-Abhängigkeiten (OHNE das Paket 'imagemagick', da wir es kopieren)
RUN apk update && apk upgrade --no-cache

RUN apk update && apk upgrade --no-cache && \
    apk add --no-cache \
    curl icu-libs libxml2 libzip oniguruma libpng libjpeg-turbo freetype gmp \
    bzip2 gettext libxslt openssl sqlite-libs libffi zlib readline c-client \
    krb5-libs tini ghostscript \
    libwebp libwebp-dev lcms2 libgomp \
    libheif librsvg argon2-libs \
    rabbitmq-c bash shadow ca-certificates libsodium \
    hiredis lz4-libs zstd-libs \
    openjpeg@edge pixman@edge glib@edge avahi-libs@edge
# WICHTIG: Alle kompilierten Binaries und Libraries (PHP + ImageMagick) kopieren
COPY --from=build /usr/local /usr/local

ENV LD_LIBRARY_PATH=/usr/local/lib:/usr/lib:/lib
RUN ln -s /usr/lib/libwebp.so.7 /usr/lib/libwebp.so.6 || true

# Shared Libraries Cache aktualisieren, damit das System das neue ImageMagick findet
RUN ldconfig /usr/local/lib || echo "/usr/local/lib" > /etc/ld.so.conf.d/local.conf && ldconfig /usr/local/lib || true

# User/Group erstellen
RUN set -x \
    && addgroup -g 1000 -S www-data 2>/dev/null || true \
    && adduser -u 1000 -D -S -G www-data www-data 2>/dev/null || true

# Verzeichnisse & Configs
RUN mkdir -p /usr/local/etc/php/conf.d /usr/local/etc/php-fpm.d /var/run/php-fpm /var/log/php-fpm /var/www/html \
    && echo "extension=imagick.so" > /usr/local/etc/php/conf.d/20-imagick.ini \
    && echo "extension=redis.so" > /usr/local/etc/php/conf.d/20-redis.ini \
    && echo "extension=amqp.so" > /usr/local/etc/php/conf.d/20-amqp.ini \
    && echo "extension=apcu.so" > /usr/local/etc/php/conf.d/20-apcu.ini

COPY --chown=www-data:www-data ./config/php.ini /usr/local/etc/php/php.ini
COPY --chown=www-data:www-data ./config/php-fpm.conf /usr/local/etc/php-fpm.conf
COPY --chown=www-data:www-data ./config/www.conf /usr/local/etc/php-fpm.d/www.conf

# fixuid frisch kompilieren (Go CVE fix)
RUN apk add --no-cache --virtual .build-deps git curl && \
    curl -fsSL https://golang.org/dl/go${GOLANG_VERSION}.linux-amd64.tar.gz -o go.tar.gz && \
    tar -C /usr/local -xzf go.tar.gz && \
    export PATH=$PATH:/usr/local/go/bin && \
    go install github.com/boxboat/fixuid@latest && \
    cp $(go env GOPATH)/bin/fixuid /usr/local/bin/fixuid && \
    apk del .build-deps && \
    rm -rf /usr/local/go go.tar.gz /root/go

# Berechtigungen
RUN chown -R www-data:www-data /var/run/php-fpm /var/log/php-fpm /usr/local/etc/php /var/www/html

COPY --chown=www-data:www-data ./entrypoint/docker-entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

RUN mkdir -p /etc/fixuid && \
    printf "user: www-data\ngroup: www-data\n" > /etc/fixuid/config.yml && \
    chown root:root /etc/fixuid/config.yml && \
    chmod 644 /etc/fixuid/config.yml

RUN chown root:root /usr/local/bin/fixuid && \
    chmod 4755 /usr/local/bin/fixuid


WORKDIR /var/www/html
USER root
EXPOSE 9000

ENTRYPOINT ["fixuid", "-q", "/sbin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["php-fpm", "-F", "-R"]