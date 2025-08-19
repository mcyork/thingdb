#!/bin/bash

echo "🏗️ Setting up pi-gen for Inventory System Image Building"
echo "======================================================="

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILDER_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(dirname "$BUILDER_DIR")"

# Configuration
PI_GEN_DIR="$BUILDER_DIR/pi-gen"

# Check if we need to clone pi-gen
if [ ! -d "$PI_GEN_DIR" ]; then
    echo "📥 Cloning pi-gen..."
    git clone https://github.com/RPi-Distro/pi-gen.git "$PI_GEN_DIR"
else
    echo "✅ pi-gen already exists"
fi

cd "$PI_GEN_DIR"

# Create our custom stage
echo "🏗️ Creating custom stage for inventory system..."
STAGE_DIR="$PI_GEN_DIR/stage-inventory"
mkdir -p "$STAGE_DIR/00-inventory/files"

# Create prerun script for our stage
cat > "$STAGE_DIR/prerun.sh" << 'EOF'
#!/bin/bash -e

# This runs before our custom stage
echo "Preparing inventory system installation..."
EOF

# Create our main installation script
cat > "$STAGE_DIR/00-inventory/01-run.sh" << 'INSTALL'
#!/bin/bash -e

# Install inventory system dependencies
on_chroot << CHROOT
apt-get update
apt-get install -y postgresql postgresql-contrib nginx python3 python3-pip python3-venv git curl wget avahi-daemon
CHROOT

# Copy inventory system files
install -d "${ROOTFS_DIR}/home/pi/pi-deployment"
cp -r INVENTORY_DEPLOYMENT_PATH/* "${ROOTFS_DIR}/home/pi/pi-deployment/"

# Set up inventory system
on_chroot << CHROOT
cd /home/pi/pi-deployment
chmod +x install/*.sh
chmod +x scripts/*.sh
chown -R pi:pi /home/pi/pi-deployment

# Run the installation in the chroot environment
SKIP_DB_INIT=true ./install/install-pi.sh

# Enable services
systemctl enable inventory-app
systemctl enable nginx
systemctl enable avahi-daemon
CHROOT

echo "Inventory system installed successfully"
INSTALL

chmod +x "$STAGE_DIR/prerun.sh"
chmod +x "$STAGE_DIR/00-inventory/01-run.sh"

# Create pi-gen configuration
echo "⚙️ Creating pi-gen configuration..."
cat > "$PI_GEN_DIR/config" << CONFIG
IMG_NAME='inventory-pi-system'
RELEASE='bookworm'
DEPLOY_COMPRESSION='xz'
LOCALE_DEFAULT='en_US.UTF-8'
TARGET_HOSTNAME='inventory'
KEYBOARD_KEYMAP='us'
KEYBOARD_LAYOUT='English (US)'
TIMEZONE_DEFAULT='America/Los_Angeles'
FIRST_USER_NAME='pi'
FIRST_USER_PASS='inventory'
WPA_ESSID='salty'
WPA_PASSWORD='I4getit2'
WPA_COUNTRY='US'
ENABLE_SSH=1
PUBKEY_SSH_FIRST_USER='ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCn8IW5zsi7oNEjOPrCwHXtV3Zb9eC33Mua06n+c6ZyFnDT+KowrfFAEcomYtiR6Jmr+o5zQlLgzX5wd706zgGHlv1+L7DEOTBo+lpqbyXbwECTI4osfpAZYQVdUAWUw6b6PaZttVTIhmPpTU9drOepxcege/8f3SpTv2WBUjnT+KowrfFAEcomYtiR6Jmr+o5zQlLgzX5wd706zgGHlv1+L7DEOTBo+lpqbyXbwECTI4osfpAZYQVdUAWUw6b6PaZttVTIhmPpTU9drOepxcege/8f3SpTv2WBUjz7H+3rj7FpjRocQLc7kz8azI2SAPijm1t365h3rAmRtdEQ8RS6iL4OOH1wvAUVw2SDpakVH5zeUx4qZ7KJr3nT8oA8GF4zMr+jWVFweSFKrGHVTfRQ0ToOelR2djf/LJa2N/NmoW8csYBuTENg/g7QusMLsc8a8HwjnbeyjyM/qjRr3bvSc+KFLD4uKOMNqLgJIluXhKAjLqHOKCwZiKi1VJrHQ/fu3HhWCVNk31m+8uWAs4MbRJiNe1CdM76pOR8XsO62uuwbUtWwww1GZ4ruB3FBxF8wmvQiUjz8i+gNoeTv1kI/8kal6aVbmHUQXoPmcIKBrUmcpJkihcRIoPZuNlc= ianmccutcheon@Ians-MacBook-Pro.local'
PUBKEY_ONLY_SSH=1
STAGE_LIST='stage0 stage1 stage2 stage-inventory'
INVENTORY_DEPLOYMENT_PATH='$PROJECT_ROOT/pi-deployment'
CONFIG

# Create build script
cat > "$BUILDER_DIR/build-with-pi-gen.sh" << 'BUILD'
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
BUILD

chmod +x "$BUILDER_DIR/build-with-pi-gen.sh"

echo ""
echo "✅ pi-gen setup complete!"
echo ""
echo "📝 Next steps:"
echo "  1. Review configuration: $PI_GEN_DIR/config"
echo "  2. Build image: ./build-with-pi-gen.sh"
echo "  3. This will create a fully custom Pi OS with inventory system pre-installed"
echo ""
echo "⚠️ Note: Building will take 30-60 minutes and requires Docker"