#!/bin/sh
set -e

# Generate app key if not set
php artisan key:generate --no-interaction --force

# Create storage symlink
php artisan storage:link --no-interaction || true

# Run migrations
php artisan migrate --force --no-interaction

# Cache config for performance
php artisan config:cache
php artisan route:cache
php artisan view:cache

exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
