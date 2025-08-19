#!/bin/bash

echo "🚀 Starting Flask Development System..."

# Change to the inv2-dev directory
cd "$(dirname "$0")/.."

# Check if images exist
if ! docker images | grep -q "flask-dev-app"; then
    echo "⚠️  Development images not found. Building them now..."
    ./scripts/build-dev.sh
fi

# Generate SSL certificates if they don't exist
if [ ! -f "config/ssl-certs/cert.pem" ]; then
    echo "🔐 Generating SSL certificates..."
    mkdir -p config/ssl-certs
    openssl req -x509 -newkey rsa:2048 -keyout config/ssl-certs/private.key -out config/ssl-certs/cert.crt -days 365 -nodes -subj "/C=US/ST=Local/L=Development/O=FlaskInventory/CN=localhost"
    cat config/ssl-certs/cert.crt config/ssl-certs/private.key > config/ssl-certs/cert.pem
    echo "✅ SSL certificates generated"
fi

# Start the containers
echo "🐳 Starting development containers..."
docker-compose -f docker/docker-compose-dev.yml up -d

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Development system started successfully!"
    echo ""
    echo "🌐 Access points:"
    echo "   - HTTPS: https://localhost"
    echo "   - HTTP: http://localhost (redirects to HTTPS)"
    echo "   - Stats: http://localhost:8404"
    echo ""
    echo "💡 Development features:"
    echo "   - Live reload enabled (edit files in src/)"
    echo "   - Debug mode active"
    echo "   - Database in config/data/"
    echo ""
    echo "📋 Commands:"
    echo "   View logs: docker-compose -f docker/docker-compose-dev.yml logs -f"
    echo "   Stop: docker-compose -f docker/docker-compose-dev.yml down"
    echo "   Shell: docker-compose -f docker/docker-compose-dev.yml exec flask-app /bin/bash"
else
    echo "❌ Failed to start development system"
    echo "Check logs: docker-compose -f docker/docker-compose-dev.yml logs"
fi