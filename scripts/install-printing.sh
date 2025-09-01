#!/bin/bash

# Printing System Installation Script for Raspberry Pi
# This script installs CUPS and related dependencies for the inventory printing system

set -e

echo "🖨️ Installing Printing System Dependencies..."
echo "=============================================="

# Update package lists
echo "📦 Updating package lists..."
sudo apt update

# Install CUPS and related packages
echo "📥 Installing CUPS printing system..."
sudo apt install -y cups cups-client cups-daemon

# Install additional printer drivers
echo "🔧 Installing common printer drivers..."
sudo apt install -y hplip brother-lpr-drivers-extra cnijfilter-common

# Install fonts for better text rendering
echo "📝 Installing fonts..."
sudo apt install -y fonts-dejavu-core fonts-liberation

# Install network printer discovery
echo "🌐 Installing network printer discovery..."
sudo apt install -y avahi-daemon

# Add pi user to lpadmin group for printer management
echo "👤 Adding pi user to printer admin group..."
sudo usermod -a -G lpadmin pi

# Start and enable services
echo "🚀 Starting printing services..."
sudo systemctl start cups
sudo systemctl enable cups
sudo systemctl start avahi-daemon
sudo systemctl enable avahi-daemon

# Install Python dependencies
echo "🐍 Installing Python printing dependencies..."
pip3 install qrcode[pil]

echo ""
echo "✅ Printing system installation complete!"
echo ""
echo "📋 Next steps:"
echo "1. Connect your printer to the Raspberry Pi (USB or network)"
echo "2. Access CUPS web interface: http://$(hostname -I | awk '{print $1}'):631"
echo "3. Add your printer through the web interface"
echo "4. Set a default printer"
echo "5. Test printing from the inventory system web interface"
echo ""
echo "📖 For detailed setup instructions, see PRINTING_GUIDE.md"
echo ""
echo "🔧 To test printer connection:"
echo "   lpstat -p"
echo ""
