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
    if grep -q "^${KEY}=" .env; then
        sed -i "s|^${KEY}=.*|${KEY}=${VALUE}|" .env
    else
        echo "${KEY}=${VALUE}" >> .env
    fi
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

# ── 3. Generate APP_KEY and write it directly into .env ───────────────────
# Do NOT use artisan key:generate yet — .env must have the key line present
# Ensure APP_KEY line exists first (even if blank)
grep -q "^APP_KEY=" .env || echo "APP_KEY=" >> .env

# Generate the key manually and inject it
APP_KEY_VALUE=$(php -r "echo 'base64:' . base64_encode(random_bytes(32));")
sed -i "s|^APP_KEY=.*|APP_KEY=${APP_KEY_VALUE}|" .env
echo "APP_KEY set."

# ── 4. Fix permissions ────────────────────────────────────────────────────
chown -R www-data:www-data storage bootstrap/cache
chmod -R 775 storage bootstrap/cache

# ── 5. Storage symlink — skip if already exists ───────────────────────────
if [ ! -L public/storage ]; then
    php artisan storage:link --no-interaction
else
    echo "Storage link already exists, skipping."
fi

# ── 6. Clear stale caches before anything else ───────────────────────────
php artisan config:clear
php artisan route:clear
php artisan view:clear
php artisan cache:clear

# ── 7. Wait for DB, then migrate ─────────────────────────────────────────
echo "Waiting for database..."
for i in $(seq 1 30); do
    php artisan migrate --force --no-interaction && break
    echo "  DB not ready yet ($i/30), retrying in 2s..."
    sleep 2
done

# ── 8. Rebuild caches ────────────────────────────────────────────────────
php artisan config:cache

# Skip route:cache — this app has duplicate route names which breaks it
# php artisan route:cache

php artisan view:cache

# ── 9. Start services ────────────────────────────────────────────────────
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
