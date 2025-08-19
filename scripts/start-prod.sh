#!/bin/bash

echo "🚀 Starting Flask Production System..."

# Change to the inv2-dev directory
cd "$(dirname "$0")/.."

# Check if images exist
if ! docker images | grep -q "flask-source"; then
    echo "⚠️  Production images not found. Building them now..."
    ./scripts/build-prod.sh
fi

# Generate SSL certificates if they don't exist
if [ ! -f "config/ssl-certs/cert.pem" ]; then
    echo "🔐 Generating SSL certificates..."
    mkdir -p config/ssl-certs
    openssl req -x509 -newkey rsa:2048 -keyout config/ssl-certs/private.key -out config/ssl-certs/cert.crt -days 365 -nodes -subj "/C=US/ST=Local/L=Production/O=FlaskInventory/CN=localhost"
    cat config/ssl-certs/cert.crt config/ssl-certs/private.key > config/ssl-certs/cert.pem
    echo "✅ SSL certificates generated"
fi

# Load environment variables if config exists
if [ -f "config/app-config/app.env" ]; then
    echo "📋 Loading configuration from app.env..."
    export $(cat config/app-config/app.env | grep -v '^#' | xargs)
fi

# Start the containers
echo "🐳 Starting production containers..."
docker-compose -f docker/docker-compose-prod.yml up -d

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Production system started successfully!"
    echo ""
    echo "🌐 Access points:"
    echo "   - HTTPS: https://localhost"
    echo "   - HTTP: http://localhost (redirects to HTTPS)"
    echo "   - Stats: http://localhost:8404"
    echo ""
    echo "📋 Commands:"
    echo "   View logs: docker-compose -f docker/docker-compose-prod.yml logs -f"
    echo "   Stop: docker-compose -f docker/docker-compose-prod.yml down"
    echo "   Shell: docker-compose -f docker/docker-compose-prod.yml exec flask-app /bin/bash"
else
    echo "❌ Failed to start production system"
    echo "Check logs: docker-compose -f docker/docker-compose-prod.yml logs"
fi