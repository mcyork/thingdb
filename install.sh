#!/bin/bash
# ThingDB Complete Installation Script
# Installs system dependencies, ThingDB package, initializes database, and starts the service

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

# Step 1: Install system dependencies (creates thingdb user)
echo -e "${BLUE}Step 1/6: Installing system dependencies...${NC}"
cd "$SCRIPT_DIR"
./install_system_deps.sh

# Step 2: Deploy application to system directory
echo ""
echo -e "${BLUE}Step 2/6: Deploying ThingDB to system directory...${NC}"

# Create app directory if it doesn't exist
sudo mkdir -p "$APP_DIR"

# Copy application files
echo "Copying application files to $APP_DIR..."
sudo rsync -av --exclude='.git' --exclude='aaa' --exclude='venv' --exclude='__pycache__' --exclude='*.pyc' \
    "$SCRIPT_DIR/" "$APP_DIR/"

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

# Final summary
echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║              🎉 Installation Complete! 🎉                      ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "ThingDB is now running with HTTPS!"
echo ""
echo "Access your inventory system:"
echo "  https://$(hostname -I | awk '{print $1}'):5000"
echo ""
echo -e "${YELLOW}📱 First-time setup (one-time only):${NC}"
echo "  Your browser will show a certificate warning."
echo "  This is normal for self-signed certificates."
echo "  Click 'Advanced' → 'Proceed' to continue."
echo ""
echo "  On iPhone: Tap 'Show Details' → 'visit this website'"
echo ""
echo "  This warning only appears once - Safari/Chrome will remember."
echo ""
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
