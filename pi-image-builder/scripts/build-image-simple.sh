#!/bin/bash

echo "🥧 Raspberry Pi Inventory System - Simple Image Builder"
echo "======================================================="
echo "This version creates a more reliable image with minimal first-boot setup"
echo ""

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILDER_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(dirname "$BUILDER_DIR")"

# Load configuration
source "$BUILDER_DIR/config/settings.conf"

# Configuration
PI_OS_URL="https://downloads.raspberrypi.org/raspios_lite_arm64/images/raspios_lite_arm64-2024-07-04/2024-07-04-raspios-bookworm-arm64-lite.img.xz"
WORK_DIR="$BUILDER_DIR/work"
OUTPUT_DIR="$BUILDER_DIR/output"
IMAGE_NAME="inventory-pi-simple-$(date +%Y%m%d).img"

# Create directories
mkdir -p "$WORK_DIR" "$OUTPUT_DIR"

# Step 1: Download and extract base image
echo "📥 Preparing base image..."
if [ ! -f "$WORK_DIR/raspios.img.xz" ]; then
    curl -L -o "$WORK_DIR/raspios.img.xz" "$PI_OS_URL"
fi

if [ ! -f "$WORK_DIR/raspios.img" ]; then
    xz -d -k "$WORK_DIR/raspios.img.xz"
fi

# Step 2: Copy and prepare working image
echo "📋 Creating working copy..."
cp "$WORK_DIR/raspios.img" "$OUTPUT_DIR/$IMAGE_NAME"

# Step 3: Mount the image
echo "🔧 Mounting image..."
if [[ "$OSTYPE" == "darwin"* ]]; then
    DEVICE=$(hdiutil attach -nomount "$OUTPUT_DIR/$IMAGE_NAME" | head -1 | awk '{print $1}')
    mkdir -p "$WORK_DIR/mount/boot"
    mount -t msdos "${DEVICE}s1" "$WORK_DIR/mount/boot"
else
    LOOP_DEVICE=$(losetup -f --show -P "$OUTPUT_DIR/$IMAGE_NAME")
    mkdir -p "$WORK_DIR/mount/boot"
    mount "${LOOP_DEVICE}p1" "$WORK_DIR/mount/boot"
fi

BOOT_DIR="$WORK_DIR/mount/boot"

echo "⚙️ Configuring boot partition..."

# Enable SSH
touch "$BOOT_DIR/ssh"

# Configure Wi-Fi
cp "$BUILDER_DIR/config/wpa_supplicant.conf" "$BOOT_DIR/wpa_supplicant.conf"

# Add user configuration (Pi OS Lite feature)
cat > "$BOOT_DIR/userconf.txt" << EOF
pi:\$6\$rBwdnKUUhxH.\$0pMqpLMkF5oF1oT9VLXkFrzqEIrqkUgCbLJKQQpGgCJHZ8Kh0zO1GjrqnFrCw8KY1dqGJZhR9xrKM/ZLG01
EOF

# Copy authorized keys
mkdir -p "$BOOT_DIR/ssh-keys"
cp "$BUILDER_DIR/config/authorized_keys" "$BOOT_DIR/ssh-keys/authorized_keys"

# Create simple first-run service instead of complex script
cat > "$BOOT_DIR/install-inventory.sh" << 'SIMPLE_INSTALL'
#!/bin/bash

# Simple inventory installation script
# This runs after the system is fully booted

set -e

LOG_FILE="/var/log/inventory-install.log"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "Starting inventory installation at $(date)"

# Set hostname
hostnamectl set-hostname inventory

# Update /etc/hosts
sed -i 's/127.0.1.1.*/127.0.1.1\tinventory/' /etc/hosts

# Setup SSH keys
if [ -f /boot/ssh-keys/authorized_keys ]; then
    mkdir -p /home/pi/.ssh
    cp /boot/ssh-keys/authorized_keys /home/pi/.ssh/authorized_keys
    chmod 600 /home/pi/.ssh/authorized_keys
    chown -R pi:pi /home/pi/.ssh
fi

# Disable password auth for SSH
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl restart ssh

# Install inventory system if deployment package exists
if [ -d /boot/pi-deployment ]; then
    echo "Installing inventory system..."
    
    # Copy to home directory
    cp -r /boot/pi-deployment /home/pi/
    chown -R pi:pi /home/pi/pi-deployment
    
    # Run installation
    cd /home/pi/pi-deployment
    ./install/install-pi.sh
    
    echo "Inventory installation completed"
else
    echo "No pi-deployment found, skipping inventory installation"
fi

# Clean up
rm -f /boot/install-inventory.sh
systemctl disable inventory-firstrun.service
rm -f /etc/systemd/system/inventory-firstrun.service

echo "First-run setup completed at $(date)"
SIMPLE_INSTALL

chmod +x "$BOOT_DIR/install-inventory.sh"

# Create systemd service for first-run
cat > "$BOOT_DIR/inventory-firstrun.service" << 'SERVICE'
[Unit]
Description=Inventory System First-Run Setup
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/boot/install-inventory.sh
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVICE

# Copy pi-deployment to boot
echo "📦 Copying inventory system..."
if [ -d "$PROJECT_ROOT/pi-deployment" ]; then
    cp -r "$PROJECT_ROOT/pi-deployment" "$BOOT_DIR/"
    echo "  ✅ Copied pi-deployment"
else
    echo "  ⚠️ pi-deployment not found, image will boot without inventory system"
fi

# Create installation instructions file
cat > "$BOOT_DIR/FIRST_BOOT_INSTRUCTIONS.txt" << 'INSTRUCTIONS'
Inventory Pi - First Boot Instructions
=====================================

This SD card will automatically:
1. Enable SSH with your public key
2. Connect to Wi-Fi network "salty"
3. Set hostname to "inventory"
4. Install the inventory system

After first boot (5-10 minutes):
- SSH: ssh pi@inventory.local
- Web: https://inventory.local

If something goes wrong:
- Check logs: sudo journalctl -u inventory-firstrun
- Manual install: sudo /boot/install-inventory.sh
- Skip inventory: rm /boot/pi-deployment

The first boot may take 10-15 minutes to complete all setup.
Red LED initially is normal - wait for it to turn green.
INSTRUCTIONS

echo "🧹 Cleaning up..."
if [[ "$OSTYPE" == "darwin"* ]]; then
    umount "$BOOT_DIR"
    hdiutil detach "$DEVICE"
else
    umount "$BOOT_DIR"
    losetup -d "$LOOP_DEVICE"
fi

rm -rf "$WORK_DIR/mount"

echo ""
echo "✅ Simple image build complete!"
echo "📦 Output: $OUTPUT_DIR/$IMAGE_NAME"
echo ""
echo "📝 This image will:"
echo "  • Boot normally without complex first-run modifications"
echo "  • Install inventory system after network is up"
echo "  • Use systemd service instead of cmdline modifications"
echo "  • Be more reliable and easier to debug"
echo ""
echo "🔧 Next: ./scripts/write-to-sd.sh /dev/diskX"