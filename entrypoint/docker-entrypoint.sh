#!/bin/bash
set -e

echo "========================================="
echo "PHP-FPM TYPO3 Base Container Starting..."
echo "========================================="

# Farben für Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# UID/GID Anpassung wenn PUID/PGID gesetzt sind
if [ ! -z "$PUID" ] && [ ! -z "$PGID" ]; then
    CURRENT_UID=$(id -u www-data)
    CURRENT_GID=$(id -g www-data)

    if [ "$CURRENT_UID" != "$PUID" ] || [ "$CURRENT_GID" != "$PGID" ]; then
        echo -e "${YELLOW}Adjusting www-data UID:GID to $PUID:$PGID${NC}"

        # Gruppe anpassen
        if [ "$CURRENT_GID" != "$PGID" ]; then
            groupmod -o -g "$PGID" www-data
        fi

        # User anpassen
        if [ "$CURRENT_UID" != "$PUID" ]; then
            usermod -o -u "$PUID" www-data
        fi

        echo -e "${GREEN}✓ UID/GID adjusted successfully${NC}"
    else
        echo -e "${GREEN}✓ UID/GID already correct ($PUID:$PGID)${NC}"
    fi
fi

# Log-Verzeichnis für PHP-FPM erstellen
echo "Setting up log directories..."
mkdir -p /var/log/php-fpm
chown www-data:www-data /var/log/php-fpm
chmod 755 /var/log/php-fpm

# Named Pipes (FIFOs) für Logs erstellen
mkfifo /var/log/php-fpm/access.log
mkfifo /var/log/php-fpm/error.log
mkfifo /var/log/php-fpm/slow.log
mkfifo /var/log/php-fpm/php-error.log

chown www-data:www-data /var/log/php-fpm/*.log
chmod 666 /var/log/php-fpm/*.log

# Log-Weiterleitung im Hintergrund starten (stdout/stderr für fluentd)
cat /var/log/php-fpm/access.log &
cat /var/log/php-fpm/error.log &
cat /var/log/php-fpm/slow.log >&2 &
cat /var/log/php-fpm/php-error.log >&2 &

echo -e "${GREEN}✓ Log pipes created and forwarding to stdout/stderr${NC}"

# PHP.ini Runtime-Anpassungen via ENV
echo "Applying PHP configuration from environment..."
sed -i "s/memory_limit = .*/memory_limit = ${PHP_MEMORY_LIMIT}/" /usr/local/etc/php/php.ini
sed -i "s/max_execution_time = .*/max_execution_time = ${PHP_MAX_EXECUTION_TIME}/" /usr/local/etc/php/php.ini
sed -i "s/max_input_vars = .*/max_input_vars = ${PHP_MAX_INPUT_VARS}/" /usr/local/etc/php/php.ini
sed -i "s/upload_max_filesize = .*/upload_max_filesize = ${PHP_UPLOAD_MAX_FILESIZE}/" /usr/local/etc/php/php.ini
sed -i "s/post_max_size = .*/post_max_size = ${PHP_POST_MAX_SIZE}/" /usr/local/etc/php/php.ini

# Opcache Einstellungen
sed -i "s/opcache.enable=.*/opcache.enable=${PHP_OPCACHE_ENABLE}/" /usr/local/etc/php/php.ini
sed -i "s/opcache.memory_consumption=.*/opcache.memory_consumption=${PHP_OPCACHE_MEMORY}/" /usr/local/etc/php/php.ini
sed -i "s/opcache.max_accelerated_files=.*/opcache.max_accelerated_files=${PHP_OPCACHE_MAX_FILES}/" /usr/local/etc/php/php.ini

# Timezone setzen
if [ ! -z "$TZ" ]; then
    echo "date.timezone = ${TZ}" > /usr/local/etc/php/conf.d/timezone.ini
    echo -e "${GREEN}✓ Timezone set to: $TZ${NC}"
fi

# PHP-FPM Pool Konfiguration anpassen
echo "Configuring PHP-FPM pool..."
sed -i "s/pm = .*/pm = ${PHP_FPM_PM}/" /usr/local/etc/php-fpm.d/www.conf
sed -i "s/pm.max_children = .*/pm.max_children = ${PHP_FPM_PM_MAX_CHILDREN}/" /usr/local/etc/php-fpm.d/www.conf
sed -i "s/pm.start_servers = .*/pm.start_servers = ${PHP_FPM_PM_START_SERVERS}/" /usr/local/etc/php-fpm.d/www.conf
sed -i "s/pm.min_spare_servers = .*/pm.min_spare_servers = ${PHP_FPM_PM_MIN_SPARE_SERVERS}/" /usr/local/etc/php-fpm.d/www.conf
sed -i "s/pm.max_spare_servers = .*/pm.max_spare_servers = ${PHP_FPM_PM_MAX_SPARE_SERVERS}/" /usr/local/etc/php-fpm.d/www.conf
sed -i "s/pm.max_requests = .*/pm.max_requests = ${PHP_FPM_PM_MAX_REQUESTS}/" /usr/local/etc/php-fpm.d/www.conf

# Berechtigungen anpassen wenn Volume gemountet ist
if mount | grep -q "/var/www/html"; then
    echo "Checking /var/www/html permissions..."

    # Nur anpassen wenn noch nicht korrekt
    CURRENT_OWNER=$(stat -c '%u:%g' /var/www/html 2>/dev/null || echo "0:0")
    EXPECTED_OWNER="${PUID}:${PGID}"

    if [ "$CURRENT_OWNER" != "$EXPECTED_OWNER" ]; then
        echo -e "${YELLOW}Fixing ownership of /var/www/html...${NC}"
        chown -R www-data:www-data /var/www/html
        echo -e "${GREEN}✓ Ownership fixed${NC}"
    fi

    # TYPO3 spezifische Verzeichnisse
    for dir in var var/cache var/log var/session public/fileadmin public/typo3temp; do
        if [ ! -d "/var/www/html/$dir" ]; then
            mkdir -p "/var/www/html/$dir"
            chown www-data:www-data "/var/www/html/$dir"
        fi
        chmod 775 "/var/www/html/$dir" 2>/dev/null || true
    done
fi

# PHP Extensions anzeigen
echo -e "\n${GREEN}Loaded PHP Extensions:${NC}"
php -m | grep -E "(redis|amqp|imagick|opcache|apcu)" || echo "Core extensions loaded"

# Version Info
echo -e "\n${GREEN}Software Versions:${NC}"
echo "PHP: $(php -v | head -n 1)"
echo "Composer: $(composer --version 2>/dev/null | head -n 1 || echo 'Not available')"
echo "Redis: $(redis-cli --version 2>/dev/null || echo 'Not available')"

# Config Test
echo -e "\n${YELLOW}Testing PHP-FPM configuration...${NC}"
if php-fpm -t; then
    echo -e "${GREEN}✓ PHP-FPM configuration valid${NC}"
else
    echo -e "${RED}✗ PHP-FPM configuration error!${NC}"
    exit 1
fi

echo -e "\n${GREEN}=========================================${NC}"
echo -e "${GREEN}Container ready! Starting PHP-FPM...${NC}"
echo -e "${GREEN}=========================================${NC}\n"

# PHP-FPM als www-data starten (nicht als root!)
if [ "$(id -u)" = "0" ]; then
    exec su-exec www-data "$@"
else
    exec "$@"
fi