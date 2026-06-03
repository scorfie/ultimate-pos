# Dockerfile
FROM php:8.3-fpm-alpine

# Install system dependencies
RUN apk add --no-cache \
    nginx \
    nodejs \
    npm \
    git \
    curl \
    zip \
    unzip \
    libpng-dev \
    libzip-dev \
    oniguruma-dev \
    openssl-dev \
    supervisor

# Install PHP extensions
RUN docker-php-ext-install \
    pdo_mysql \
    bcmath \
    gd \
    mbstring \
    zip \
    fileinfo \
    opcache

# Install Composer
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /var/www/html

# Copy app files
COPY . .

# Create directories required by Ultimate POS
RUN mkdir -p \
    /var/www/html/custom_views \
    /var/www/html/public/uploads \
    /var/www/html/public/uploads/product \
    /var/www/html/public/uploads/brand \
    && chown -R www-data:www-data \
        /var/www/html/custom_views \
        /var/www/html/public/uploads \
    && chmod -R 775 \
        /var/www/html/custom_views \
        /var/www/html/public/uploads

# Install PHP dependencies
RUN composer install --no-dev --optimize-autoloader --no-interaction

# Delete any bootstrap cache baked in during composer install
RUN rm -f bootstrap/cache/config.php \
          bootstrap/cache/routes-v7.php \
          bootstrap/cache/services.php \
          bootstrap/cache/packages.php

# Install & build JS assets
RUN npm install && npm run build || true

# Set permissions
RUN chown -R www-data:www-data /var/www/html \
    && chmod -R 775 storage bootstrap/cache

# Nginx config
COPY docker/nginx.conf /etc/nginx/nginx.conf

# Supervisor config
COPY docker/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Entrypoint script
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 80

ENTRYPOINT ["/entrypoint.sh"]
