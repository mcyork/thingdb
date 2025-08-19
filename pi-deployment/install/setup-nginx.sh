#!/bin/bash

echo "🌐 Setting up Nginx for Raspberry Pi..."

# Copy Pi-specific nginx configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PI_DEPLOYMENT_DIR="$(dirname "$SCRIPT_DIR")"

# Add rate limiting zones to main nginx.conf
if ! grep -q "limit_req_zone" /etc/nginx/nginx.conf; then
    sed -i '/http {/a\\n    # Rate limiting zones for inventory app\n    limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;\n    limit_req_zone $binary_remote_addr zone=images:10m rate=50r/s;' /etc/nginx/nginx.conf
fi

cp "$PI_DEPLOYMENT_DIR/config/nginx-pi.conf" /etc/nginx/sites-available/inventory
ln -sf /etc/nginx/sites-available/inventory /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Create nginx directories
mkdir -p /var/log/nginx
mkdir -p /var/cache/nginx/{client_temp,proxy_temp,fastcgi_temp,uwsgi_temp,scgi_temp}
chown -R www-data:www-data /var/cache/nginx
chown -R www-data:www-data /var/log/nginx

# Test nginx configuration
nginx -t
if [ $? -ne 0 ]; then
    echo "❌ Nginx configuration test failed!"
    echo "💡 Check the configuration file at /etc/nginx/sites-available/inventory"
    exit 1
fi

echo "✅ Nginx setup complete"