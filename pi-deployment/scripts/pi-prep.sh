#!/bin/bash

echo "🥧 Preparing Raspberry Pi deployment package..."

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PI_DEPLOYMENT_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(dirname "$PI_DEPLOYMENT_DIR")"

echo "📁 Project root: $PROJECT_ROOT"
echo "📁 Pi deployment: $PI_DEPLOYMENT_DIR"

# Check if development environment is running
if ! docker-compose -f "$PROJECT_ROOT/docker/docker-compose-dev.yml" ps | grep -q "Up"; then
    echo "⚠️ Development environment not running. Starting it..."
    cd "$PROJECT_ROOT"
    ./scripts/start-dev.sh
    echo "⏱️ Waiting for services to start..."
    sleep 15
fi

# Copy source code to deployment package
echo "📋 Copying source code..."
cp -r "$PROJECT_ROOT/src"/* "$PI_DEPLOYMENT_DIR/"
echo "✅ Source code copied"

# Export database
echo "🗄️ Exporting database..."
cd "$PROJECT_ROOT"
docker-compose -f docker/docker-compose-dev.yml exec flask-app pg_dump -U docker -d docker_dev --no-owner --no-privileges > "$PI_DEPLOYMENT_DIR/data/database-export.sql"

if [ $? -eq 0 ]; then
    echo "✅ Database exported successfully"
    echo "   Size: $(du -h "$PI_DEPLOYMENT_DIR/data/database-export.sql" | cut -f1)"
else
    echo "❌ Database export failed"
    exit 1
fi

# Extract images from database
echo "🖼️ Extracting images from database..."
cd "$PROJECT_ROOT"

# Use our working Docker extraction script
./pi-deployment/scripts/extract-images-docker.sh

# Make scripts executable
echo "🔧 Setting up permissions..."
chmod +x "$PI_DEPLOYMENT_DIR/install"/*.sh
chmod +x "$PI_DEPLOYMENT_DIR/scripts"/*.sh

# Ensure all shell scripts have proper line endings
find "$PI_DEPLOYMENT_DIR" -name "*.sh" -exec dos2unix {} \; 2>/dev/null || true

# Create deployment package info
cat > "$PI_DEPLOYMENT_DIR/deployment-info.txt" << EOF
Home Inventory System - Raspberry Pi Deployment Package
======================================================

Generated: $(date)
Database export: $(du -h "$PI_DEPLOYMENT_DIR/data/database-export.sql" | cut -f1)
Images extracted: $(find "$PI_DEPLOYMENT_DIR/data/images" -name "*.jpg" -o -name "*.png" -o -name "*.gif" 2>/dev/null | wc -l || echo "0") files

Installation Instructions:
1. Copy this entire pi-deployment folder to your Raspberry Pi
2. SSH into your Pi as root (or use sudo)
3. Run: ./install/install-pi.sh
4. Access your inventory at: https://raspberrypi.local

Requirements:
- Raspberry Pi 4 or 5 with 4GB+ RAM
- Fresh Raspberry Pi OS installation
- Internet connection for package downloads

EOF

echo ""
echo "✅ Pi deployment package ready!"
echo "📦 Location: $PI_DEPLOYMENT_DIR"
echo "📄 Package info: $PI_DEPLOYMENT_DIR/deployment-info.txt"
echo ""
echo "🚀 Next steps:"
echo "   1. Copy pi-deployment/ folder to your Raspberry Pi"
echo "   2. SSH to Pi: ssh pi@raspberrypi.local"
echo "   3. Run: sudo ./pi-deployment/install/install-pi.sh"
echo "   4. Access: https://raspberrypi.local"