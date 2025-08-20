#!/bin/bash
# deploy-prepare.sh
# Creates a deployment package for Raspberry Pi

set -e

echo "🚀 Creating Raspberry Pi deployment package..."

# Configuration
PROJECT_ROOT="/Users/ianmccutcheon/projects/inv2-dev"
DEPLOY_DIR="$HOME/inventory-deploy-build"
PACKAGE_NAME="inventory-deploy.tar.gz"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if project directory exists
if [ ! -d "$PROJECT_ROOT" ]; then
    print_error "Project directory not found: $PROJECT_ROOT"
    exit 1
fi

# Create deployment directory
print_status "Creating deployment directory..."
rm -rf "$DEPLOY_DIR"
mkdir -p "$DEPLOY_DIR"
cd "$DEPLOY_DIR"

# Copy application source code
print_status "Copying application source code..."
cp -r "$PROJECT_ROOT/src" ./
print_success "Source code copied"

# Copy Python requirements
print_status "Copying Python requirements..."
cp -r "$PROJECT_ROOT/requirements" .
print_success "Requirements copied"

# Ensure requirements directory is included even if empty
if [ ! -f "requirements/.gitkeep" ]; then
    touch requirements/.gitkeep
fi

# Copy database export
print_status "Copying database export..."
if [ -f "$PROJECT_ROOT/pi-deployment/data/database-export.sql" ]; then
    cp "$PROJECT_ROOT/pi-deployment/data/database-export.sql" ./
    DB_SIZE=$(du -h database-export.sql | cut -f1)
    print_success "Database export copied ($DB_SIZE)"
else
    print_warning "Database export not found, skipping..."
fi

# Copy images
if [ -d "$PROJECT_ROOT/pi-deployment/data/images" ]; then
    print_status "Copying image files..."
    cp -r "$PROJECT_ROOT/pi-deployment/data/images" .
    IMAGE_COUNT=$(find images -type f | wc -l)
    IMAGE_SIZE=$(du -sh images | cut -f1)
    print_success "Images copied ($(printf "%7d" $IMAGE_COUNT) files, $IMAGE_SIZE)"
    
    # Ensure empty directories are included by adding .gitkeep files
    find images -type d -empty -exec touch {}/.gitkeep \;
else
    print_warning "Images directory not found, skipping..."
    # Create empty images directory with placeholder
    mkdir -p images
    touch images/.gitkeep
fi

# Create deployment script
print_status "Creating deployment script..."
cat > deploy.sh << 'EOF'
#!/bin/bash
# Automated deployment script for Raspberry Pi
set -e

echo "🚀 Starting inventory system deployment..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run as root or with sudo"
    exit 1
fi

# Update system packages
print_status "Updating system packages..."
export DEBIAN_FRONTEND=noninteractive
apt update
apt upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"

# Install system dependencies
print_status "Installing system dependencies..."
apt install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" python3 python3-pip python3-venv postgresql postgresql-contrib nginx git curl wget

# Install additional Python packages
print_status "Installing Python development packages..."
apt install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" python3-dev libpq-dev python3-psycopg2

# Create application directory
print_status "Creating application directory..."
mkdir -p /var/lib/inventory
chown pi:pi /var/lib/inventory

# Move application files
print_status "Setting up application files..."
mv src /var/lib/inventory/app/
mv requirements /var/lib/inventory/app/

# Create inventory user
print_status "Creating inventory user..."
useradd -r -s /bin/false inventory || true

# Create proper home directory for inventory user (needed for ML model caching)
print_status "Setting up inventory user home directory..."
mkdir -p /home/inventory
chown inventory:inventory /home/inventory
chmod 755 /home/inventory

# Create ML cache directory for sentence-transformers and other ML models
print_status "Setting up ML cache directory..."
mkdir -p /var/lib/inventory/ml_cache
chown inventory:inventory /var/lib/inventory/ml_cache
chmod 755 /var/lib/inventory/ml_cache

