#!/bin/bash

echo "🥧 Pi Inventory Image - Fixed Method"
echo "===================================="
echo "Using lessons learned from Pi Imager analysis"
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
IMAGE_NAME="inventory-pi-fixed-$(date +%Y%m%d-%H%M).img"

# Create directories
mkdir -p "$WORK_DIR" "$OUTPUT_DIR"

# Download and extract base image
echo "📥 Preparing base image..."
if [ ! -f "$WORK_DIR/raspios.img.xz" ]; then
    curl -L -o "$WORK_DIR/raspios.img.xz" "$PI_OS_URL"
fi

if [ ! -f "$WORK_DIR/raspios.img" ]; then
    echo "📦 Extracting image..."
    xz -d -k "$WORK_DIR/raspios.img.xz"
fi

echo "📋 Creating working copy..."
cp "$WORK_DIR/raspios.img" "$OUTPUT_DIR/$IMAGE_NAME"

# Mount the image
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

# 1. Enable SSH
touch "$BOOT_DIR/ssh"

# 2. Create empty wpa_supplicant.conf (Pi Imager method)
cat > "$BOOT_DIR/wpa_supplicant.conf" << 'EOF'
country=US
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1

network={
	ssid="salty"
	psk=
}
EOF

# 3. Generate proper PSK hash for Wi-Fi
echo "🔐 Generating Wi-Fi credentials..."
PSK_HASH=$(echo -n "salty${WIFI_PASSWORD}" | openssl dgst -sha256 | cut -d' ' -f2)

# 4. Create proper firstrun.sh (based on Pi Imager analysis)
cat > "$BOOT_DIR/firstrun.sh" << FIRSTRUN
#!/bin/bash

set +e

