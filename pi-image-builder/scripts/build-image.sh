#!/bin/bash

echo "🥧 Raspberry Pi Inventory System - SD Card Image Builder"
echo "========================================================="

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
IMAGE_NAME="inventory-pi-$(date +%Y%m%d).img"

# Create directories
mkdir -p "$WORK_DIR" "$OUTPUT_DIR"

# Step 1: Download Raspberry Pi OS
echo "📥 Downloading Raspberry Pi OS..."
if [ ! -f "$WORK_DIR/raspios.img.xz" ]; then
    curl -L -o "$WORK_DIR/raspios.img.xz" "$PI_OS_URL"
fi

# Step 2: Extract the image
echo "📦 Extracting image..."
if [ ! -f "$WORK_DIR/raspios.img" ]; then
    xz -d -k "$WORK_DIR/raspios.img.xz"
fi

# Step 3: Create a copy to modify
echo "📋 Creating working copy..."
cp "$WORK_DIR/raspios.img" "$OUTPUT_DIR/$IMAGE_NAME"

# Step 4: Mount the image (macOS specific)
echo "🔧 Mounting image partitions..."
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    DEVICE=$(hdiutil attach -nomount "$OUTPUT_DIR/$IMAGE_NAME" | head -1 | awk '{print $1}')
    echo "  Attached as device: $DEVICE"
    
    # Mount boot partition
    mkdir -p "$WORK_DIR/mount/boot"
    mount -t msdos "${DEVICE}s1" "$WORK_DIR/mount/boot"
    
    # Mount root partition
    mkdir -p "$WORK_DIR/mount/root"
    mount -t ext4 "${DEVICE}s2" "$WORK_DIR/mount/root" 2>/dev/null || {
        echo "⚠️ Cannot mount ext4 on macOS directly. Using alternative method..."
        # We'll modify files in boot partition only for macOS
        MACOS_LIMITED=true
    }
else
    # Linux
    LOOP_DEVICE=$(losetup -f --show -P "$OUTPUT_DIR/$IMAGE_NAME")
    mkdir -p "$WORK_DIR/mount/boot" "$WORK_DIR/mount/root"
    mount "${LOOP_DEVICE}p1" "$WORK_DIR/mount/boot"
    mount "${LOOP_DEVICE}p2" "$WORK_DIR/mount/root"
fi

BOOT_DIR="$WORK_DIR/mount/boot"
ROOT_DIR="$WORK_DIR/mount/root"

# Step 5: Configure boot partition
echo "⚙️ Configuring boot settings..."

# Enable SSH
touch "$BOOT_DIR/ssh"

# Configure Wi-Fi (for first boot)
cp "$BUILDER_DIR/config/wpa_supplicant.conf" "$BOOT_DIR/wpa_supplicant.conf"

# Create firstrun script for initial setup
cat > "$BOOT_DIR/firstrun.sh" << 'FIRSTRUN'
#!/bin/bash

# This script runs once on first boot

set -e

# Set hostname
raspi-config nonint do_hostname inventory

# Configure locale and timezone
raspi-config nonint do_change_locale en_US.UTF-8
raspi-config nonint do_change_timezone America/Los_Angeles

# Enable SSH permanently
systemctl enable ssh
systemctl start ssh

# Create pi user's SSH directory and add authorized keys
mkdir -p /home/pi/.ssh
chmod 700 /home/pi/.ssh

# Add authorized keys from boot partition
if [ -f /boot/authorized_keys ]; then
    cp /boot/authorized_keys /home/pi/.ssh/authorized_keys
    chmod 600 /home/pi/.ssh/authorized_keys
    chown -R pi:pi /home/pi/.ssh
fi

# Disable password authentication for SSH
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl restart ssh

# Update system
apt update
apt upgrade -y

# Install inventory system dependencies
apt install -y \
    postgresql \
    postgresql-contrib \
    nginx \
    python3 \
    python3-pip \
    python3-venv \
    git \
    curl \
    wget \
    avahi-daemon

