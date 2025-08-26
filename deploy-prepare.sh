#!/bin/bash
# deploy-prepare.sh
# Creates a deployment package for Raspberry Pi

set -e

echo "🚀 Creating Raspberry Pi deployment package..."

# Configuration
PROJECT_ROOT="/Users/ianmccutcheon/projects/inv2-dev"
DEPLOY_DIR="$HOME/inventory-deploy-build"
PACKAGE_NAME="inventory-deploy.tar.gz"
PYBRIDGE_PATH="/Users/ianmccutcheon/projects/pi-shell/pi"

# Pi configuration
PI_HOST="192.168.43.203"  # Pi IP (will be overridden by PyBridge default)
PI_USER="pi"
PI_DEPLOY_PATH="/tmp"

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

# Function to check Pi status using PyBridge
check_pi_status() {
    if [ -f "$PYBRIDGE_PATH" ]; then
        print_status "Checking Pi status using PyBridge..."
        cd "$(dirname "$PYBRIDGE_PATH")"
        if ./pi status | grep -q ".*ONLINE"; then
            print_success "Pi is online and ready for deployment"
            return 0
        else
            print_warning "Pi appears to be offline. Check PyBridge status."
            return 1
        fi
    else
        print_warning "PyBridge not found at $PYBRIDGE_PATH"
        print_warning "Will use manual SCP/SSH instead"
        return 1
    fi
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

# Check if Docker testing environment is available
if [ ! -f "$PROJECT_ROOT/scripts/manage-docker-storage.sh" ]; then
    print_warning "Docker testing environment not found. This is recommended for testing before Pi deployment."
else
    print_status "Docker testing environment found. Testing code before deployment..."
    
    # Test our code in Docker first (following our documented workflow)
    cd "$PROJECT_ROOT"
    if ./scripts/manage-docker-storage.sh test > /tmp/docker-test.log 2>&1; then
        print_success "Docker tests passed - code is ready for Pi deployment"
    else
        print_warning "Docker tests had issues - check /tmp/docker-test.log"
        print_warning "Consider fixing issues before Pi deployment"
        read -p "Continue with Pi deployment anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_error "Deployment cancelled. Fix Docker issues first."
            exit 1
        fi
    fi
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

# If --provision flag is set, copy the pi-setup directory
if [[ "$1" == "--provision" ]]; then
    print_status "Including pi-setup for provisioning..."
    cp -r "$PROJECT_ROOT/pi-setup" ./
    print_success "pi-setup directory copied"
    cp "$PROJECT_ROOT/pi-setup/btwifiset.py" ./
    print_success "btwifiset.py copied"
fi

# Skip database export - start with empty database like Docker
print_status "Skipping database export - will start with empty database (like Docker)"

# Skip image copying - start with empty images directory like Docker
print_status "Skipping image copying - will start with empty images directory (like Docker)"
mkdir -p images
touch images/.gitkeep

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

# Note: Vector extension should be available in base PostgreSQL installation
# If not available, the extension creation will fail gracefully

# Create inventory user if it doesn't exist
if id -u "inventory" &>/dev/null; then
    print_success "User 'inventory' already exists."
else
    print_status "Creating inventory user..."
    useradd -r -s /bin/false inventory
    print_success "User 'inventory' created."
fi

# Setup application directory
print_status "Setting up application directory..."
# Cleanly replace the app directory to ensure a fresh install
rm -rf /var/lib/inventory/app
mkdir -p /var/lib/inventory

# Move the new src directory and rename it to 'app'
mv src /var/lib/inventory/app

# Move the new requirements directory inside the 'app' directory
mv requirements /var/lib/inventory/app/

chown -R pi:pi /var/lib/inventory

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

# Setup PostgreSQL
print_status "Setting up PostgreSQL database..."

# Create inventory user if it doesn't exist
print_status "Checking for inventory database user..."
if sudo -u postgres psql -t -c "SELECT 1 FROM pg_roles WHERE rolname='inventory'" | grep -q 1; then
    print_success "PostgreSQL user 'inventory' already exists."
else
    print_status "Creating PostgreSQL user 'inventory'..."
    sudo -u postgres psql -c "CREATE USER inventory WITH PASSWORD 'inventory_pi_2024';"
    print_success "User 'inventory' created."
fi

# Check if database exists
print_status "Checking for inventory_db database..."
if sudo -u postgres psql -lqt | cut -d '|' -f 1 | grep -qw "inventory_db"; then
    print_success "Database 'inventory_db' already exists."
else
    print_status "Database 'inventory_db' not found. Creating new database..."
    sudo -u postgres psql -c "CREATE DATABASE inventory_db OWNER inventory;"
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE inventory_db TO inventory;"
    print_success "Database 'inventory_db' created and privileges granted."
fi

# ALWAYS ensure database extensions exist (critical for semantic search)
print_status "Setting up database extensions for semantic search..."
sudo -u postgres psql -d inventory_db -c "CREATE EXTENSION IF NOT EXISTS vector;" || {
    print_warning "Vector extension creation failed - checking if it exists..."
    sudo -u postgres psql -d inventory_db -c "SELECT extname FROM pg_extension WHERE extname = 'vector';" || {
        print_error "Vector extension not available - semantic search will not work"
        print_status "You may need to install postgresql-vector package"
    }
}

sudo -u postgres psql -d inventory_db -c "CREATE EXTENSION IF NOT EXISTS pg_trgm;" || {
    print_warning "pg_trgm extension creation failed"
}

# Verify extensions are actually available
print_status "Verifying database extensions..."
VECTOR_EXT=$(sudo -u postgres psql -d inventory_db -t -c "SELECT extname FROM pg_extension WHERE extname = 'vector';" 2>/dev/null | tr -d ' ')
TRGM_EXT=$(sudo -u postgres psql -d inventory_db -t -c "SELECT extname FROM pg_extension WHERE extname = 'pg_trgm';" 2>/dev/null | tr -d ' ')

if [ "$VECTOR_EXT" = "vector" ]; then
    print_success "Vector extension is available for semantic search"
else
    print_error "Vector extension not available - semantic search will fail"
fi

if [ "$TRGM_EXT" = "pg_trgm" ]; then
    print_success "pg_trgm extension is available for text search"
else
    print_warning "pg_trgm extension not available - text search may be limited"
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
    client_max_body_size 25M;
    listen 80;
    server_name _;
    # Note: This will redirect to the Pi's actual IP address
    # The IP will be determined dynamically by nginx at runtime
    return 301 https://$host$request_uri;
}

