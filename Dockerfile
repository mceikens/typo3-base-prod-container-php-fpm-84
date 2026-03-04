#######################
# Stage 1: Build
#######################
FROM alpine:3.21 AS build

ENV PHP_VERSION=8.4.18
ENV IMAGEMAGICK_VERSION=7.1.2-15
ENV LIBTIFF_VERSION=4.7.1
ENV OPENJPEG_VERSION=2.5.3
ENV PIXMAN_VERSION=0.44.2
ENV GHOSTSCRIPT_VERSION=10.05.1

RUN apk update && apk upgrade && \
    apk add --no-cache \
    autoconf bison build-base curl curl-dev tar xz icu-dev libxml2-dev libzip-dev \
    oniguruma-dev libpng-dev libjpeg-turbo-dev freetype-dev gmp-dev bzip2-dev \
    gettext-dev libxslt-dev openssl-dev sqlite-dev libffi-dev zlib-dev readline-dev \
    imap-dev krb5-dev libwebp-dev libheif-dev librsvg-dev libc-dev \
    argon2-dev rabbitmq-c-dev linux-headers re2c pkgconf git libsodium-dev \
    automake autoconf libtool m4 wget meson ninja cmake \
    fontconfig-dev lcms2-dev

RUN curl -fsSL https://gitlab.com/libtiff/libtiff/-/archive/v${LIBTIFF_VERSION}/libtiff-v${LIBTIFF_VERSION}.tar.gz -o /tmp/libtiff.tar.gz && \
    mkdir -p /tmp/libtiff && \
    tar -xzf /tmp/libtiff.tar.gz -C /tmp/libtiff --strip-components=1 && \
    cd /tmp/libtiff && \
    autoreconf -fiv && \
    ./configure --prefix=/usr/local --disable-static && \
    make -j$(nproc) && \
    make install && \
    rm -rf /tmp/libtiff /tmp/libtiff.tar.gz

RUN curl -fsSL https://github.com/uclouvain/openjpeg/archive/refs/tags/v${OPENJPEG_VERSION}.tar.gz -o /tmp/openjpeg.tar.gz && \
    mkdir -p /tmp/openjpeg/build && \
    tar -xzf /tmp/openjpeg.tar.gz -C /tmp/openjpeg --strip-components=1 && \
    cd /tmp/openjpeg/build && \
    cmake .. -DCMAKE_INSTALL_PREFIX=/usr/local -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=ON -DBUILD_STATIC_LIBS=OFF && \
    make -j$(nproc) && \
    make install && \
    rm -rf /tmp/openjpeg /tmp/openjpeg.tar.gz

RUN curl -fsSL https://cairographics.org/releases/pixman-${PIXMAN_VERSION}.tar.gz -o /tmp/pixman.tar.gz && \
    mkdir -p /tmp/pixman && \
    tar -xzf /tmp/pixman.tar.gz -C /tmp/pixman --strip-components=1 && \
    cd /tmp/pixman && \
    mkdir build && cd build && \
    meson setup .. --prefix=/usr/local --buildtype=release \
        -Ddefault_library=shared && \
    ninja -j$(nproc) && \
    ninja install && \
    rm -rf /tmp/pixman /tmp/pixman.tar.gz

RUN curl -fsSL https://github.com/ArtifexSoftware/ghostpdl-downloads/releases/download/gs10051/ghostscript-${GHOSTSCRIPT_VERSION}.tar.gz -o /tmp/gs.tar.gz && \
    mkdir -p /tmp/gs && \
    tar -xzf /tmp/gs.tar.gz -C /tmp/gs --strip-components=1 && \
    cd /tmp/gs && \
    ./configure \
        --prefix=/usr/local \
        --disable-compile-inits \
        --disable-hidden-visibility \
        --without-x \
        --disable-cups && \
    make -j$(nproc) && \
    make install && \
    rm -rf /tmp/gs /tmp/gs.tar.gz

RUN curl -fsSL https://github.com/ImageMagick/ImageMagick/archive/refs/tags/${IMAGEMAGICK_VERSION}.tar.gz -o /tmp/ImageMagick.tar.gz && \
    mkdir -p /tmp/ImageMagick && \
    tar -xzf /tmp/ImageMagick.tar.gz -C /tmp/ImageMagick --strip-components=1 && \
    cd /tmp/ImageMagick && \
    PKG_CONFIG_PATH=/usr/local/lib/pkgconfig \
    ./configure \
        --prefix=/usr/local \
        --with-tiff=yes \
        --with-openjp2=yes \
        --with-magick-plus-plus=no \
        --with-perl=no \
        --with-webp=yes \
        --with-heic=yes \
        --with-gvc=no \
        --with-fontconfig=yes \
        --with-freetype=yes \
        --with-gs-font-dir=/usr/local/share/ghostscript/fonts \
        --disable-docs && \
    make -j$(nproc) && \
    make install && \
    rm -rf /tmp/ImageMagick /tmp/ImageMagick.tar.gz

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

