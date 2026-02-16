# =============================================================================
# Dockerfile — Builds the PHP Symfony chat application container
# =============================================================================
#
# This is a simple development Dockerfile that:
#   1. Starts from the official PHP 8.3 CLI image
#   2. Installs system dependencies (unzip for Composer, zip extension for packages)
#   3. Copies Composer (PHP package manager) from the official Composer image
#   4. Copies the sibling strands-php-client library into the container
#   5. Copies the Symfony application code
#   6. Runs Composer to install PHP dependencies
#   7. Starts PHP's built-in web server on port 8080
#
# NOTE: This uses PHP's built-in web server, which is fine for development
# but NOT suitable for production. For production, use Nginx + PHP-FPM or
# a similar setup.
#
# BUILD CONTEXT:
#   The build context is the the-summit-chatroom/ directory (set in docker-compose.yml).
#   The "additional_contexts" in docker-compose.yml makes the strands-php-client
#   directory available via the "strands-php-client" build context name.
# =============================================================================

# Use PHP 8.3 CLI as the base image (no Apache/Nginx — we use the built-in server)
FROM php:8.3-cli

# Install system packages needed by PHP extensions and Composer
RUN apt-get update && apt-get install -y \
    unzip \
    libzip-dev \
    curl \
    && docker-php-ext-install zip \
    && rm -rf /var/lib/apt/lists/*

# Copy Composer binary from the official Composer Docker image
# This avoids having to install Composer manually
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

WORKDIR /app

# Copy the strands-php-client library into /libs/ inside the container.
# This is needed because composer.json references it via a "path" repository
# (normally at ../strands-php-client relative to the project root).
# Inside Docker, we put it at /libs/strands-php-client instead.
COPY --from=strands-php-client . /libs/strands-php-client

# Copy the entire Symfony application into the container
COPY . /app/

# Rewrite the Composer path repository to point to the Docker location.
# In local development, composer.json says "../strands-php-client" (relative to project root).
# Inside Docker, the library is at "/libs/strands-php-client" (absolute path).
# Both composer.json and composer.lock reference the path and both need updating.
RUN sed -i 's|\.\./strands-php-client|/libs/strands-php-client|g' composer.json composer.lock

# Install PHP dependencies (--no-dev skips test/dev packages, --optimize-autoloader for speed)
RUN composer install --no-dev --optimize-autoloader

# The PHP built-in server listens on this port
EXPOSE 8080

# Start PHP's built-in web server, serving from the public/ directory
# The -t flag sets the document root (where index.php lives)
CMD ["php", "-S", "0.0.0.0:8080", "-t", "public"]
