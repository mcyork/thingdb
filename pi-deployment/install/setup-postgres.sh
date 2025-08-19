#!/bin/bash

echo "🗄️ Setting up PostgreSQL for Raspberry Pi..."

# Start PostgreSQL first
systemctl enable postgresql
systemctl start postgresql
sleep 3  # Give PostgreSQL time to start

# Create database and user (handle if already exists)
echo "📝 Creating database and user..."
sudo -u postgres psql << 'EOF' 2>/dev/null || true
CREATE USER inventory WITH PASSWORD 'inventory_pi_2024';
EOF

sudo -u postgres psql << 'EOF' 2>/dev/null || true
CREATE DATABASE inventory_db OWNER inventory;
GRANT ALL PRIVILEGES ON DATABASE inventory_db TO inventory;
EOF

# Import database if export file exists
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PI_DEPLOYMENT_DIR="$(dirname "$SCRIPT_DIR")"
DB_EXPORT="$PI_DEPLOYMENT_DIR/data/database-export.sql"

if [ -f "$DB_EXPORT" ]; then
    echo "📥 Importing database..."
    
    # First drop existing tables to avoid conflicts
    sudo -u postgres psql -d inventory_db << 'EOF' 2>/dev/null || true
DROP TABLE IF EXISTS qr_aliases CASCADE;
DROP TABLE IF EXISTS text_content CASCADE;
DROP TABLE IF EXISTS categories CASCADE;
DROP TABLE IF EXISTS images CASCADE;
DROP TABLE IF EXISTS items CASCADE;
EOF
    
    # Copy the export file to /tmp for postgres user access
    cp "$DB_EXPORT" /tmp/database-export.sql
    chown postgres:postgres /tmp/database-export.sql
    
    # Import the database
    sudo -u postgres psql -d inventory_db < /tmp/database-export.sql
    
    # CRITICAL: Fix table ownership after import
    echo "🔧 Fixing table ownership..."
    sudo -u postgres psql -d inventory_db << 'EOF'
-- Change ownership of all tables to inventory user
ALTER TABLE items OWNER TO inventory;
ALTER TABLE images OWNER TO inventory;
ALTER TABLE categories OWNER TO inventory;
ALTER TABLE qr_aliases OWNER TO inventory;
ALTER TABLE text_content OWNER TO inventory;

-- Change ownership of all sequences
ALTER SEQUENCE IF EXISTS categories_id_seq OWNER TO inventory;
ALTER SEQUENCE IF EXISTS images_id_seq OWNER TO inventory;
ALTER SEQUENCE IF EXISTS label_number_seq OWNER TO inventory;
ALTER SEQUENCE IF EXISTS text_content_id_seq OWNER TO inventory;
ALTER SEQUENCE IF EXISTS qr_aliases_id_seq OWNER TO inventory;

-- Grant all privileges to inventory user
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO inventory;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO inventory;
GRANT ALL PRIVILEGES ON SCHEMA public TO inventory;
EOF
    
    # Clean up temp file
    rm -f /tmp/database-export.sql
    
    echo "✅ Database imported and ownership fixed"
    
    # Verify the import
    ITEM_COUNT=$(sudo -u postgres psql -d inventory_db -t -c "SELECT COUNT(*) FROM items;" 2>/dev/null || echo "0")
    IMAGE_COUNT=$(sudo -u postgres psql -d inventory_db -t -c "SELECT COUNT(*) FROM images;" 2>/dev/null || echo "0")
    echo "📊 Imported: $ITEM_COUNT items, $IMAGE_COUNT images"
else
    echo "⚠️ No database export found at $DB_EXPORT"
    echo "🔧 Database will be initialized on first app run"
fi

# Optimize PostgreSQL for Pi (if config directory exists)
if [ -d "/etc/postgresql" ]; then
    PG_VERSION=$(ls /etc/postgresql/ | head -1)
    if [ -n "$PG_VERSION" ]; then
        CONFIG_DIR="/etc/postgresql/$PG_VERSION/main/conf.d"
        mkdir -p "$CONFIG_DIR"
        
        cat > "$CONFIG_DIR/99-pi-optimized.conf" << 'EOF'
# Raspberry Pi optimizations
shared_buffers = 128MB
effective_cache_size = 1GB
maintenance_work_mem = 64MB
checkpoint_completion_target = 0.9
wal_buffers = 16MB
default_statistics_target = 100
random_page_cost = 1.1
work_mem = 4MB
min_wal_size = 1GB
max_wal_size = 2GB
max_worker_processes = 2
EOF
        
        # Reload PostgreSQL to apply optimizations
        systemctl reload postgresql
        echo "✅ PostgreSQL optimized for Raspberry Pi"
    fi
fi

echo "✅ PostgreSQL setup complete"