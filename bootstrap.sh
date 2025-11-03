#!/bin/bash
# ThingDB Bootstrap Installer
# This script downloads and runs the ThingDB installer
# Usage: wget -qO- https://raw.githubusercontent.com/mcyork/thingdb/main/bootstrap.sh | bash

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║         ThingDB One-Command Bootstrap Installer                ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Check if running on Raspberry Pi
if grep -q "Raspberry Pi" /proc/cpuinfo 2>/dev/null; then
    echo -e "${BLUE}📟 Raspberry Pi detected${NC}"
    echo ""
    echo -e "${YELLOW}⚠️  Important for Pi Zero/older models:${NC}"
    echo "   Large downloads may fail due to limited /tmp space."
    echo "   The installer will handle this automatically."
    echo ""
fi

# Create temporary directory
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

echo -e "${BLUE}📥 Downloading ThingDB...${NC}"
wget -q --show-progress https://github.com/mcyork/thingdb/archive/refs/heads/main.zip -O thingdb.zip

echo ""
echo -e "${BLUE}📦 Extracting...${NC}"
unzip -q thingdb.zip

echo ""
echo -e "${BLUE}🚀 Starting installation...${NC}"
echo ""

cd thingdb-main
chmod +x install.sh
./install.sh

# Cleanup
echo ""
echo -e "${BLUE}🧹 Cleaning up...${NC}"
cd /
rm -rf "$TEMP_DIR"

echo ""
echo -e "${GREEN}✨ Bootstrap complete!${NC}"
echo ""

