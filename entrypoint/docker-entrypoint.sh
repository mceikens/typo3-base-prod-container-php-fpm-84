#!/bin/bash
# set -e entfernt, um manuelle Fehlerprüfung zu ermöglichen
set -a # Exportiert alle folgenden Variablen automatisch

echo "========================================="
echo "PHP-FPM TYPO3 (Rootless via fixuid)"
echo "User: $(whoami) (UID: $(id -u), GID: $(id -g))"
echo "========================================="

# 1. PHP.ini Anpassungen (Fehlertolerant)
# Wir prüfen erst, ob die Datei existiert und beschreibbar ist
PHP_INI="/usr/local/etc/php/php.ini"

if [ -w "$PHP_INI" ]; then
    echo "Applying PHP configuration..."
    # Nutze ein anderes Trennzeichen (|), falls Werte Pfade enthalten
    sed -i "s|memory_limit = .*|memory_limit = ${PHP_MEMORY_LIMIT}|" "$PHP_INI"
    sed -i "s|max_execution_time = .*|max_execution_time = ${PHP_MAX_EXECUTION_TIME}|" "$PHP_INI"
    sed -i "s|max_input_vars = .*|max_input_vars = ${PHP_MAX_INPUT_VARS}|" "$PHP_INI"
    sed -i "s|upload_max_filesize = .*|upload_max_filesize = ${PHP_UPLOAD_MAX_FILESIZE}|" "$PHP_INI"
    sed -i "s|post_max_size = .*|post_max_size = ${PHP_POST_MAX_SIZE}|" "$PHP_INI"
else
    echo "Warning: $PHP_INI is not writable or missing. Skipping sed adjustments."
fi

# 2. TYPO3 Verzeichnisse (ohne chown!)
echo "Ensuring TYPO3 directories..."
for dir in var/cache var/log var/session public/fileadmin public/typo3temp; do
    mkdir -p "/var/www/html/$dir" 2>/dev/null
done

# 3. Extensions anzeigen
echo -e "\nLoaded PHP Extensions:"
# Wir fangen den Output ab, damit ein Grep-Fehler nicht das Skript killt
LOADED_EXTS=$(php -m)
echo "$LOADED_EXTS" | grep -E "(redis|amqp|imagick|opcache|apcu)" || echo "No custom extensions found."

# 4. Config Test (WICHTIG: Hier kracht es oft bei Rootless)
echo -e "\nTesting PHP-FPM configuration..."
# Wir leiten stderr um, um zu sehen, WARUM es fehlschlägt
FPM_TEST=$(php-fpm -t 2>&1)
if [ $? -eq 0 ]; then
    echo "✓ PHP-FPM configuration valid"
else
    echo "✗ PHP-FPM configuration error!"
    echo "$FPM_TEST"
    exit 1
fi

echo "Starting PHP-FPM..."
exec "$@"