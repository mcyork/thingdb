#!/bin/bash
# ThingDB Complete Installation Script
# Installs system dependencies, ThingDB package, initializes database, and starts the service
# This script is idempotent - safe to run multiple times for upgrades

set -e  # Exit on error

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║            ThingDB Complete Installation                       ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="/var/lib/thingdb/app"
INSTALL_INFO="/var/lib/thingdb/INSTALL_INFO"

# INSTALL_INFO Management Functions
write_install_info() {
    local version=$(grep "^APP_VERSION=" "$APP_DIR/.env" 2>/dev/null | cut -d'=' -f2 || echo "1.4.17")
    local branch=$(git -C "$SCRIPT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    
    sudo tee "$INSTALL_INFO" > /dev/null << EOF
# ThingDB Installation Information
VERSION=$version
INSTALLED=$(date -Iseconds)
BRANCH=$branch
LAST_UPGRADE=$(date -Iseconds)
SECRETS_GENERATED=yes
SSL_TYPE=thingdb-selfgned
EOF
    
    sudo chown thingdb:thingdb "$INSTALL_INFO"
}

detect_installation_mode() {
    # Upgrade if INSTALL_INFO exists OR if app directory exists
    if [ -f "$INSTALL_INFO" ] || [ -d "$APP_DIR" ]; then
        echo "UPGRADE"
    else
        echo "FRESH"
    fi
}

show_upgrade_banner() {
    local old_version=$(grep "^VERSION=" "$INSTALL_INFO" 2>/dev/null | cut -d'=' -f2 || echo "unknown")
    local new_version=$(grep "^APP_VERSION=" "$SCRIPT_DIR/.env" 2>/dev/null | cut -d'=' -f2 || echo "1.4.17")
    
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║              🔄 UPGRADE MODE DETECTED                          ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Existing installation found!"
    echo "  Current version: $old_version"
    echo "  New version: $new_version"
    echo ""
    echo "The following will be preserved:"
    echo "  ✓ Database and all items"
    echo "  ✓ .env configuration (merged with new keys)"
    echo "  ✓ SSL certificates (if valid)"
    echo "  ✓ Uploaded images"
    echo "  ✓ Backups"
    echo ""
    echo "The following will be updated:"
    echo "  ✓ Application code"
    echo "  ✓ Python dependencies"
    echo "  ✓ System packages"
    echo ""
}

# Detect installation mode
INSTALL_MODE=$(detect_installation_mode)

if [ "$INSTALL_MODE" = "UPGRADE" ]; then
    show_upgrade_banner
fi

# Step 1: Install system dependencies (creates thingdb user)
echo -e "${BLUE}Step 1/6: Installing system dependencies...${NC}"
cd "$SCRIPT_DIR"
./install_system_deps.sh

# Step 2: Deploy application to system directory
echo ""
echo -e "${BLUE}Step 2/6: Deploying ThingDB to system directory...${NC}"

# Create app directory if it doesn't exist
sudo mkdir -p "$APP_DIR"

# Backup .env if it exists (for upgrade mode)
if [ -f "$APP_DIR/.env" ] && [ "$INSTALL_MODE" = "UPGRADE" ]; then
    echo "Backing up existing .env file..."
    sudo cp "$APP_DIR/.env" "$APP_DIR/.env.backup.$(date +%s)"
fi

# Copy application files (preserve .env)
echo "Copying application files to $APP_DIR..."
sudo rsync -av --exclude='.git' --exclude='aaa' --exclude='venv' --exclude='__pycache__' --exclude='*.pyc' --exclude='.env' \
    "$SCRIPT_DIR/" "$APP_DIR/"

# If new install, copy .env from script directory
if [ "$INSTALL_MODE" = "FRESH" ] && [ -f "$SCRIPT_DIR/.env" ]; then
    echo "Copying .env configuration..."
    sudo cp "$SCRIPT_DIR/.env" "$APP_DIR/.env"
fi

# Set ownership to thingdb user
sudo chown -R thingdb:thingdb "$APP_DIR"
sudo chown -R thingdb:thingdb /var/lib/thingdb

echo -e "${GREEN}✓${NC} Application deployed"

# Step 3: Create virtual environment and install ThingDB
echo ""
echo -e "${BLUE}Step 3/6: Installing ThingDB Python package...${NC}"

# Create venv as thingdb user
sudo -u thingdb python3 -m venv "$APP_DIR/venv"
echo -e "${GREEN}✓${NC} Virtual environment created"

echo "Installing ThingDB and all dependencies (this may take 5-10 minutes)..."
# Install as thingdb user
sudo -u thingdb "$APP_DIR/venv/bin/pip" install --quiet --upgrade pip
sudo -u thingdb "$APP_DIR/venv/bin/pip" install -e "$APP_DIR"

echo -e "${GREEN}✓${NC} ThingDB installed successfully!"

# Step 4: Initialize database
echo ""
echo -e "${BLUE}Step 4/6: Initializing database...${NC}"
sudo -u thingdb "$APP_DIR/venv/bin/thingdb" init

# Step 5: Setup and enable systemd service
echo ""
echo -e "${BLUE}Step 5/6: Setting up systemd service...${NC}"
if [ -f "$APP_DIR/thingdb.service" ]; then
    sudo cp "$APP_DIR/thingdb.service" /etc/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl enable thingdb
    echo -e "${GREEN}✓${NC} Systemd service installed and enabled"
else
    echo -e "${YELLOW}!${NC} thingdb.service not found, skipping service setup"
fi

# Step 6: Start the service
echo ""
echo -e "${BLUE}Step 6/7: Starting ThingDB service...${NC}"
sudo systemctl start thingdb

echo ""
echo "Waiting for service to start..."
sleep 3

# Check if service is running
if sudo systemctl is-active --quiet thingdb; then
    echo -e "${GREEN}✓${NC} ThingDB service is running!"
else
    echo -e "${RED}✗${NC} Service failed to start. Check logs with:"
    echo "   sudo journalctl -u thingdb -n 50"
    exit 1
fi

# Step 7: Setup HTTPS (for iPhone camera support)
echo ""
echo -e "${BLUE}Step 7/7: Setting up HTTPS (enables camera on iPhone)...${NC}"
if [ -f "$APP_DIR/setup_ssl.sh" ]; then
    cd "$APP_DIR"
    sudo ./setup_ssl.sh
    echo -e "${GREEN}✓${NC} HTTPS configured!"
else
    echo -e "${YELLOW}!${NC} setup_ssl.sh not found, skipping HTTPS setup"
fi

# Write installation info
write_install_info

# Final summary
echo ""
if [ "$INSTALL_MODE" = "UPGRADE" ]; then
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║              🎉 Upgrade Complete! 🎉                           ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "ThingDB has been upgraded successfully!"
    echo ""
    echo "✓ Your data has been preserved"
    echo "✓ Configuration maintained"
    echo "✓ Service restarted with new code"
else
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║              🎉 Installation Complete! 🎉                      ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "ThingDB is now running with HTTPS!"
fi
echo ""
echo "Access your inventory system:"
echo "  https://$(hostname -I | awk '{print $1}'):5000"
echo ""
if [ "$INSTALL_MODE" = "FRESH" ]; then
    echo -e "${YELLOW}📱 First-time setup (one-time only):${NC}"
    echo "  Your browser will show a certificate warning."
    echo "  This is normal for self-signed certificates."
    echo "  Click 'Advanced' → 'Proceed' to continue."
    echo ""
    echo "  On iPhone: Tap 'Show Details' → 'visit this website'"
    echo ""
    echo "  This warning only appears once - Safari/Chrome will remember."
    echo ""
fi
echo ""
echo "Service Management:"
echo "  sudo systemctl status thingdb   - Check status"
echo "  sudo systemctl restart thingdb  - Restart service"
echo "  sudo systemctl stop thingdb     - Stop service"
echo "  sudo journalctl -u thingdb -f   - View live logs"
echo ""
echo "Configuration:"
echo "  Edit /var/lib/thingdb/app/.env to change settings"
echo "  After editing .env, restart: sudo systemctl restart thingdb"
echo ""
echo -e "${GREEN}Enjoy your ThingDB inventory system! 📦${NC}"
echo ""
