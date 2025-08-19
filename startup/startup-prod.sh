#!/bin/bash
set -e

echo "🚀 Starting Flask Production Container..."

# Check if we're using external PostgreSQL
if [ ! -z "$EXTERNAL_POSTGRES_HOST" ]; then
    echo "🔗 Using external PostgreSQL at $EXTERNAL_POSTGRES_HOST:$EXTERNAL_POSTGRES_PORT"
    
    # Test external database connection
    echo "🧪 Testing external database connection..."
    export PGPASSWORD=$EXTERNAL_POSTGRES_PASSWORD
    
    for i in {1..30}; do
        if psql -h $EXTERNAL_POSTGRES_HOST -p $EXTERNAL_POSTGRES_PORT -U $EXTERNAL_POSTGRES_USER -d $EXTERNAL_POSTGRES_DB -c "SELECT version();" >/dev/null 2>&1; then
            echo "✅ External database connection successful!"
            break
        fi
        if [ $i -eq 30 ]; then
            echo "❌ Failed to connect to external database after 30 attempts"
            exit 1
        fi
        echo "   Attempt $i/30 - waiting..."
        sleep 2
    done
else
    echo "🗄️ Using internal PostgreSQL database..."
    
    # Generate SSL certificates if they don't exist
    if [ ! -f "/config/ssl-certs/cert.pem" ] && [ -d "/config/ssl-certs" ]; then
        echo "🔐 Generating SSL certificates..."
        openssl req -x509 -newkey rsa:2048 -keyout /config/ssl-certs/private.key -out /config/ssl-certs/cert.crt -days 365 -nodes -subj "/C=US/ST=Local/L=Production/O=FlaskInventory/CN=localhost"
        cat /config/ssl-certs/cert.crt /config/ssl-certs/private.key > /config/ssl-certs/cert.pem
    fi
    
    # Ensure postgres user owns the data directory
    sudo chown -R postgres:postgres /config/data
    sudo chmod 700 /config/data
    
    # Check if PostgreSQL is already initialized
    if [ ! -f "/config/data/postgresql.conf" ]; then
        echo "🗄️ Initializing PostgreSQL database..."
        
        # Initialize PostgreSQL as postgres user
        sudo -u postgres /usr/lib/postgresql/*/bin/initdb -D /config/data
        
        # Configure PostgreSQL
        echo "host all all 127.0.0.1/32 md5" >> /config/data/pg_hba.conf
        echo "host all all ::1/128 md5" >> /config/data/pg_hba.conf
        echo "listen_addresses = 'localhost'" >> /config/data/postgresql.conf
        echo "port = 5432" >> /config/data/postgresql.conf
        
        echo "✅ PostgreSQL initialized"
    fi
    
    # Start PostgreSQL
    echo "🗄️ Starting PostgreSQL..."
    sudo -u postgres /usr/lib/postgresql/*/bin/pg_ctl -D /config/data -l /config/data/postgresql.log start
    
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
            cat /config/data/postgresql.log 2>/dev/null || echo "No log file found"
            exit 1
        fi
        echo "   Attempt $i/30 - waiting..."
        sleep 2
    done
    
    # Create production user and database (only if they don't exist)
    echo "👤 Setting up production database..."
    sudo -u postgres /usr/lib/postgresql/*/bin/psql -h localhost -p 5432 -c "SELECT 1" >/dev/null 2>&1
    
    # Create user if it doesn't exist
    sudo -u postgres /usr/lib/postgresql/*/bin/psql -h localhost -p 5432 -tc "SELECT 1 FROM pg_user WHERE usename = 'flask_prod'" | grep -q 1 || \
    sudo -u postgres /usr/lib/postgresql/*/bin/createuser -h localhost -p 5432 -s flask_prod
    
    # Create database if it doesn't exist  
    sudo -u postgres /usr/lib/postgresql/*/bin/psql -h localhost -p 5432 -tc "SELECT 1 FROM pg_database WHERE datname = 'flask_inventory'" | grep -q 1 || \
    sudo -u postgres /usr/lib/postgresql/*/bin/createdb -h localhost -p 5432 -O flask_prod flask_inventory
    
    # Set password from environment or use default
    DB_PASSWORD=${POSTGRES_PASSWORD:-flask_prod_pass}
    sudo -u postgres /usr/lib/postgresql/*/bin/psql -h localhost -p 5432 -c "ALTER USER flask_prod PASSWORD '$DB_PASSWORD';"
    
    echo "✅ Database setup complete!"
    
    # Set internal database environment variables
    export POSTGRES_HOST=localhost
    export POSTGRES_PORT=5432
    export POSTGRES_USER=flask_prod
    export POSTGRES_PASSWORD=$DB_PASSWORD
    export POSTGRES_DB=flask_inventory
fi

# Create necessary directories if they don't exist
mkdir -p /app/uploads /app/logs

# Load any custom configuration from mounted config
if [ -f "/config/app-config/app.env" ]; then
    echo "📋 Loading custom configuration..."
    source /config/app-config/app.env
fi

# Start Flask application in production mode
echo "🌐 Starting Flask application in production mode..."
cd /app/src

# Use gunicorn for production
if [ -f "main.py" ]; then
    exec gunicorn --bind 0.0.0.0:5000 --workers 4 --timeout 120 main:app
else
    echo "❌ No main.py found in /app/src"
    exit 1
fi