#!/bin/bash
# on-pi-deploy.sh
# Automated deployment script for Raspberry Pi. This script is executed on the Pi.
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

# --- Start of Deployment Logic ---

print_status "Installing system dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt update -qq
apt install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
    python3 python3-pip python3-venv postgresql postgresql-contrib nginx git curl wget \
    cloud-guest-utils python3-dev libpq-dev python3-psycopg2

print_status "Creating inventory user..."
if ! id -u "inventory" &>/dev/null; then
    useradd -r -s /bin/false inventory
    print_success "User 'inventory' created."
else
    print_success "User 'inventory' already exists."
fi

print_status "Configuring sudo permissions for inventory user..."
cat > /etc/sudoers.d/010_inventory << 'SUDOERSEOF'
inventory ALL=(ALL) NOPASSWD: /sbin/shutdown, /sbin/reboot, /usr/bin/systemctl restart inventory-app, /bin/sync
SUDOERSEOF
chmod 440 /etc/sudoers.d/010_inventory
print_success "Sudo permissions configured for inventory user."

print_status "Setting up application directories..."
rm -rf /var/lib/inventory/app
mkdir -p /var/lib/inventory/app
mkdir -p /var/lib/inventory/images
mkdir -p /var/lib/inventory/ml_cache
mkdir -p /home/inventory

print_status "Moving application source..."
mv src /var/lib/inventory/app
mv requirements /var/lib/inventory/app/

print_status "Setting up Python virtual environment..."
cd /var/lib/inventory/app
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements/base-requirements.txt
pip install gunicorn psutil

print_status "Installing ML packages for semantic search..."
if [ "$(uname -m)" = "aarch64" ]; then
    pip install torch torchvision --index-url https://download.pytorch.org/whl/cpu || print_warning "PyTorch installation failed."
    pip install 'sentence-transformers>=3.0.0' || print_warning "Sentence-transformers installation failed."
else
    pip install -r requirements/ml-requirements.txt || print_warning "ML requirements installation failed."
fi

print_status "Setting up PostgreSQL..."
if ! sudo -u postgres psql -t -c "SELECT 1 FROM pg_roles WHERE rolname='inventory'" | grep -q 1; then
    sudo -u postgres psql -c "CREATE USER inventory WITH PASSWORD 'inventory_pi_2024';"
fi
if ! sudo -u postgres psql -lqt | cut -d '|' -f 1 | grep -qw "inventory_db"; then
    sudo -u postgres psql -c "CREATE DATABASE inventory_db OWNER inventory;"
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE inventory_db TO inventory;"
fi
sudo -u postgres psql -d inventory_db -c "CREATE EXTENSION IF NOT EXISTS vector;"
sudo -u postgres psql -d inventory_db -c "CREATE EXTENSION IF NOT EXISTS pg_trgm;"

print_status "Copying configuration files from package..."
mkdir -p /var/lib/inventory/config
cp ./config/environment.env /var/lib/inventory/config/environment.env
cp ./config/inventory-app.service /etc/systemd/system/inventory-app.service
cp ./config/nginx.conf /etc/nginx/sites-available/inventory

print_status "Creating Nginx service override to wait for network..."
mkdir -p /etc/systemd/system/nginx.service.d
cat > /etc/systemd/system/nginx.service.d/wait-for-network.conf << 'NGINXOVREOF'
[Unit]
After=network-online.target
Wants=network-online.target
NGINXOVREOF

print_status "Generating SSL certificates..."
mkdir -p /var/lib/inventory/ssl
openssl req -x509 -newkey rsa:4096 -keyout /var/lib/inventory/ssl/key.pem -out /var/lib/inventory/ssl/cert.pem -days 365 -nodes -subj '/CN=inventory.local' > /dev/null 2>&1
chmod 600 /var/lib/inventory/ssl/*

print_status "Setting final permissions..."
chown -R inventory:inventory /var/lib/inventory
chown inventory:inventory /home/inventory
chmod 755 /var/lib/inventory/app
chmod 644 /var/lib/inventory/config/*

print_status "Enabling Nginx site..."
ln -sf /etc/nginx/sites-available/inventory /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

print_status "Reloading systemd and starting services..."
systemctl daemon-reload
systemctl enable postgresql nginx inventory-app
systemctl restart postgresql
sleep 2
systemctl restart nginx
systemctl restart inventory-app

print_status "Waiting for services to stabilize..."
sleep 10

# Final verification
if ! systemctl is-active --quiet inventory-app; then
    print_error "Inventory app service failed to start."
    journalctl -u inventory-app -n 20 --no-pager
    exit 1
fi
if ! systemctl is-active --quiet nginx; then
    print_error "Nginx service failed to start."
    journalctl -u nginx -n 20 --no-pager
    exit 1
fi

print_success "✅ Deployment completed successfully!"
print_status "Access your inventory system at: https://$(hostname -I | awk '{print $1}')"
