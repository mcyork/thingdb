#!/bin/bash

echo "⚙️ Setting up systemd services..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PI_DEPLOYMENT_DIR="$(dirname "$SCRIPT_DIR")"

# Copy systemd service files
cp "$PI_DEPLOYMENT_DIR/config/inventory.service" /etc/systemd/system/inventory-app.service

# Create environment file
cp "$PI_DEPLOYMENT_DIR/config/environment-pi.env" /var/lib/inventory/config/environment.env
chown inventory:inventory /var/lib/inventory/config/environment.env

# Reload systemd
systemctl daemon-reload

echo "✅ Systemd services configured"