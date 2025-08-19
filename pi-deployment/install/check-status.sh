#!/bin/bash

echo "🔍 Home Inventory System - Status Check"
echo "========================================"
echo ""

# Check services
echo "📊 Service Status:"
echo -n "  PostgreSQL: "
systemctl is-active postgresql > /dev/null 2>&1 && echo "✅ Running" || echo "❌ Not running"

echo -n "  Flask App:  "
systemctl is-active inventory-app > /dev/null 2>&1 && echo "✅ Running" || echo "❌ Not running"

echo -n "  Nginx:      "
systemctl is-active nginx > /dev/null 2>&1 && echo "✅ Running" || echo "❌ Not running"

echo ""

# Check database
echo "🗄️ Database Status:"
if sudo -u postgres psql -d inventory_db -c "SELECT 1;" > /dev/null 2>&1; then
    echo "  ✅ Database accessible"
    
    # Count items and images
    ITEM_COUNT=$(sudo -u postgres psql -d inventory_db -t -c "SELECT COUNT(*) FROM items;" 2>/dev/null | xargs)
    IMAGE_COUNT=$(sudo -u postgres psql -d inventory_db -t -c "SELECT COUNT(*) FROM images;" 2>/dev/null | xargs)
    echo "  📦 Items:  $ITEM_COUNT"
    echo "  🖼️ Images: $IMAGE_COUNT"
else
    echo "  ❌ Database not accessible"
fi

echo ""

# Check file system
echo "📁 File System:"
if [ -d "/var/lib/inventory" ]; then
    echo "  ✅ Application directory exists"
    
    # Count image files
    if [ -d "/var/lib/inventory/images" ]; then
        FILE_COUNT=$(find /var/lib/inventory/images -type f 2>/dev/null | wc -l)
        echo "  🖼️ Image files: $FILE_COUNT"
    fi
    
    # Check log files
    if [ -f "/var/lib/inventory/logs/error.log" ]; then
        echo "  📝 Error log exists"
        RECENT_ERRORS=$(tail -5 /var/lib/inventory/logs/error.log 2>/dev/null | grep -c ERROR)
        if [ "$RECENT_ERRORS" -gt 0 ]; then
            echo "  ⚠️ Recent errors found in log"
        fi
    fi
else
    echo "  ❌ Application directory not found"
fi

echo ""

# Check network
echo "🌐 Network Access:"
echo "  Local:  https://$(hostname).local"
echo "  IP:     https://$(hostname -I | awk '{print $1}')"

# Test if nginx is responding
curl -k -s -o /dev/null -w "  Nginx:  %{http_code}\n" https://localhost 2>/dev/null || echo "  Nginx:  ❌ Not responding"

echo ""

# Show log commands
echo "📝 Useful Commands:"
echo "  View app logs:     journalctl -u inventory-app -f"
echo "  View nginx logs:   tail -f /var/log/nginx/error.log"
echo "  View access logs:  tail -f /var/lib/inventory/logs/access.log"
echo "  Restart app:       sudo systemctl restart inventory-app"
echo "  Restart nginx:     sudo systemctl restart nginx"