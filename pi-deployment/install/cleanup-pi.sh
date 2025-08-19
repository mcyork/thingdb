#!/bin/bash

echo "🧹 Cleaning up previous Home Inventory installation..."

# Stop services
echo "⏹️ Stopping services..."
systemctl stop inventory-app 2>/dev/null || true
systemctl stop nginx 2>/dev/null || true
systemctl disable inventory-app 2>/dev/null || true

# Remove systemd service
echo "🗑️ Removing systemd services..."
rm -f /etc/systemd/system/inventory-app.service
systemctl daemon-reload

# Clean up database
echo "🗄️ Cleaning up database..."
sudo -u postgres psql << 'EOF' 2>/dev/null || true
DROP DATABASE IF EXISTS inventory_db;
DROP USER IF EXISTS inventory;
EOF

# Remove nginx configuration
echo "🌐 Removing nginx configuration..."
rm -f /etc/nginx/sites-enabled/inventory
rm -f /etc/nginx/sites-available/inventory

# Remove application files
echo "📁 Removing application files..."
rm -rf /var/lib/inventory

# Remove inventory user (optional - commented out for safety)
# echo "👤 Removing inventory user..."
# userdel -r inventory 2>/dev/null || true

echo "✅ Cleanup complete!"
echo ""
echo "You can now run a fresh installation with:"
echo "  sudo ./install-pi.sh"