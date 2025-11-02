#!/bin/bash
# Database initialization script for Docker container

set -e

echo "🗄️ Initializing PostgreSQL database..."

# Wait for PostgreSQL to be ready
until pg_isready -h localhost -p 5432 -U postgres; do
    echo "Waiting for PostgreSQL to be ready..."
    sleep 2
done

# Create inventory user if it doesn't exist
if ! psql -h localhost -U postgres -t -c "SELECT 1 FROM pg_roles WHERE rolname='inventory'" | grep -q 1; then
    echo "Creating inventory user..."
    psql -h localhost -U postgres -c "CREATE USER inventory WITH PASSWORD 'inventory_pi_2024';"
    echo "✅ Inventory user created"
else
    echo "✅ Inventory user already exists"
fi

# Create inventory database if it doesn't exist
if ! psql -h localhost -U postgres -lqt | cut -d '|' -f 1 | grep -qw "inventory_db"; then
    echo "Creating inventory database..."
    psql -h localhost -U postgres -c "CREATE DATABASE inventory_db OWNER inventory;"
    psql -h localhost -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE inventory_db TO inventory;"
    echo "✅ Inventory database created"
else
    echo "✅ Inventory database already exists"
fi

# Create vector extensions if available
echo "Creating database extensions..."
psql -h localhost -U inventory -d inventory_db -c "CREATE EXTENSION IF NOT EXISTS vector;" 2>/dev/null || echo "⚠️ Vector extension not available"
psql -h localhost -U inventory -d inventory_db -c "CREATE EXTENSION IF NOT EXISTS pg_trgm;" 2>/dev/null || echo "⚠️ pg_trgm extension not available"

echo "✅ Database initialization complete!"
