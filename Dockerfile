FROM php:8.2-apache

# Install system dependencies & PHP extensions required by Laravel/UltimatePOS
RUN apt-get update && apt-get install -y \
    libpng-dev \
    libjpeg-dev \
    libfreetype6-dev \
    zip \
    libzip-dev \
    unzip \
    git \
    curl \
    libicu-dev \
    && rm -rf /var/lib/apt/lists/*

# Configure and install PHP extensions
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install pdo_mysql bcmath gd zip intl opcache

# Optimize PHP settings for Ultimate POS (Crucial for large CSV/Excel imports & item images)
RUN echo "file_uploads = On\n\
memory_limit = 512M\n\
upload_max_filesize = 128M\n\
post_max_size = 128M\n\
max_execution_time = 600\n\
" > /usr/local/etc/php/conf.d/ultimate-pos.ini

# Enable Apache mod_rewrite for Laravel routing
RUN a2enmod rewrite

# Set Apache document root to Laravel's public directory
ENV APACHE_DOCUMENT_ROOT /var/www/html/public
RUN sed -ri -e 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/sites-available/*.conf
RUN sed -ri -e 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/apache2.conf /etc/apache2/conf-available/*.conf

# Set working directory
WORKDIR /var/www/html

# Copy application files
COPY . /var/www/html

# Install Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Create necessary directories and set initial permissions
RUN mkdir -p /var/www/html/storage /var/www/html/public/uploads \
    && chown -R www-data:www-data /var/www/html

# Persistent entrypoint trick: Moves .env to a persistent storage directory 
# so it doesn't get wiped out when the container restarts or updates.
RUN echo '#!/bin/sh\n\
set -e\n\
if [ ! -f /var/www/html/storage/.env ]; then\n\
    if [ -f /var/www/html/.env ]; then\n\
        mv /var/www/html/.env /var/www/html/storage/.env\n\
    else\n\
        cp /var/www/html/.env.example /var/www/html/storage/.env\n\
    fi\n\
fi\n\
ln -sf /var/www/html/storage/.env /var/www/html/.env\n\
chown -R www-data:www-data /var/www/html/storage /var/www/html/public/uploads\n\
exec apache2-foreground' > /usr/local/bin/docker-entrypoint.sh \
    && chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 80

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
