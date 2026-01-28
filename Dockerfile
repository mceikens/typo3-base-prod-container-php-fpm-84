#######################
# Build Stage
#######################
FROM alpine:3.20 AS build

# Aktuellste PHP Version (Januar 2025)
ENV PHP_VERSION=8.4.2

# Build-Abhängigkeiten installieren
RUN apk add --no-cache \
    autoconf \
    bison \
    build-base \
    curl \
    curl-dev \
    tar \
    xz \
    icu-dev \
    libxml2-dev \
    libzip-dev \
    oniguruma-dev \
    libpng-dev \
    libjpeg-turbo-dev \
    freetype-dev \
    gmp-dev \
    bzip2-dev \
    gettext-dev \
    libxslt-dev \
    openssl-dev \
    sqlite-dev \
    libffi-dev \
    zlib-dev \
    readline-dev \
    imap-dev \
    krb5-dev \
    imagemagick-dev \
    libwebp-dev \
    libheif-dev \
    librsvg-dev \
    libc-dev \
    argon2-dev \
    rabbitmq-c-dev \
    linux-headers \
    re2c \
    pkgconf \
    git \
    && update-ca-certificates

# PHP source download & extraction
RUN curl -fsSL https://www.php.net/distributions/php-${PHP_VERSION}.tar.xz -o php.tar.xz \
    && mkdir -p /usr/src/php \
    && tar -xf php.tar.xz -C /usr/src/php --strip-components=1 \
    && rm php.tar.xz

# Build PHP mit optimierten Flags für TYPO3
RUN cd /usr/src/php \
    && ./configure \
        --prefix=/usr/local \
        --enable-fpm \
        --enable-bcmath \
        --enable-calendar \
        --enable-exif \
        --enable-ftp \
        --enable-gd \
        --enable-intl \
        --enable-mbstring \
        --enable-opcache \
        --enable-pcntl \
        --enable-shmop \
        --enable-soap \
        --enable-sockets \
        --enable-zts \
        --enable-fileinfo \
        --enable-dom \
        --enable-simplexml \
        --enable-xmlreader \
        --enable-xmlwriter \
        --enable-session \
        --enable-filter \
        --enable-ctype \
        --enable-hash \
        --enable-posix \
        --enable-sysvsem \
        --enable-sysvshm \
        --enable-sysvmsg \
        --with-xsl \
        --with-zip \
        --with-zlib \
        --with-openssl \
        --with-readline \
        --with-imap \
        --with-imap-ssl \
        --with-pdo-mysql \
        --with-password-argon2 \
        --with-gettext \
        --with-gmp \
        --with-jpeg \
        --with-freetype \
        --with-mysqli \
        --with-bz2 \
        --with-curl \
        --with-gd \
        --with-webp \
        --with-fpm-user=www-data \
        --with-fpm-group=www-data \
        --with-config-file-path=/usr/local/etc/php \
        --with-config-file-scan-dir=/usr/local/etc/php/conf.d \
        --with-pear \
        --disable-cgi \
    && make -j$(nproc) \
    && make install \
    && mkdir -p /usr/local/etc/php/conf.d \
    && cp php.ini-production /usr/local/etc/php/php.ini

# ImageMagick aus Git kompilieren (aktuellste kompatible Version für PHP 8.4)
RUN cd /tmp \
    && git clone https://github.com/Imagick/imagick.git \
    && cd imagick \
    && phpize \
    && ./configure \
    && make -j$(nproc) \
    && make install \
    && cd / \
    && rm -rf /tmp/imagick

# PECL Extensions installieren (einzeln für bessere Fehlerbehandlung)
RUN pecl channel-update pecl.php.net \
    && pecl install redis-6.1.0 \
    && pecl install apcu-5.1.24 \
    && pecl install amqp-2.1.2 \
    && rm -rf /tmp/pear

# Extensions aktivieren
RUN for ext in imagick redis amqp apcu; do \
        echo "extension=${ext}.so" > /usr/local/etc/php/conf.d/20-${ext}.ini; \
    done

# APCu CLI disable (nur für FPM)
RUN echo "apc.enable_cli=0" >> /usr/local/etc/php/conf.d/20-apcu.ini

# Default PHP-FPM configs (werden überschriebbar sein)
RUN cp /usr/local/etc/php-fpm.conf.default /usr/local/etc/php-fpm.conf \
    && cp /usr/local/etc/php-fpm.d/www.conf.default /usr/local/etc/php-fpm.d/www.conf


#######################
# Runtime Stage
#######################
FROM alpine:3.20

LABEL maintainer="your-email@example.com" \
      description="PHP-FPM 8.4 Base Image for TYPO3 with RabbitMQ, Redis & ImageMagick" \
      php.version="8.4.2"

# Nur Runtime-Abhängigkeiten
RUN apk add --no-cache \
    curl \
    icu-libs \
    libxml2 \
    libzip \
    oniguruma \
    libpng \
    libjpeg-turbo \
    freetype \
    gmp \
    bzip2 \
    gettext \
    libxslt \
    openssl \
    sqlite-libs \
    libffi \
    zlib \
    readline \
    c-client \
    krb5-libs \
    tini \
    imagemagick \
    imagemagick-libs \
    ghostscript \
    libwebp \
    libde265 \
    dav1d \
    librsvg \
    libheif \
    argon2-libs \
    rabbitmq-c \
    redis \
    graphicsmagick \
    git \
    patch \
    bash \
    su-exec \
    shadow \
    && rm -rf /var/cache/apk/*

# PHP & Extensions aus Build-Stage kopieren
COPY --from=build /usr/local /usr/local

# Standard www-data User erstellen (wird im Entrypoint angepasst)
RUN set -x \
    && addgroup -g 82 -S www-data 2>/dev/null || true \
    && adduser -u 82 -D -S -G www-data www-data 2>/dev/null || true

# Verzeichnisse für PHP-FPM und TYPO3
RUN mkdir -p \
    /var/run/php-fpm \
    /usr/share/nginx/html \
    /var/www/html \
    && chown -R www-data:www-data \
        /var/run/php-fpm \
        /usr/share/nginx/html

# TYPO3-optimierte php.ini als Basis
COPY ./config/php.ini /usr/local/etc/php/php.ini
COPY ./config/php-fpm.conf /usr/local/etc/php-fpm.conf
COPY ./config/www.conf /usr/local/etc/php-fpm.d/www.conf

# Environment Variables für Customization
ENV PHP_MEMORY_LIMIT=512M \
    PHP_MAX_EXECUTION_TIME=240 \
    PHP_MAX_INPUT_VARS=1500 \
    PHP_UPLOAD_MAX_FILESIZE=64M \
    PHP_POST_MAX_SIZE=64M \
    PHP_OPCACHE_ENABLE=1 \
    PHP_OPCACHE_MEMORY=256 \
    PHP_OPCACHE_MAX_FILES=20000 \
    PHP_FPM_PM=dynamic \
    PHP_FPM_PM_MAX_CHILDREN=50 \
    PHP_FPM_PM_START_SERVERS=5 \
    PHP_FPM_PM_MIN_SPARE_SERVERS=5 \
    PHP_FPM_PM_MAX_SPARE_SERVERS=35 \
    PHP_FPM_PM_MAX_REQUESTS=500 \
    PUID=82 \
    PGID=82 \
    TZ=Europe/Berlin

# Healthcheck für PHP-FPM
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD pgrep php-fpm > /dev/null || exit 1

# Entrypoint der UID/GID anpasst
COPY ./entrypoint/docker-entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /var/www/html

EXPOSE 9000

VOLUME ["/var/www/html"]

ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["php-fpm", "-F", "-R"]