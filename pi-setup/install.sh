#!/bin/bash

# This script must be run as root
if [ "$EUID" -ne 0 ]
  then echo "Please run as root or with sudo"
  exit
fi

set -e

echo ">>> Installing Bluetooth Config Service..."

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

echo ">>> Installing Python dependencies..."
pip3 install -r "$SCRIPT_DIR/requirements.txt"

echo ">>> Copying service files..."
cp "$SCRIPT_DIR/ble_config_service.py" /usr/local/bin/
chmod +x /usr/local/bin/ble_config_service.py

cp "$SCRIPT_DIR/ble-config.service" /etc/systemd/system/

echo ">>> Setting up and starting systemd service..."
systemctl daemon-reload
systemctl enable ble-config.service
systemctl restart ble-config.service

echo ">>> Installation complete. The BLE config service is now running."
