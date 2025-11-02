#!/bin/bash
# Startup script for Inventory Management System Docker container

set -e

echo "🚀 Starting Inventory Management System..."

# Initialize PostgreSQL data directory if it doesn't exist
if [ ! -f /var/lib/postgresql/data/PG_VERSION ]; then
    echo "📊 Initializing PostgreSQL database..."
    su - postgres -c "/usr/lib/postgresql/17/bin/initdb -D /var/lib/postgresql/data"
    echo "✅ PostgreSQL database initialized"
fi

# Start PostgreSQL
echo "🗄️ Starting PostgreSQL..."
su - postgres -c "/usr/lib/postgresql/17/bin/postgres -D /var/lib/postgresql/data -c config_file=/etc/postgresql/postgresql.conf" &
POSTGRES_PID=$!

# Wait for PostgreSQL to be ready
echo "⏳ Waiting for PostgreSQL to be ready..."
until pg_isready -h localhost -p 5432 -U postgres; do
    echo "Waiting for PostgreSQL..."
    sleep 2
done
echo "✅ PostgreSQL is ready"

# Initialize database
echo "🔧 Initializing database..."
/usr/local/bin/init-db.sh
echo "✅ Database initialization complete"

# Start Flask application
echo "🐍 Starting Flask application..."
cd /var/lib/inventory/app
export POSTGRES_HOST=localhost
export POSTGRES_PORT=5432
export POSTGRES_USER=inventory
export POSTGRES_PASSWORD=inventory_pi_2024
export POSTGRES_DB=inventory_db
export FLASK_ENV=production
export SECRET_KEY=inventory_docker_secret_key_change_in_production
export RELEASE_CANDIDATE=RC8
export IMAGE_STORAGE_METHOD=filesystem
export IMAGE_DIR=/var/lib/inventory/images
export TRANSFORMERS_CACHE=/var/lib/inventory/ml_cache
export HF_HOME=/var/lib/inventory/ml_cache
/var/lib/inventory/app/venv/bin/gunicorn --preload --workers 2 --bind 127.0.0.1:8000 main:app &
FLASK_PID=$!

# Wait for Flask to be ready
echo "⏳ Waiting for Flask application..."
until curl -f http://localhost:8000/health > /dev/null 2>&1; do
    echo "Waiting for Flask application..."
    sleep 2
done
echo "✅ Flask application is ready"

# Start Nginx
echo "🌐 Starting Nginx..."
nginx -g "daemon off;" &
NGINX_PID=$!

echo "✅ All services started successfully!"
echo "📱 Access the application at:"
echo "   HTTP:  http://localhost"
echo "   HTTPS: https://localhost"

# Keep the script running
wait