RUN /usr/local/bin/pear config-set php_ini /usr/local/etc/php/php.ini \
    && /usr/local/bin/pecl channel-update pecl.php.net \
    && /usr/local/bin/pecl install redis-6.1.0 apcu-5.1.24 amqp-2.1.2 imagick-3.8.1

RUN cp /usr/lib/libicu*.so.74* /usr/local/lib/ 2>/dev/null || true \
    && cp -r /usr/share/icu /tmp/icu-share

#######################
# Stage 2: Runtime
#######################
FROM alpine:edge

USER root

ENV GOLANG_VERSION=1.26.0

RUN echo "https://dl-cdn.alpinelinux.org/alpine/edge/main" > /etc/apk/repositories && \
    echo "https://dl-cdn.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories

RUN apk update && apk upgrade --no-cache

RUN apk add --no-cache \
    curl libxml2 libzip oniguruma libpng libjpeg-turbo freetype gmp \
    bzip2 gettext libxslt openssl sqlite-libs libffi zlib readline c-client \
    krb5-libs tini \
    libwebp libwebp-dev lcms2 libgomp \
    libheif librsvg argon2-libs \
    rabbitmq-c bash shadow ca-certificates libsodium \
    hiredis lz4-libs zstd-libs \
    fontconfig

COPY --from=build /usr/local /usr/local
COPY --from=build /tmp/icu-share /usr/share/icu

ENV LD_LIBRARY_PATH=/usr/local/lib:/usr/lib:/lib

RUN ln -s /usr/lib/libwebp.so.7 /usr/lib/libwebp.so.6 2>/dev/null || true

RUN ldconfig /usr/local/lib || \
    (echo "/usr/local/lib" > /etc/ld.so.conf.d/local.conf && ldconfig) || true

RUN apk del tiff pixman 2>/dev/null || true && \
    rm -f /usr/lib/libtiff*.so* \
          /usr/lib/libtiffxx*.so* \
          /usr/lib/libpixman-1*.so* \
          /usr/lib/libavahi*.so* \
          /usr/lib/libcups*.so* \
          /usr/bin/flock

RUN for pkg in tiff pixman openjpeg ghostscript avahi cups flock coreutils; do \
        sed -i "/^P:${pkg}/,/^$/d" /lib/apk/db/installed 2>/dev/null || true; \
    done

RUN set -x \
    && addgroup -g 1000 -S www-data 2>/dev/null || true \
    && adduser -u 1000 -D -S -G www-data www-data 2>/dev/null || true

RUN mkdir -p /usr/local/etc/php/conf.d /usr/local/etc/php-fpm.d /var/run/php-fpm /var/log/php-fpm /var/www/html \
    && echo "extension=imagick.so" > /usr/local/etc/php/conf.d/20-imagick.ini \
    && echo "extension=redis.so" > /usr/local/etc/php/conf.d/20-redis.ini \
    && echo "extension=amqp.so" > /usr/local/etc/php/conf.d/20-amqp.ini \
    && echo "extension=apcu.so" > /usr/local/etc/php/conf.d/20-apcu.ini

COPY --chown=www-data:www-data ./config/php.ini /usr/local/etc/php/php.ini
COPY --chown=www-data:www-data ./config/php-fpm.conf /usr/local/etc/php-fpm.conf
COPY --chown=www-data:www-data ./config/www.conf /usr/local/etc/php-fpm.d/www.conf

RUN apk add --no-cache --virtual .build-deps git curl && \
    curl -fsSL https://golang.org/dl/go${GOLANG_VERSION}.linux-amd64.tar.gz -o go.tar.gz && \
    tar -C /usr/local -xzf go.tar.gz && \
    export PATH=$PATH:/usr/local/go/bin && \
    go install github.com/boxboat/fixuid@latest && \
    cp $(go env GOPATH)/bin/fixuid /usr/local/bin/fixuid && \
    apk del .build-deps && \
    rm -rf /usr/local/go go.tar.gz /root/go

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