server {
    client_max_body_size 25M;
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

    location /setup/ {
        alias /var/www/inventory-setup/;
        index index.html;
        try_files $uri $uri/ =404;
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

# Start PostgreSQL first (database dependency)
print_status "Starting PostgreSQL..."
systemctl enable postgresql
systemctl start postgresql
sleep 3  # Give PostgreSQL time to start

# Verify PostgreSQL is running
if ! systemctl is-active --quiet postgresql; then
    print_error "PostgreSQL failed to start"
    systemctl status postgresql
    exit 1
fi
print_success "PostgreSQL is running"

# Start Nginx
print_status "Starting Nginx..."
systemctl enable nginx
systemctl start nginx
sleep 3  # Give Nginx time to start

# Verify Nginx is running
if ! systemctl is-active --quiet nginx; then
    print_error "Nginx failed to start"
    systemctl status nginx
    exit 1
fi
print_success "Nginx service is running"

# CRITICAL: Verify Nginx is actually listening on both HTTP and HTTPS ports
print_status "Verifying Nginx port binding..."
sleep 2
if ! netstat -tlnp | grep -q ":80.*nginx" || ! netstat -tlnp | grep -q ":443.*nginx"; then
    print_warning "Nginx not listening on required ports - attempting restart..."
    systemctl restart nginx
    sleep 3
    
    # Check again after restart
    if ! netstat -tlnp | grep -q ":80.*nginx" || ! netstat -tlnp | grep -q ":443.*nginx"; then
        print_error "Nginx still not listening on required ports after restart"
        netstat -tlnp | grep -E ":(80|443)"
        systemctl status nginx --no-pager
        exit 1
    fi
    print_success "Nginx restarted and now listening on required ports"
else
    print_success "Nginx is listening on HTTP (80) and HTTPS (443)"
fi

# Start Flask application
print_status "Starting Flask application..."
systemctl enable inventory-app
systemctl start inventory-app

# Wait for service to stabilize with retry logic
print_status "Waiting for Flask application to stabilize..."
MAX_RETRIES=10
RETRY_COUNT=0
SERVICE_STABLE=false

while [ $RETRY_COUNT -lt $MAX_RETRIES ] && [ "$SERVICE_STABLE" = false ]; do
    sleep 3
    RETRY_COUNT=$((RETRY_COUNT + 1))
    
    if systemctl is-active --quiet inventory-app; then
        # Service is running, now check if it's actually responding
        if curl -s -f --max-time 5 http://127.0.0.1:8000/ > /dev/null 2>&1; then
            SERVICE_STABLE=true
            print_success "Flask application is running and responding (attempt $RETRY_COUNT)"
        else
            print_status "Service running but not responding yet, waiting... (attempt $RETRY_COUNT/$MAX_RETRIES)"
        fi
    else
        print_status "Service not yet active, waiting... (attempt $RETRY_COUNT/$MAX_RETRIES)"
    fi
done

# Final verification
if [ "$SERVICE_STABLE" = true ]; then
    print_success "Flask application is running and stable"
else
    print_error "Flask application failed to stabilize after $MAX_RETRIES attempts"
    print_status "Checking service status and logs..."
    systemctl status inventory-app --no-pager
    journalctl -u inventory-app -n 20 --no-pager
    exit 1
fi

# CRITICAL: Force download of sentence-transformers model to correct cache directory
print_status "Pre-downloading ML model for semantic search..."
sleep 5  # Give the app time to start

MAX_RETRIES=3
RETRY_COUNT=0
DOWNLOAD_SUCCESS=false
cd /var/lib/inventory/app

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    RETRY_COUNT=$((RETRY_COUNT+1))
    print_status "Attempting to download ML model (Attempt $RETRY_COUNT/$MAX_RETRIES)..."

    if sudo -u inventory ./venv/bin/python3 << 'PYTHONEOF'
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
    sys.exit(0)
    
except Exception as e:
    print(f"Error downloading model: {e}")
    sys.exit(1)
PYTHONEOF
    then
        DOWNLOAD_SUCCESS=true
        break
    fi

    if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
        print_warning "ML model download failed. Retrying in 10 seconds..."
        sleep 10
    fi
done

if [ "$DOWNLOAD_SUCCESS" = "true" ]; then
    print_success "ML model downloaded successfully to correct cache directory"
    print_status "Skipping re-indexing - database is empty, no items to index"
else
    print_error "ML model download failed after $MAX_RETRIES attempts. Semantic search may not work properly."
fi

# Verify installation
print_status "Verifying installation..."
if systemctl is-active --quiet inventory-app; then
    print_success "Inventory app service is running"
else
    print_error "Inventory app service failed to start"
    systemctl status inventory-app --no-pager
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

# Test Flask app directly
if curl -s -f http://127.0.0.1:8000/ > /dev/null; then
    print_success "Flask app is responding directly on port 8000"
else
    print_warning "Flask app not responding on port 8000 - checking logs..."
    journalctl -u inventory-app -n 10 --no-pager
fi

# Test Flask app through Nginx (HTTP redirect)
if curl -s -f http://localhost/ > /dev/null; then
    print_success "Flask app is accessible through Nginx HTTP (with redirect)"
else
    print_warning "Flask app not accessible through Nginx HTTP - checking nginx config..."
    nginx -t
    journalctl -u nginx -n 10 --no-pager
fi

# Test HTTPS connectivity and functionality
print_status "Testing HTTPS connectivity..."
if timeout 10 curl -s -k -f https://localhost/ > /dev/null; then
    print_success "HTTPS interface is working through nginx"
else
    print_warning "HTTPS interface not working - attempting to fix..."
    
    # Check if it's a port binding issue
    if ! netstat -tlnp | grep -q ":443.*nginx"; then
        print_status "Nginx not listening on 443 - restarting nginx..."
        systemctl restart nginx
        sleep 3
        
        # Test HTTPS again after restart
        if timeout 10 curl -s -k -f https://localhost/ > /dev/null; then
            print_success "HTTPS working after nginx restart"
        else
            print_error "HTTPS still not working after nginx restart"
            print_status "Checking nginx configuration and logs..."
            nginx -t
            journalctl -u nginx -n 15 --no-pager
            netstat -tlnp | grep -E ":(80|443)"
            exit 1
        fi
    else
        print_error "Nginx listening on 443 but HTTPS not working - configuration issue"
        nginx -t
        journalctl -u nginx -n 15 --no-pager
        exit 1
    fi
fi

# Final comprehensive test: verify the system is accessible from network perspective
print_status "Performing final network accessibility test..."
PI_IP=$(hostname -I | awk '{print $1}')
if timeout 15 curl -s -k -f "https://$PI_IP/" > /dev/null; then
    print_success "✅ System is fully accessible via HTTPS from network: https://$PI_IP"
else
    print_error "❌ System not accessible via HTTPS from network - deployment incomplete"
    print_status "Local HTTPS test passed but network test failed - checking firewall/network config..."
    exit 1
fi

# Skip semantic search testing for now - database is empty, no items to search
print_status "Skipping semantic search testing - database is empty, no items to search"
print_success "Semantic search API will be available when items are added"

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

# Add pi-setup to tar if it exists
TAR_EXTRAS=""
if [ -d "pi-setup" ]; then
    TAR_EXTRAS="pi-setup"
fi

# Create the package with all the files we need
tar -czf "$PACKAGE_NAME" src requirements images deploy.sh README.md $TAR_EXTRAS btwifiset.py

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

# Check Pi status for informational purposes
if check_pi_status; then
    print_status "Pi is online and ready for deployment"
    print_status "Use ./scripts/deploy-remote.sh to deploy automatically"
else
    print_status "Pi appears to be offline or PyBridge unavailable"
    print_status "Use manual deployment instructions below"
fi
echo "🚀 Next Steps:"
echo "   1. Deploy automatically: ./scripts/deploy-remote.sh"
echo "   2. Or deploy manually:"
echo "      - Transfer: scp $PACKAGE_PATH $PI_USER@$PI_HOST:/tmp/"
echo "      - SSH: ssh $PI_USER@$PI_HOST"
echo "      - Deploy: cd /tmp && tar -xzf $PACKAGE_NAME && sudo ./deploy.sh"
echo ""
echo "📋 Alternative transfer methods:"
echo "   - Automatic: ./scripts/deploy-remote.sh (recommended)"
echo "   - Manual rsync: rsync -avz $PACKAGE_PATH $PI_USER@$PI_HOST:/tmp/"
echo "   - USB drive: Copy $PACKAGE_PATH to USB and transfer manually"
echo ""
echo "🔧 Improved Workflow (Following Our Strategy):"
echo "   1. Test in Docker: ./scripts/manage-docker-storage.sh test"
echo "   2. Create deployment package: ./deploy-prepare.sh"
echo "   3. Deploy automatically: ./scripts/deploy-remote.sh"
echo "   4. Verify functionality on Pi"
echo ""

# Clean up deployment directory (keep the package)
print_status "Cleaning up temporary files..."
rm -rf "$DEPLOY_DIR"/src "$DEPLOY_DIR"/requirements "$DEPLOY_DIR"/images "$DEPLOY_DIR"/deploy.sh "$DEPLOY_DIR"/README.md 2>/dev/null || true

print_success "Deployment preparation complete!"
