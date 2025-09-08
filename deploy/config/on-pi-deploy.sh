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
# Move all extracted files and directories to app directory
mv * /var/lib/inventory/app/ 2>/dev/null || true

# Clean environment function
clean_pip_environment() {
    print_status "Cleaning Python environment..."
    
    # Remove all pip caches
    find /root -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
    find /home -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
    find /var/lib -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
    
    # Clear pip caches
    rm -rf /root/.cache/pip
    rm -rf /home/*/.cache/pip
    
    # Remove old wheel files
    find /tmp -name "*.whl" -delete 2>/dev/null || true
}

# Call it before setting up Python
clean_pip_environment

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
# Vector extensions are included by default in modern PostgreSQL
# sudo -u postgres psql -d inventory_db -c "CREATE EXTENSION IF NOT EXISTS vector;"
# sudo -u postgres psql -d inventory_db -c "CREATE EXTENSION IF NOT EXISTS pg_trgm;"

print_status "Copying configuration files from package..."
mkdir -p /var/lib/inventory/config
mkdir -p /var/lib/inventory/signing-certs-and-root
cp ./config/environment.env /var/lib/inventory/config/environment.env
cp ./config/inventory-app.service /etc/systemd/system/inventory-app.service
cp ./config/nginx.conf /etc/nginx/sites-available/inventory
cp ./config/cloudflared.service /etc/systemd/system/cloudflared.service

print_status "Creating cloudflared config directory with inventory ownership..."
mkdir -p /etc/cloudflared
chown inventory:inventory /etc/cloudflared

print_status "Creating initial cloudflared config file with inventory ownership..."
cat > /etc/cloudflared/config.yml << 'CLOUDFLAREDEOF'
tunnel: dummy
credentials-file: /dev/null
ingress:
  - service: http_status:404
CLOUDFLAREDEOF
chown inventory:inventory /etc/cloudflared/config.yml
chmod 644 /etc/cloudflared/config.yml

print_status "Granting inventory user permission to manage cloudflared service..."
echo "inventory ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart cloudflared.service, /usr/bin/systemctl enable cloudflared.service, /usr/bin/systemctl daemon-reload" > /etc/sudoers.d/inventory-cloudflared
chmod 0440 /etc/sudoers.d/inventory-cloudflared


print_status "Copying certificate chains for package verification..."
if [ -d "./signing-certs-and-root" ]; then
    cp ./signing-certs-and-root/*.crt /var/lib/inventory/signing-certs-and-root/
    print_success "Certificate chains copied for package verification"
else
    print_warning "No signing-certs-and-root directory found - package verification will be disabled"
fi

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

# Comprehensive verification tests
print_status "Performing comprehensive system verification..."

# Verify services are running
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

if systemctl is-active --quiet postgresql; then
    print_success "PostgreSQL service is running"
else
    print_error "PostgreSQL service failed to start"
    systemctl status postgresql
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

# Final comprehensive verification
print_status "Performing final system verification..."
echo ""
echo "🔍 System Status Check:"
echo "   • Inventory App Service: $(systemctl is-active inventory-app 2>/dev/null || echo 'FAILED')"
echo "   • Nginx Service: $(systemctl is-active nginx 2>/dev/null || echo 'FAILED')"
echo "   • PostgreSQL Service: $(systemctl is-active postgresql 2>/dev/null || echo 'FAILED')"
echo "   • ML Cache Directory: $(ls -A /var/lib/inventory/ml_cache >/dev/null 2>&1 && echo 'READY' || echo 'EMPTY')"
echo "   • Database Connection: $(timeout 5 sudo -u inventory psql -h localhost -U inventory -d inventory_db -c 'SELECT 1;' >/dev/null 2>&1 && echo 'OK' || echo 'FAILED')"
echo "   • Port 80 (HTTP): $(netstat -tlnp | grep -q ':80.*nginx' && echo 'LISTENING' || echo 'NOT LISTENING')"
echo "   • Port 443 (HTTPS): $(netstat -tlnp | grep -q ':443.*nginx' && echo 'LISTENING' || echo 'NOT LISTENING')"
echo "   • Port 8000 (Flask): $(netstat -tlnp | grep -q ':8000.*gunicorn' && echo 'LISTENING' || echo 'NOT LISTENING')"
echo ""

# Check if all critical services are running
CRITICAL_SERVICES_OK=true
if ! systemctl is-active --quiet inventory-app; then
    CRITICAL_SERVICES_OK=false
fi
if ! systemctl is-active --quiet nginx; then
    CRITICAL_SERVICES_OK=false
fi
if ! systemctl is-active --quiet postgresql; then
    CRITICAL_SERVICES_OK=false
fi

if [ "$CRITICAL_SERVICES_OK" = true ]; then
    print_success "✅ All critical services are running properly!"
else
    print_warning "⚠️  Some services may not be running optimally. Check the status above."
fi

print_success "✅ Deployment completed successfully!"
print_status "Access your inventory system at: https://$(hostname -I | awk '{print $1}')"