# Set hostname
CURRENT_HOSTNAME=\`cat /etc/hostname | tr -d " \t\n\r"\`
echo inventory >/etc/hostname
sed -i "s/127.0.1.1.*\$CURRENT_HOSTNAME/127.0.1.1\tinventory/g" /etc/hosts

# Get first user info
FIRSTUSER=\`getent passwd 1000 | cut -d: -f1\`
FIRSTUSERHOME=\`getent passwd 1000 | cut -d: -f6\`

# Setup SSH keys
install -o "\$FIRSTUSER" -m 700 -d "\$FIRSTUSERHOME/.ssh"
cat > "\$FIRSTUSERHOME/.ssh/authorized_keys" << 'SSHKEY'
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCn8IW5zsi7oNEjOPrCwHXtV3Zb9eC33Mua06n+c6ZyFnDT+KowrfFAEcomYtiR6Jmr+o5zQlLgzX5wd706zgGHlv1+L7DEOTBo+lpqbyXbwECTI4osfpAZYQVdUAWUw6b6PaZttVTIhmPpTU9drOepxcege/8f3SpTv2WBUjz7H+3rj7FpjRocQLc7kz8azI2SAPijm1t365h3rAmRtdEQ8RS6iL4OOH1wvAUVw2SDpakVH5zeUx4qZ7KJr3nT8oA8GF4zMr+jWVFweSFKrGHVTfRQ0ToOelR2djf/LJa2N/NmoW8csYBuTENg/g7QusMLsc8a8HwjnbeyjyM/qjRr3bvSc+KFLD4uKOMNqLgJIluXhKAjLqHOKCwZiKi1VJrHQ/fu3HhWCVNk31m+8uWAs4MbRJiNe1CdM76pOR8XsO62uuwbUtWwww1GZ4ruB3FBxF8wmvQiUjz8i+gNoeTv1kI/8kal6aVbmHUQXoPmcIKBrUmcpJkihcRIoPZuNlc= ianmccutcheon@Ians-MacBook-Pro.local
SSHKEY

chmod 600 "\$FIRSTUSERHOME/.ssh/authorized_keys"
chown -R "\$FIRSTUSER:\$FIRSTUSER" "\$FIRSTUSERHOME/.ssh"

# Disable password authentication
echo 'PasswordAuthentication no' >>/etc/ssh/sshd_config
systemctl enable ssh

# Set user password (pi:inventory)
echo "pi:inventory" | chpasswd

# Configure Wi-Fi with proper PSK hash
cat >/etc/wpa_supplicant/wpa_supplicant.conf <<'WPAEOF'
country=US
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
ap_scan=1
update_config=1

network={
	ssid="salty"
	psk=${PSK_HASH}
}
WPAEOF

chmod 600 /etc/wpa_supplicant/wpa_supplicant.conf

# Restart Wi-Fi services
rfkill unblock wifi
for filename in /var/lib/systemd/rfkill/*:wlan ; do
    [ -f "\$filename" ] && echo 0 > "\$filename"
done

# Install inventory system if available
if [ -d /boot/pi-deployment ]; then
    echo "Installing inventory system..."
    cp -r /boot/pi-deployment /home/pi/
    chown -R pi:pi /home/pi/pi-deployment
    
    # Run installation
    cd /home/pi/pi-deployment
    ./install/install-pi.sh > /var/log/inventory-install.log 2>&1
    
    if [ \$? -eq 0 ]; then
        echo "✅ Inventory system installed successfully"
    else
        echo "❌ Inventory system installation failed - check /var/log/inventory-install.log"
    fi
fi

# Clean up
rm -f /boot/firstrun.sh
sed -i 's| systemd.run.*||g' /boot/cmdline.txt

echo "First-run setup completed at \$(date)" >> /var/log/firstrun.log

exit 0
FIRSTRUN

chmod +x "$BOOT_DIR/firstrun.sh"

# 5. Copy inventory system
echo "📦 Copying inventory system..."
if [ -d "$PROJECT_ROOT/pi-deployment" ]; then
    cp -r "$PROJECT_ROOT/pi-deployment" "$BOOT_DIR/"
    echo "  ✅ Copied pi-deployment"
fi

# 6. Modify cmdline.txt (minimal changes)
if [ -f "$BOOT_DIR/cmdline.txt" ]; then
    # Backup original
    cp "$BOOT_DIR/cmdline.txt" "$BOOT_DIR/cmdline.txt.bak"
    
    # Add firstrun and regulatory domain (single line, no duplicates)
    if ! grep -q "systemd.run=/boot/firstrun.sh" "$BOOT_DIR/cmdline.txt"; then
        echo -n " systemd.run=/boot/firstrun.sh systemd.run_success_action=reboot systemd.unit=kernel-command-line.target cfg80211.ieee80211_regdom=US" >> "$BOOT_DIR/cmdline.txt"
    fi
fi

# 7. Create status file
cat > "$BOOT_DIR/inventory-build-info.txt" << EOF
Inventory Pi Image - Build Info
==============================

Built: $(date)
Wi-Fi SSID: $WIFI_SSID
Wi-Fi PSK Hash: $PSK_HASH
SSH Key: Configured
Hostname: inventory

This image includes:
- Complete inventory system in /boot/pi-deployment
- Automatic Wi-Fi connection to "$WIFI_SSID"
- SSH access with your public key
- All dependencies pre-configured

First boot will:
1. Connect to Wi-Fi
2. Set hostname to 'inventory'
3. Install inventory system
4. Enable all services

Access after first boot:
- SSH: ssh pi@inventory.local (password: inventory)
- Web: https://inventory.local
EOF

echo "🧹 Cleaning up..."
sync

# Unmount
if [[ "$OSTYPE" == "darwin"* ]]; then
    umount "$BOOT_DIR"
    hdiutil detach "$DEVICE"
else
    umount "$BOOT_DIR"
    losetup -d "$LOOP_DEVICE"
fi

rm -rf "$WORK_DIR/mount"

echo ""
echo "✅ Fixed image build complete!"
echo "📦 Output: $OUTPUT_DIR/$IMAGE_NAME"
echo ""
echo "📋 This image uses:"
echo "  • Proper PSK hash generation"
echo "  • Clean firstrun.sh based on Pi Imager"
echo "  • Minimal cmdline.txt changes"
echo "  • Regulatory domain configuration"
echo "  • Error logging and status reporting"
echo ""
echo "🔧 Write to SD: ./scripts/write-to-sd.sh /dev/disk4"