#!/bin/bash

echo "🥧 Home Inventory System - Raspberry Pi Installation"
echo "=================================================="

# Exit on any error
set -e

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "❌ Please run as root (use sudo)"
    exit 1
fi

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PI_DEPLOYMENT_DIR="$(dirname "$SCRIPT_DIR")"

echo "📁 Installation directory: $PI_DEPLOYMENT_DIR"

# Update system
echo "🔄 Updating system packages..."
apt update && apt upgrade -y

# Install dependencies
echo "📦 Installing dependencies..."
apt install -y \
    python3 \
    python3-pip \
    python3-venv \
    postgresql \
    postgresql-contrib \
    nginx \
    git \
    curl \
    wget \
    unzip \
    avahi-daemon \
    avahi-utils

# Create inventory user
echo "👤 Creating inventory user..."
if ! id "inventory" &>/dev/null; then
    useradd -r -s /bin/bash -d /var/lib/inventory -m inventory
fi

# Create application directory
echo "📂 Setting up application directories..."
mkdir -p /var/lib/inventory/{app,images,logs,backups}
chown -R inventory:inventory /var/lib/inventory

# Copy application files
echo "📋 Copying application files..."
mkdir -p /var/lib/inventory/app/src

# Copy all Flask application files
cp "$PI_DEPLOYMENT_DIR"/*.py /var/lib/inventory/app/src/
cp -r "$PI_DEPLOYMENT_DIR/routes" /var/lib/inventory/app/src/
cp -r "$PI_DEPLOYMENT_DIR/templates" /var/lib/inventory/app/src/
cp -r "$PI_DEPLOYMENT_DIR/static" /var/lib/inventory/app/src/
cp -r "$PI_DEPLOYMENT_DIR/services" /var/lib/inventory/app/src/
cp -r "$PI_DEPLOYMENT_DIR/utils" /var/lib/inventory/app/src/
[ -f "$PI_DEPLOYMENT_DIR/requirements.txt" ] && cp "$PI_DEPLOYMENT_DIR/requirements.txt" /var/lib/inventory/app/
[ -d "$PI_DEPLOYMENT_DIR/uploads" ] && cp -r "$PI_DEPLOYMENT_DIR/uploads" /var/lib/inventory/app/src/

# Copy test script for debugging
cp "$PI_DEPLOYMENT_DIR/test-startup.py" /var/lib/inventory/app/
chmod +x /var/lib/inventory/app/test-startup.py

# Copy configuration files
cp -r "$PI_DEPLOYMENT_DIR/config" /var/lib/inventory/

chown -R inventory:inventory /var/lib/inventory/app
chown -R inventory:inventory /var/lib/inventory/config

# Setup Python virtual environment
echo "🐍 Setting up Python environment..."
sudo -u inventory python3 -m venv /var/lib/inventory/app/venv
sudo -u inventory /var/lib/inventory/app/venv/bin/pip install --upgrade pip

# Install Python dependencies
echo "📚 Installing Python packages..."

# First install basic requirements
cat > /var/lib/inventory/app/requirements-basic.txt << 'EOF'
Flask==2.3.3
psycopg2-binary==2.9.7
Pillow==10.0.0
numpy==1.24.3
python-dotenv==1.0.0
Werkzeug==2.3.7
gunicorn==21.2.0
psutil==5.9.5
EOF

echo "  Installing basic packages..."
sudo -u inventory /var/lib/inventory/app/venv/bin/pip install -r /var/lib/inventory/app/requirements-basic.txt

# Try to install sentence-transformers (may fail on Pi due to torch)
echo "  Installing ML packages for semantic search..."
echo "  This may take several minutes on Raspberry Pi..."

# For ARM64/Raspberry Pi, we need specific torch version
if [ "$(uname -m)" = "aarch64" ]; then
    echo "  Detected ARM64 architecture (Raspberry Pi)"
    # Install PyTorch for ARM64 first
    sudo -u inventory /var/lib/inventory/app/venv/bin/pip install torch torchvision --index-url https://download.pytorch.org/whl/cpu 2>/dev/null || {
        echo "  ⚠️ PyTorch installation failed - semantic search will be disabled"
    }
fi

# Try to install sentence-transformers (use latest compatible version)
sudo -u inventory /var/lib/inventory/app/venv/bin/pip install 'sentence-transformers>=3.0.0' 2>/dev/null || {
    echo "  ⚠️ Sentence-transformers installation failed"
    echo "  Semantic search will fall back to traditional search"
    echo "  This is normal on Raspberry Pi with limited resources"
}

# Copy extracted images
echo "🖼️ Copying image files..."
if [ -d "$PI_DEPLOYMENT_DIR/data/images" ]; then
    cp -r "$PI_DEPLOYMENT_DIR/data/images"/* /var/lib/inventory/images/
    chown -R inventory:inventory /var/lib/inventory/images
    echo "✅ Copied $(find /var/lib/inventory/images -type f | wc -l) image files"
else
    echo "⚠️ No image files found in deployment package"
fi

# Setup PostgreSQL
echo "🗄️ Setting up PostgreSQL..."
"$SCRIPT_DIR/setup-postgres.sh"

# Generate SSL certificates BEFORE nginx setup
echo "🔐 Generating SSL certificates..."
mkdir -p /var/lib/inventory/ssl
openssl req -x509 -newkey rsa:2048 \
    -keyout /var/lib/inventory/ssl/private.key \
    -out /var/lib/inventory/ssl/cert.crt \
    -days 365 -nodes \
    -subj "/C=US/ST=Local/L=Home/O=HomeInventory/CN=$(hostname)"

cat /var/lib/inventory/ssl/cert.crt /var/lib/inventory/ssl/private.key > /var/lib/inventory/ssl/cert.pem
chown -R inventory:inventory /var/lib/inventory/ssl
chmod 600 /var/lib/inventory/ssl/private.key

# Setup Nginx (now SSL certs exist)
echo "🌐 Setting up Nginx..."
"$SCRIPT_DIR/setup-nginx.sh"

# Setup systemd services
echo "⚙️ Setting up system services..."
"$SCRIPT_DIR/setup-services.sh"

# Setup mDNS
echo "📡 Setting up network discovery..."
systemctl enable avahi-daemon
systemctl start avahi-daemon

# Test application startup
echo "🧪 Testing application startup..."
cd /var/lib/inventory/app/src

# Load environment variables for test
export $(grep -v '^#' /var/lib/inventory/config/environment.env | xargs)

# Run the test as inventory user with environment
sudo -u inventory \
    PYTHONPATH=/var/lib/inventory/app/src \
    POSTGRES_HOST=localhost \
    POSTGRES_PORT=5432 \
    POSTGRES_USER=inventory \
    POSTGRES_PASSWORD=inventory_pi_2024 \
    POSTGRES_DB=inventory_db \
    DEPLOYMENT_TYPE=raspberry_pi \
    IMAGE_FILE_PATH=/var/lib/inventory/images \
    /var/lib/inventory/app/venv/bin/python3 /var/lib/inventory/app/test-startup.py

if [ $? -ne 0 ]; then
    echo "❌ Application startup test failed. Check the output above for errors."
    echo "💡 Trying to diagnose the issue..."
    
    # Check if database is accessible
    sudo -u postgres psql -d inventory_db -c "SELECT 1;" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "   ❌ Database is not accessible"
    else
        echo "   ✅ Database is accessible"
    fi
    
    # Check if tables exist
    TABLE_COUNT=$(sudo -u postgres psql -d inventory_db -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null || echo "0")
    echo "   📊 Found $TABLE_COUNT tables in database"
    
    exit 1
fi

# Start services
echo "🚀 Starting services..."
systemctl daemon-reload
systemctl enable inventory-app
systemctl enable nginx
systemctl start inventory-app
systemctl start nginx

# Final status check
echo ""
echo "✅ Installation complete!"
echo ""
echo "🌐 Access your inventory system:"
echo "   Local: https://$(hostname).local"
echo "   IP: https://$(hostname -I | awk '{print $1}')"
echo ""
echo "📊 Service status:"
systemctl is-active inventory-app && echo "   ✅ Inventory app: Running" || echo "   ❌ Inventory app: Failed"
systemctl is-active nginx && echo "   ✅ Nginx: Running" || echo "   ❌ Nginx: Failed"
systemctl is-active postgresql && echo "   ✅ PostgreSQL: Running" || echo "   ❌ PostgreSQL: Failed"
echo ""
echo "📝 Logs:"
echo "   Application: journalctl -u inventory-app -f"
echo "   Nginx: tail -f /var/log/nginx/error.log"
echo "   PostgreSQL: tail -f /var/log/postgresql/postgresql-*.log"