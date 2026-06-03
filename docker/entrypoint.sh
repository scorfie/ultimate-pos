#!/bin/sh
set -e

cd /var/www/html

# ── 1. Ensure .env exists ──────────────────────────────────────────────────
if [ ! -f .env ]; then
    if [ -f .env.example ]; then
        cp .env.example .env
        echo ".env created from .env.example"
    else
        echo "ERROR: No .env or .env.example found!" && exit 1
    fi
fi

# ── 2. Inject Coolify env vars into .env ──────────────────────────────────
set_env() {
    KEY=$1
    VALUE=$2
    grep -v "^${KEY}=" .env > /tmp/.env.tmp && mv /tmp/.env.tmp .env
    echo "${KEY}=\"${VALUE}\"" >> .env
}

[ -n "$APP_NAME" ]         && set_env APP_NAME         "$APP_NAME"
[ -n "$APP_ENV" ]          && set_env APP_ENV           "$APP_ENV"
[ -n "$APP_DEBUG" ]        && set_env APP_DEBUG         "$APP_DEBUG"
[ -n "$APP_URL" ]          && set_env APP_URL           "$APP_URL"
[ -n "$DB_HOST" ]          && set_env DB_HOST           "$DB_HOST"
[ -n "$DB_PORT" ]          && set_env DB_PORT           "$DB_PORT"
[ -n "$DB_DATABASE" ]      && set_env DB_DATABASE       "$DB_DATABASE"
[ -n "$DB_USERNAME" ]      && set_env DB_USERNAME       "$DB_USERNAME"
[ -n "$DB_PASSWORD" ]      && set_env DB_PASSWORD       "$DB_PASSWORD"
[ -n "$SESSION_DRIVER" ]   && set_env SESSION_DRIVER    "$SESSION_DRIVER"
[ -n "$CACHE_DRIVER" ]     && set_env CACHE_DRIVER      "$CACHE_DRIVER"
[ -n "$QUEUE_CONNECTION" ] && set_env QUEUE_CONNECTION  "$QUEUE_CONNECTION"

# ── 3. Generate APP_KEY using artisan ─────────────────────────────────────
grep -q "^APP_KEY=" .env || echo "APP_KEY=" >> .env
php artisan key:generate --force --no-interaction
echo "APP_KEY value:"
grep "^APP_KEY=" .env

# ── 4. Fix permissions ────────────────────────────────────────────────────
chown -R www-data:www-data storage bootstrap/cache
chmod -R 775 storage bootstrap/cache

# ── 4b. Create required app directories ──────────────────────────────────
for DIR in custom_views public/uploads public/uploads/product public/uploads/brand; do
    if [ ! -d "$DIR" ]; then
        mkdir -p "$DIR"
        echo "Created missing directory: $DIR"
    fi
done
chown -R www-data:www-data custom_views public/uploads
chmod -R 775 custom_views public/uploads

# ── 5. Storage symlink ────────────────────────────────────────────────────
if [ ! -L public/storage ]; then
    php artisan storage:link --no-interaction
else
    echo "Storage link already exists, skipping."
fi

# ── 6. Nuke ALL stale bootstrap caches ───────────────────────────────────
rm -f bootstrap/cache/config.php
rm -f bootstrap/cache/routes-v7.php
rm -f bootstrap/cache/services.php
rm -f bootstrap/cache/packages.php
php artisan config:clear 2>/dev/null || true
php artisan route:clear  2>/dev/null || true
php artisan view:clear   2>/dev/null || true
php artisan cache:clear  2>/dev/null || true

# ── 7. Wait for DB then migrate ───────────────────────────────────────────
echo "Waiting for database..."
for i in $(seq 1 30); do
    php artisan migrate --force --no-interaction && break
    echo "  DB not ready yet ($i/30), retrying in 2s..."
    sleep 2
done

# ── 8. Rebuild caches ─────────────────────────────────────────────────────
php artisan config:cache
php artisan view:cache
# route:cache intentionally skipped — duplicate route names in this app

# ── 9. Start services ─────────────────────────────────────────────────────
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
