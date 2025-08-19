#!/bin/bash
set -e

echo "🚀 Starting Flask Development Container..."

# Generate SSL certificates if they don't exist
if [ ! -f "/ssl-certs/cert.pem" ] && [ -d "/ssl-certs" ]; then
    echo "🔐 Generating SSL certificates..."
    openssl req -x509 -newkey rsa:2048 -keyout /ssl-certs/private.key -out /ssl-certs/cert.crt -days 365 -nodes -subj "/C=US/ST=Local/L=Development/O=FlaskInventory/CN=localhost"
    cat /ssl-certs/cert.crt /ssl-certs/private.key > /ssl-certs/cert.pem
fi

# Ensure postgres user owns the data directory
sudo chown -R postgres:postgres /postgres-data
sudo chmod 700 /postgres-data

# Check if PostgreSQL is already initialized
if [ ! -f "/postgres-data/postgresql.conf" ]; then
    echo "🗄️ Initializing PostgreSQL database..."
    
    # Initialize PostgreSQL as postgres user
    sudo -u postgres /usr/lib/postgresql/*/bin/initdb -D /postgres-data
    
    # Configure PostgreSQL
    echo "host all all 127.0.0.1/32 md5" >> /postgres-data/pg_hba.conf
    echo "host all all ::1/128 md5" >> /postgres-data/pg_hba.conf
    echo "listen_addresses = 'localhost'" >> /postgres-data/postgresql.conf
    echo "port = 5432" >> /postgres-data/postgresql.conf
    
    echo "✅ PostgreSQL initialized"
fi

# Start PostgreSQL
echo "🗄️ Starting PostgreSQL..."
sudo -u postgres /usr/lib/postgresql/*/bin/pg_ctl -D /postgres-data -l /postgres-data/postgresql.log start

# Wait for PostgreSQL to be ready
echo "⏳ Waiting for PostgreSQL to start..."
for i in {1..30}; do
    if sudo -u postgres /usr/lib/postgresql/*/bin/pg_isready -h localhost -p 5432 >/dev/null 2>&1; then
        echo "✅ PostgreSQL is ready!"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "❌ PostgreSQL failed to start after 30 attempts"
        echo "📋 PostgreSQL log:"
        cat /postgres-data/postgresql.log 2>/dev/null || echo "No log file found"
        exit 1
    fi
    echo "   Attempt $i/30 - waiting..."
    sleep 2
done

# Skip database initialization if using existing production database
if [ "${SKIP_DB_INIT}" = "true" ]; then
    echo "⏭️  Skipping database initialization (using existing production database)"
else
    # Create development user and database (only if they don't exist)
    echo "👤 Setting up development database..."
    sudo -u postgres /usr/lib/postgresql/*/bin/psql -h localhost -p 5432 -c "SELECT 1" >/dev/null 2>&1

    # Create user if it doesn't exist
    sudo -u postgres /usr/lib/postgresql/*/bin/psql -h localhost -p 5432 -tc "SELECT 1 FROM pg_user WHERE usename = 'flask_dev'" | grep -q 1 || \
    sudo -u postgres /usr/lib/postgresql/*/bin/createuser -h localhost -p 5432 -s flask_dev

    # Create database if it doesn't exist  
    sudo -u postgres /usr/lib/postgresql/*/bin/psql -h localhost -p 5432 -tc "SELECT 1 FROM pg_database WHERE datname = 'flask_inventory'" | grep -q 1 || \
    sudo -u postgres /usr/lib/postgresql/*/bin/createdb -h localhost -p 5432 -O flask_dev flask_inventory

    # Set password
    DB_PASSWORD=flask_dev_pass
    sudo -u postgres /usr/lib/postgresql/*/bin/psql -h localhost -p 5432 -c "ALTER USER flask_dev PASSWORD '$DB_PASSWORD';"

    echo "✅ Database setup complete!"

    # Only set database environment variables if not already set by Docker Compose
    export POSTGRES_HOST=${POSTGRES_HOST:-localhost}
    export POSTGRES_PORT=${POSTGRES_PORT:-5432}
    export POSTGRES_USER=${POSTGRES_USER:-flask_dev}
    export POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-$DB_PASSWORD}
    export POSTGRES_DB=${POSTGRES_DB:-flask_inventory}
fi

# Create necessary directories if they don't exist
mkdir -p /app/uploads /app/logs

# Start Flask application in development mode with auto-reload
echo "🌐 Starting Flask application in development mode..."
cd /app

# Use Flask development server for auto-reload
if [ -f "main.py" ]; then
    exec python main.py
else
    echo "❌ No main.py found in /app"
    exit 1
fi