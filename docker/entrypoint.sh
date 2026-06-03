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

# ── 3. Nuke bootstrap cache FIRST before any artisan command ──────────────
rm -f bootstrap/cache/config.php
rm -f bootstrap/cache/routes-v7.php
rm -f bootstrap/cache/services.php
rm -f bootstrap/cache/packages.php
echo "Bootstrap cache cleared."

# ── 4. Generate APP_KEY ───────────────────────────────────────────────────
grep -v "^APP_KEY=" .env > /tmp/.env.tmp && mv /tmp/.env.tmp .env
echo "APP_KEY=" >> .env
php artisan key:generate --force --no-interaction
echo "APP_KEY result:"
grep "^APP_KEY=" .env

# ── 5. Fix permissions ────────────────────────────────────────────────────
chown -R www-data:www-data storage bootstrap/cache
chmod -R 775 storage bootstrap/cache

# ── 6. Create required app directories ───────────────────────────────────
for DIR in custom_views public/uploads public/uploads/product public/uploads/brand; do
    if [ ! -d "$DIR" ]; then
        mkdir -p "$DIR"
        echo "Created: $DIR"
    fi
done
chown -R www-data:www-data custom_views public/uploads
chmod -R 775 custom_views public/uploads

# ── 7. Storage symlink ────────────────────────────────────────────────────
if [ ! -L public/storage ]; then
    php artisan storage:link --no-interaction
else
    echo "Storage link already exists, skipping."
fi

# ── 8. Clear all caches (no config:cache — avoids timing race with nginx) ─
php artisan config:clear
php artisan route:clear
php artisan view:clear
php artisan cache:clear

# ── 9. Wait for DB then migrate ───────────────────────────────────────────
echo "Waiting for database..."
for i in $(seq 1 30); do
    php artisan migrate --force --no-interaction && break
    echo "  DB not ready ($i/30), retrying in 2s..."
    sleep 2
done

# ── 10. view:cache only (safe — no key dependency) ───────────────────────
php artisan view:cache
# config:cache  → SKIPPED (causes blank key race condition)
# route:cache   → SKIPPED (duplicate route names in this app)

# ── 11. Start services ────────────────────────────────────────────────────
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