# Clear any old cache directories that might interfere
print_status "Clearing old ML cache directories..."
rm -rf /home/inventory/.cache/huggingface 2>/dev/null || true
rm -rf /home/inventory/.cache/torch 2>/dev/null || true
rm -rf /root/.cache/huggingface 2>/dev/null || true
rm -rf /root/.cache/torch 2>/dev/null || true

# Setup Python virtual environment
print_status "Setting up Python environment..."
cd /var/lib/inventory/app
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements/base-requirements.txt

# Install ML packages with proper ARM64 support
print_status "Installing ML packages for semantic search..."
if [ "$(uname -m)" = "aarch64" ]; then
    print_status "Detected ARM64 architecture (Raspberry Pi)"
    # Install PyTorch for ARM64 first (without version pinning for compatibility)
    pip install torch torchvision --index-url https://download.pytorch.org/whl/cpu 2>/dev/null || {
        print_warning "PyTorch installation failed - semantic search will be disabled"
    }
    
    # Try to install sentence-transformers (use latest compatible version)
    pip install 'sentence-transformers>=3.0.0' 2>/dev/null || {
        print_warning "Sentence-transformers installation failed"
        print_warning "Semantic search will fall back to traditional search"
    }
else
    print_status "Installing ML packages for x86_64..."
    pip install -r requirements/ml-requirements.txt 2>/dev/null || {
        print_warning "ML requirements installation failed - some features may be limited"
    }
fi

# Install gunicorn if not in requirements
pip install gunicorn

# Install additional required packages that might not be in requirements
print_status "Installing additional required packages..."
pip install psutil 2>/dev/null || {
    print_warning "psutil installation failed - some features may be limited"
}

# Setup PostgreSQL - ALWAYS create user and database first
print_status "Setting up PostgreSQL database..."

# Create database user and database (always do this first)
print_status "Creating PostgreSQL user and database..."
sudo -u postgres psql -c "CREATE USER inventory WITH PASSWORD 'inventory_pi_2024';" || true

# Drop and recreate database to ensure clean slate
print_status "Ensuring clean database..."
sudo -u postgres psql -c "DROP DATABASE IF EXISTS inventory_db;" || true
sudo -u postgres psql -c "CREATE DATABASE inventory_db OWNER inventory;" || true
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE inventory_db TO inventory;" || true

# Import database if available
if [ -f "/tmp/database-export.sql" ]; then
    print_status "Importing database..."
    sudo -u postgres psql -d inventory_db < /tmp/database-export.sql
    
    # CRITICAL: Fix table ownership after import
    print_status "Fixing table ownership..."
    sudo -u postgres psql -d inventory_db << 'DBEOF'
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
DBEOF
    
    print_success "Database imported and ownership fixed"
else
    print_warning "No database export found - database will be empty"
fi

# Verify and fix database ownership (critical for Flask app to work)
print_status "Verifying database ownership..."
sudo -u postgres psql -d inventory_db << 'DBOWNEOF' 2>/dev/null || true
-- Change ownership of all tables to inventory user (if they exist)
DO \$\$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname = 'public') LOOP
        EXECUTE 'ALTER TABLE ' || quote_ident(r.tablename) || ' OWNER TO inventory;';
    END LOOP;
    
    FOR r IN (SELECT sequence_name FROM information_schema.sequences WHERE sequence_schema = 'public') LOOP
        EXECUTE 'ALTER SEQUENCE ' || quote_ident(r.sequence_name) || ' OWNER TO inventory;';
    END LOOP;
    
    -- Grant all privileges
    GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO inventory;
    GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO inventory;
    GRANT ALL PRIVILEGES ON SCHEMA public TO inventory;
END \$\$;
DBOWNEOF

print_success "Database ownership verified and fixed"

# Additional database setup for semantic search
print_status "Setting up database for semantic search..."
sudo -u postgres psql -d inventory_db << 'SEMANTICEOF' 2>/dev/null || true
-- Ensure the database has the necessary extensions for semantic search
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Verify extensions are installed
SELECT extname FROM pg_extension WHERE extname IN ('vector', 'pg_trgm');
SEMANTICEOF

# Verify extensions were created
print_status "Verifying database extensions..."
if sudo -u postgres psql -d inventory_db -t -c "SELECT extname FROM pg_extension WHERE extname IN ('vector', 'pg_trgm');" | grep -q "vector\|pg_trgm"; then
    print_success "Database extensions for semantic search are installed"
