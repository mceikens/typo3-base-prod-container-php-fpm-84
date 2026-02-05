#!/bin/bash
set -a

echo "========================================="
echo "PHP-FPM TYPO3 (Rootless via fixuid)"
echo "User: $(whoami) (UID: $(id -u), GID: $(id -g))"
echo "========================================="

# DEBUG: PHP-Konfiguration
echo -e "\n=== PHP Configuration Debug ==="
echo "PHP Binary: $(which php)"
echo "PHP Version: $(php -v | head -n 1)"
echo "Configuration File (php.ini) Path: $(php --ini | grep 'Loaded Configuration File')"
echo "Scan this dir for additional .ini files: $(php --ini | grep 'Scan this dir')"

# DEBUG: Extension-Pfad
echo -e "\n=== Extension Directory ==="
echo "Extension dir: $(php -r 'echo ini_get("extension_dir");')"

# DEBUG: Welche Extensions sind geladen?
echo -e "\n=== Loaded Extensions ==="
php -m | grep -E "(redis|amqp|imagick|opcache|apcu)" || echo "No custom extensions found."

# PHP.ini Anpassungen mit Defaults
PHP_INI="/usr/local/etc/php/php.ini"

# Setze vernünftige Defaults falls nicht gesetzt
: ${PHP_MEMORY_LIMIT:=512M}
: ${PHP_MAX_EXECUTION_TIME:=240}
: ${PHP_MAX_INPUT_VARS:=1500}
: ${PHP_UPLOAD_MAX_FILESIZE:=64M}
: ${PHP_POST_MAX_SIZE:=64M}

if [ -w "$PHP_INI" ]; then
    echo -e "\n=== Applying PHP configuration ==="
    echo "  memory_limit: $PHP_MEMORY_LIMIT"
    echo "  max_execution_time: $PHP_MAX_EXECUTION_TIME"
    echo "  max_input_vars: $PHP_MAX_INPUT_VARS"
    echo "  upload_max_filesize: $PHP_UPLOAD_MAX_FILESIZE"
    echo "  post_max_size: $PHP_POST_MAX_SIZE"

    sed -i "s|memory_limit = .*|memory_limit = ${PHP_MEMORY_LIMIT}|" "$PHP_INI"
    sed -i "s|max_execution_time = .*|max_execution_time = ${PHP_MAX_EXECUTION_TIME}|" "$PHP_INI"
    sed -i "s|max_input_vars = .*|max_input_vars = ${PHP_MAX_INPUT_VARS}|" "$PHP_INI"
    sed -i "s|upload_max_filesize = .*|upload_max_filesize = ${PHP_UPLOAD_MAX_FILESIZE}|" "$PHP_INI"
    sed -i "s|post_max_size = .*|post_max_size = ${PHP_POST_MAX_SIZE}|" "$PHP_INI"
else
    echo "Warning: $PHP_INI is not writable or missing."
fi

# TYPO3 Verzeichnisse
echo -e "\n=== Ensuring TYPO3 directories ==="
for dir in var/cache var/log var/session public/fileadmin public/typo3temp; do
    mkdir -p "/var/www/html/$dir" 2>/dev/null
done

# PHP-FPM Test
echo -e "\n=== Testing PHP-FPM configuration ==="
FPM_TEST=$(php-fpm -t 2>&1)
if [ $? -eq 0 ]; then
    echo "✓ PHP-FPM configuration valid"
else
    echo "✗ PHP-FPM configuration error!"
    echo "$FPM_TEST"
    exit 1
fi

echo -e "\n=== Starting PHP-FPM ==="
exec "$@"