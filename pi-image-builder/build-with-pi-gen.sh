#!/bin/bash

echo "🏗️ Building Inventory Pi Image with pi-gen"
echo "=========================================="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PI_GEN_DIR="$SCRIPT_DIR/pi-gen"

if [ ! -d "$PI_GEN_DIR" ]; then
    echo "❌ pi-gen not found. Run setup-pi-gen.sh first"
    exit 1
fi

cd "$PI_GEN_DIR"

# Update the deployment path in config
BUILDER_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(dirname "$BUILDER_DIR")"
sed -i.bak "s|INVENTORY_DEPLOYMENT_PATH=.*|INVENTORY_DEPLOYMENT_PATH='$PROJECT_ROOT/pi-deployment'|" config

# Also update the install script with the actual path
sed -i.bak "s|INVENTORY_DEPLOYMENT_PATH|$PROJECT_ROOT/pi-deployment|g" stage-inventory/00-inventory/01-run.sh

echo "🚀 Starting pi-gen build..."
echo "This will take 30-60 minutes..."

# Build the image
sudo ./build.sh

echo ""
echo "✅ Build complete!"
echo "📦 Image location: $PI_GEN_DIR/deploy/"
ls -la "$PI_GEN_DIR/deploy/"*.img* 2>/dev/null || echo "Check deploy/ directory for output"