else
    print_warning "Database extensions may not be properly installed"
fi

# Setup images directory
if [ -d "images" ]; then
    print_status "Setting up images directory..."
    mkdir -p /var/lib/inventory/images
    mv images/* /var/lib/inventory/images/ 2>/dev/null || true
    chown -R inventory:inventory /var/lib/inventory/images
    print_success "Images directory configured"
fi

# Create configuration directory
print_status "Creating configuration files..."
mkdir -p /var/lib/inventory/config

# Create environment file
cat > /var/lib/inventory/config/environment.env << 'ENVEOF'
DEPLOYMENT_TYPE=raspberry_pi
SERVE_IMAGES_FROM_FILES=true
IMAGE_STORAGE_METHOD=filesystem
IMAGE_DIR=/var/lib/inventory/images
POSTGRES_HOST=localhost
POSTGRES_PORT=5432
POSTGRES_USER=inventory
POSTGRES_PASSWORD=inventory_pi_2024
POSTGRES_DB=inventory_db
FLASK_ENV=production
SECRET_KEY=inventory_pi_secret_key_change_in_production

# ML Model Cache Directories (critical for sentence-transformers)
TRANSFORMERS_CACHE=/var/lib/inventory/ml_cache
HF_HOME=/var/lib/inventory/ml_cache
ENVEOF

# Create systemd service
print_status "Creating systemd service..."
cat > /etc/systemd/system/inventory-app.service << 'SVCEOF'
[Unit]
Description=Inventory Management System
After=network.target postgresql.service

[Service]
Type=simple
User=inventory
Group=inventory
WorkingDirectory=/var/lib/inventory/app
Environment=PATH=/var/lib/inventory/app/venv/bin
Environment=TRANSFORMERS_CACHE=/var/lib/inventory/ml_cache
Environment=HF_HOME=/var/lib/inventory/ml_cache
EnvironmentFile=/var/lib/inventory/config/environment.env
ExecStart=/var/lib/inventory/app/venv/bin/gunicorn --workers 2 --bind 127.0.0.1:8000 main:app
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
SVCEOF

# Create nginx configuration
print_status "Configuring nginx..."
cat > /etc/nginx/sites-available/inventory << 'NGINXEOF'
server {
    listen 80;
    server_name _;
    # Note: This will redirect to the Pi's actual IP address
    # The IP will be determined dynamically by nginx at runtime
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name _;
    
    ssl_certificate /var/lib/inventory/ssl/cert.pem;
    ssl_certificate_key /var/lib/inventory/ssl/key.pem;
    
    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    
    location /images/ {
        alias /var/lib/inventory/images/;
        expires 30d;
        add_header Cache-Control "public, immutable";
    }
}
NGINXEOF

# Generate SSL certificates
print_status "Generating SSL certificates..."
mkdir -p /var/lib/inventory/ssl
cd /var/lib/inventory/ssl
openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -days 365 -nodes -subj '/CN=inventory.local' > /dev/null 2>&1
chmod 600 /var/lib/inventory/ssl/*

# Set proper permissions
print_status "Setting file permissions..."
chown -R inventory:inventory /var/lib/inventory
chmod 755 /var/lib/inventory/app
chmod 644 /var/lib/inventory/config/*

# Enable nginx site
print_status "Enabling nginx site..."
ln -sf /etc/nginx/sites-available/inventory /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Reload systemd and start services
print_status "Starting services..."
systemctl daemon-reload
systemctl enable inventory-app
systemctl start inventory-app
systemctl reload nginx

# CRITICAL: Force download of sentence-transformers model to correct cache directory
print_status "Pre-downloading ML model for semantic search..."
sleep 5  # Give the app time to start
cd /var/lib/inventory/app
sudo -u inventory ./venv/bin/python3 << 'PYTHONEOF'
import os
import sys

# Set environment variables for model caching
os.environ['TRANSFORMERS_CACHE'] = '/var/lib/inventory/ml_cache'
os.environ['HF_HOME'] = '/var/lib/inventory/ml_cache'

try:
    print("Downloading sentence-transformers model...")
    from sentence_transformers import SentenceTransformer
    
    # Force download to correct cache directory
    model = SentenceTransformer('all-MiniLM-L6-v2')
    print("Model downloaded successfully!")
    
    # Test embedding generation
    test_embedding = model.encode("test text")
    print(f"Test embedding generated: {len(test_embedding)} dimensions")
    
except Exception as e:
    print(f"Error downloading model: {e}")
    sys.exit(1)
PYTHONEOF

if [ $? -eq 0 ]; then
    print_success "ML model downloaded successfully to correct cache directory"
    
    # Trigger re-index to generate embeddings for all items
    print_status "Generating embeddings for all items..."
    sleep 3  # Give the app time to stabilize
    if timeout 30 curl -s -X POST "http://127.0.0.1:8000/api/reindex-embeddings" > /dev/null; then
        print_success "Embeddings generated for all items"
    else
        print_warning "Failed to generate embeddings - semantic search may be limited"
    fi
else
    print_warning "ML model download failed - semantic search may not work properly"
fi

# Verify installation
print_status "Verifying installation..."
if systemctl is-active --quiet inventory-app; then
    print_success "Inventory app service is running"
else
    print_error "Inventory app service failed to start"
    systemctl status inventory-app
    exit 1
fi

if systemctl is-active --quiet nginx; then
    print_success "Nginx service is running"
else
    print_error "Nginx service failed to start"
    systemctl status nginx
    exit 1
fi

# Test web interface accessibility
print_status "Testing web interface..."
sleep 5  # Give the app time to fully start
if curl -s -f http://127.0.0.1:8000/ > /dev/null; then
    print_success "Flask app is responding on port 8000"
else
    print_warning "Flask app not responding on port 8000 - checking logs..."
    journalctl -u inventory-app -n 10 --no-pager
fi

if timeout 10 curl -s -k -f https://localhost/ > /dev/null; then
    print_success "HTTPS interface is working through nginx"
else
    print_warning "HTTPS interface not working - checking nginx logs..."
    journalctl -u nginx -n 10 --no-pager
fi

# Test semantic search functionality
print_status "Testing semantic search functionality..."
sleep 5  # Give the app more time to fully initialize

# Test the semantic search API directly
if curl -s -f "http://127.0.0.1:8000/api/semantic-search?q=test&limit=1" > /dev/null; then
    print_success "Semantic search API is responding"
    
    # Check if ML cache directory is being used
    if [ -d "/var/lib/inventory/ml_cache" ] && [ "$(ls -A /var/lib/inventory/ml_cache 2>/dev/null)" ]; then
        print_success "ML cache directory is being used by sentence-transformers"
        
        # Test actual semantic search functionality
        print_status "Testing semantic search with real query..."
        SEARCH_RESULT=$(timeout 10 curl -s "http://127.0.0.1:8000/api/semantic-search?q=power&limit=1")
        if echo "$SEARCH_RESULT" | grep -q "match_type.*semantic"; then
            print_success "Semantic search is working correctly!"
        else
            print_warning "Semantic search returned results but may not be using semantic matching"
        fi
    else
        print_warning "ML cache directory is empty - semantic search may not be fully functional"
    fi
else
    print_warning "Semantic search API not accessible - checking logs..."
    journalctl -u inventory-app -n 10 --no-pager
fi

print_success "Deployment completed successfully!"
print_status "Access your inventory system at: https://$(hostname -I | awk '{print $1}')"
print_status "Or use: https://raspberrypi.local (if mDNS is enabled)"

# Final comprehensive verification
print_status "Performing final system verification..."
echo ""
echo "🔍 System Status Check:"
echo "   • Inventory App Service: $(systemctl is-active inventory-app 2>/dev/null || echo 'FAILED')"
echo "   • Nginx Service: $(systemctl is-active nginx 2>/dev/null || echo 'FAILED')"
echo "   • PostgreSQL Service: $(systemctl is-active postgresql 2>/dev/null || echo 'FAILED')"
echo "   • ML Cache Directory: $(ls -A /var/lib/inventory/ml_cache >/dev/null 2>&1 && echo 'READY' || echo 'EMPTY')"
echo "   • Database Connection: $(timeout 5 sudo -u inventory psql -h localhost -U inventory -d inventory_db -c 'SELECT 1;' >/dev/null 2>&1 && echo 'OK' || echo 'FAILED')"
echo "   • Flask App Response: $(timeout 5 curl -s -f http://127.0.0.1:8000/ >/dev/null 2>&1 && echo 'OK' || echo 'FAILED')"
echo "   • HTTPS Interface: $(timeout 5 curl -s -k -f https://localhost/ >/dev/null 2>&1 && echo 'OK' || echo 'FAILED')"
echo ""

if systemctl is-active --quiet inventory-app && systemctl is-active --quiet nginx && systemctl is-active --quiet postgresql; then
    print_success "🎉 All core services are running successfully!"
    print_status "Your inventory system is ready for use!"
else
    print_warning "⚠️  Some services may not be running optimally. Check the status above."
fi

# Explicit exit to return to command line
print_success "Deployment script completed successfully!"

# Final cleanup and exit
print_status "Final cleanup..."
sync  # Ensure all data is written to disk
print_success "Deployment script completed successfully!"
exit 0
EOF

chmod +x deploy.sh

# Create README for deployment
cat > README.md << 'EOF'
# Inventory System Deployment Package

This package contains everything needed to deploy the Flask Inventory Management System to a Raspberry Pi.

## Contents
- `src/` - Application source code
- `requirements/` - Python dependencies
- `deploy.sh` - Automated deployment script
- `database-export.sql` - Database backup (if present)
- `images/` - Image files (if present)

## Deployment Instructions

1. **Transfer this package** to your Raspberry Pi
2. **Extract the package**: `tar -xzf inventory-deploy.tar.gz`
3. **Run the deployment script**: `sudo ./deploy.sh`

## What Gets Installed

- Python 3 + virtual environment
- PostgreSQL database server
- Nginx web server with SSL
- Flask application with all dependencies
- systemd service for auto-startup

## Access

After deployment, access your system at:
- **HTTPS**: https://[pi-ip-address]
- **Local**: https://localhost

## Troubleshooting

- Check service status: `sudo systemctl status inventory-app`
- View logs: `sudo journalctl -u inventory-app -f`
- Check nginx: `sudo nginx -t`
EOF

# Create final package
print_status "Creating deployment package..."

# Create the package with all the files we need
tar -czf "$PACKAGE_NAME" src requirements images database-export.sql deploy.sh README.md

# Get package information
PACKAGE_SIZE=$(du -h "$PACKAGE_NAME" | cut -f1)
PACKAGE_PATH="$DEPLOY_DIR/$PACKAGE_NAME"

print_success "Deployment package created successfully!"
echo ""
echo "📦 Package Details:"
echo "   Name: $PACKAGE_NAME"
echo "   Size: $PACKAGE_SIZE"
echo "   Location: $PACKAGE_PATH"
echo ""
echo "🚀 Next Steps:"
echo "   1. Transfer package to Pi: scp $PACKAGE_PATH pi@192.168.43.200:/tmp/"
echo "   2. SSH to Pi: ssh pi@192.168.43.200"
echo "   3. Extract and deploy: cd /tmp && tar -xzf $PACKAGE_NAME && sudo ./deploy.sh"
echo ""
echo "📋 Alternative transfer methods:"
echo "   - rsync: rsync -avz $DEPLOY_DIR/ pi@192.168.43.200:/var/lib/inventory/"
echo "   - USB drive: Copy $PACKAGE_PATH to USB and transfer manually"
echo ""

# Clean up deployment directory (keep the package)
print_status "Cleaning up temporary files..."
rm -rf "$DEPLOY_DIR"/src "$DEPLOY_DIR"/requirements "$DEPLOY_DIR"/images "$DEPLOY_DIR"/database-export.sql "$DEPLOY_DIR"/deploy.sh "$DEPLOY_DIR"/README.md 2>/dev/null || true

print_success "Deployment preparation complete!"