# Run the inventory installation
if [ -f /boot/inventory-install.sh ]; then
    bash /boot/inventory-install.sh
fi

# Expand filesystem
raspi-config nonint do_expand_rootfs

# Remove firstrun script
rm -f /boot/firstrun.sh
sed -i 's| systemd.run.*||g' /boot/cmdline.txt

# Reboot
reboot
FIRSTRUN

chmod +x "$BOOT_DIR/firstrun.sh"

# Copy authorized keys to boot
cp "$BUILDER_DIR/config/authorized_keys" "$BOOT_DIR/authorized_keys"

# Create inventory installation script
cat > "$BOOT_DIR/inventory-install.sh" << 'INVINSTALL'
#!/bin/bash

# Copy pi-deployment from boot partition if available
if [ -d /boot/pi-deployment ]; then
    cp -r /boot/pi-deployment /home/pi/
    chown -R pi:pi /home/pi/pi-deployment
    
    # Run the installation
    cd /home/pi/pi-deployment
    ./install/install-pi.sh
    
    # Enable services
    systemctl enable inventory-app
    systemctl enable nginx
    systemctl start inventory-app
    systemctl start nginx
fi
INVINSTALL

# Copy pi-deployment to boot partition
echo "📦 Copying inventory system to image..."
cp -r "$PROJECT_ROOT/pi-deployment" "$BOOT_DIR/"

# Modify cmdline.txt to run firstrun on boot
if [ -f "$BOOT_DIR/cmdline.txt" ]; then
    sed -i.bak 's/$/ systemd.run=\/boot\/firstrun.sh systemd.run_success_action=reboot systemd.unit=kernel-command-line.target/' "$BOOT_DIR/cmdline.txt"
fi

# Step 6: Configure root partition (if accessible)
if [ "$MACOS_LIMITED" != "true" ] && [ -d "$ROOT_DIR/etc" ]; then
    echo "🔧 Configuring root filesystem..."
    
    # Set hostname
    echo "inventory" > "$ROOT_DIR/etc/hostname"
    
    # Configure hosts file
    cat > "$ROOT_DIR/etc/hosts" << EOF
127.0.0.1       localhost
127.0.1.1       inventory
::1             localhost ip6-localhost ip6-loopback
ff02::1         ip6-allnodes
ff02::2         ip6-allrouters
EOF
    
    # Enable SSH service
    ln -sf /lib/systemd/system/ssh.service "$ROOT_DIR/etc/systemd/system/sshd.service"
    ln -sf /lib/systemd/system/ssh.service "$ROOT_DIR/etc/systemd/system/multi-user.target.wants/ssh.service"
else
    echo "⚠️ Root partition configuration skipped (will be done on first boot)"
fi

# Step 7: Unmount and cleanup
echo "🧹 Cleaning up..."
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    umount "$BOOT_DIR" 2>/dev/null || diskutil unmount "$BOOT_DIR"
    [ "$MACOS_LIMITED" != "true" ] && umount "$ROOT_DIR" 2>/dev/null
    hdiutil detach "$DEVICE"
else
    # Linux
    umount "$BOOT_DIR"
    umount "$ROOT_DIR"
    losetup -d "$LOOP_DEVICE"
fi

# Cleanup mount points
rm -rf "$WORK_DIR/mount"

echo ""
echo "✅ Image build complete!"
echo "📦 Output: $OUTPUT_DIR/$IMAGE_NAME"
echo ""
echo "📝 Next steps:"
echo "  1. Update Wi-Fi password in: $BUILDER_DIR/config/wpa_supplicant.conf"
echo "  2. Write to SD card: ./scripts/write-to-sd.sh /dev/diskX"
echo "  3. Insert SD card and boot your Pi"
echo "  4. Access at: https://inventory.local"
echo ""
echo "⚠️ IMPORTANT: Edit the Wi-Fi password before building the final image!"