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

# Step 1: Install system dependencies
echo -e "${BLUE}Step 1/5: Installing system dependencies...${NC}"
./install_system_deps.sh

# Step 2: Create virtual environment and install ThingDB
echo ""
echo -e "${BLUE}Step 2/5: Installing ThingDB Python package...${NC}"
if [ ! -d "venv" ]; then
    python3 -m venv venv
    echo -e "${GREEN}✓${NC} Virtual environment created"
fi

source venv/bin/activate

echo "Installing ThingDB and all dependencies (this may take 5-10 minutes)..."
pip install --quiet --upgrade pip
pip install -e .

echo -e "${GREEN}✓${NC} ThingDB installed successfully!"

# Step 3: Initialize database
echo ""
echo -e "${BLUE}Step 3/5: Initializing database...${NC}"
thingdb init

# Step 4: Setup and enable systemd service
echo ""
echo -e "${BLUE}Step 4/5: Setting up systemd service...${NC}"
if [ -f "thingdb.service" ]; then
    sudo cp thingdb.service /etc/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl enable thingdb
    echo -e "${GREEN}✓${NC} Systemd service installed and enabled"
else
    echo -e "${YELLOW}!${NC} thingdb.service not found, skipping service setup"
fi

# Step 5: Start the service
echo ""
echo -e "${BLUE}Step 5/5: Starting ThingDB service...${NC}"
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

# Final summary
echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║              🎉 Installation Complete! 🎉                      ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "ThingDB is now running as a system service!"
echo ""
echo "Access your inventory system:"
echo "  http://$(hostname -I | awk '{print $1}'):5000"
echo ""
echo "Service Management:"
echo "  sudo systemctl status thingdb   - Check status"
echo "  sudo systemctl restart thingdb  - Restart service"
echo "  sudo systemctl stop thingdb     - Stop service"
echo "  sudo journalctl -u thingdb -f   - View live logs"
echo ""
echo "Configuration:"
echo "  Edit .env to change database settings or other options"
echo "  After editing .env, restart: sudo systemctl restart thingdb"
echo ""
echo -e "${GREEN}Enjoy your ThingDB inventory system! 📦${NC}"
echo ""

