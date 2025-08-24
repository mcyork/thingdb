#!/bin/bash

# This script must be run as root
if [ "$EUID" -ne 0 ]
  then echo "Please run as root or with sudo"
  exit
fi

set -e

echo ">>> Installing BTBerryWifi BLE Service..."

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

echo ">>> Installing BTBerryWifi service..."
# Install the btwifiset service using the official installer
curl -L https://raw.githubusercontent.com/nksan/Rpi-SetWiFi-viaBluetooth/main/btwifisetInstall.sh | bash

# Deploy web app for setup
echo ">>> Deploying web app for Bluetooth setup..."
sudo mkdir -p /var/www/inventory-setup/
sudo cp -r "$SCRIPT_DIR/webapp/"* /var/www/inventory-setup/
sudo chown -R www-data:www-data /var/www/inventory-setup/
sudo systemctl reload nginx

# Apply Bluetooth/Wi-Fi coexistence firmware patch
echo ">>> Applying Wi-Fi/Bluetooth coexistence firmware patch..."
FIRMWARE_FILE="/usr/lib/firmware/brcm/brcmfmac43455-sdio.txt"

OLD_COEXISTENCE_CONFIG="# Improved Bluetooth coexistence parameters from Cypress\nbtc_mode=1\nbtc_params8=0x4e20\nbtc_params1=0x7530\nbtc_params50=0x972c"
NEW_COEXISTENCE_CONFIG="# Improved Bluetooth coexistence parameters from Cypress\nbtc_mode=4\n# btc_params8=0x4e20\n# btc_params1=0x7530\n# btc_params50=0x972c"

sudo sed -i "s|${OLD_COEXISTENCE_CONFIG}|${NEW_COEXISTENCE_CONFIG}|g" "$FIRMWARE_FILE"

echo ">>> Setting up and starting BTBerryWifi service..."
systemctl daemon-reload

# Enable and start the btwifiset service (this is the main BLE service)
systemctl enable btwifiset.service
systemctl start btwifiset.service

echo ">>> Installation complete. The BTBerryWifi BLE service is now running."
echo ">>> Users can now use the BTBerryWifi mobile app to configure WiFi."

# Show service status
echo ">>> Service Status:"
systemctl status btwifiset.service --no-pager
echo ""
echo ">>> To check logs: journalctl -u btwifiset.service -f"
echo ">>> To restart: systemctl restart btwifiset.service"
echo ">>> To check if service is running: systemctl is-active btwifiset.service"
