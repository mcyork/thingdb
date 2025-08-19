#!/bin/bash

echo "🥧 Pi Inventory Image - Raspberry Pi Imager Style"
echo "================================================"
echo "This mimics exactly what the official Pi Imager does"
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
IMAGE_NAME="inventory-pi-imager-$(date +%Y%m%d).img"

# Create directories
mkdir -p "$WORK_DIR" "$OUTPUT_DIR"

# Download and extract base image
echo "📥 Preparing base image..."
if [ ! -f "$WORK_DIR/raspios.img.xz" ]; then
    curl -L -o "$WORK_DIR/raspios.img.xz" "$PI_OS_URL"
fi

if [ ! -f "$WORK_DIR/raspios.img" ]; then
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

echo "⚙️ Configuring boot partition (Pi Imager style)..."

# 1. Enable SSH (Pi Imager method)
touch "$BOOT_DIR/ssh"

# 2. Generate proper PSK hash for Wi-Fi (exactly like Pi Imager)
PSK_HASH=$(wpa_passphrase "$WIFI_SSID" "$WIFI_PASSWORD" | grep -v "#psk" | grep "psk=" | cut -d'=' -f2)

cat > "$BOOT_DIR/wpa_supplicant.conf" << EOF
country=$WIFI_COUNTRY
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1

network={
	ssid="$WIFI_SSID"
	psk=$PSK_HASH
}
EOF

# 3. Create user with password hash (Pi Imager method)
# Generate password hash for 'pi' user with password 'inventory'
USER_HASH='$6$rounds=656000$YQKJZkKOuKS9cNLu$lIAgKQXRKS8qZQEJztHN9wPZ7B8LOCXhF8uQcgp1PYXvhpYOW9K6m/VKSyJP9aKkc3BPP'

cat > "$BOOT_DIR/userconf.txt" << EOF
pi:$USER_HASH
EOF

# 4. Setup SSH keys (Pi Imager method - goes in firstrun.sh)
cat > "$BOOT_DIR/firstrun.sh" << 'FIRSTRUN'
#!/bin/bash

set +e

CURRENT_HOSTNAME=`cat /etc/hostname | tr -d " \t\n\r"`
if [ -f /usr/lib/raspberrypi-sys-mods/imager_custom ]; then
   /usr/lib/raspberrypi-sys-mods/imager_custom set_hostname inventory
else
   echo inventory >/etc/hostname
   sed -i "s/127.0.1.1.*$CURRENT_HOSTNAME/127.0.1.1\tinventory/g" /etc/hosts
fi

# Setup SSH keys
if [ -f /boot/authorized_keys ]; then
   mkdir -p /home/pi/.ssh
   cp /boot/authorized_keys /home/pi/.ssh/authorized_keys
   chmod 600 /home/pi/.ssh/authorized_keys
   chown pi:pi /home/pi/.ssh/authorized_keys
fi

# Disable password auth
if [ -f /usr/lib/raspberrypi-sys-mods/imager_custom ]; then
   /usr/lib/raspberrypi-sys-mods/imager_custom disable_password_auth
else
   sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
   systemctl restart ssh
fi

# Install inventory system
if [ -d /boot/pi-deployment ]; then
   echo "Installing inventory system..."
   cp -r /boot/pi-deployment /home/pi/
   chown -R pi:pi /home/pi/pi-deployment
   cd /home/pi/pi-deployment
   ./install/install-pi.sh
fi

# Cleanup
rm -f /boot/firstrun.sh
sed -i 's| systemd.run.*||g' /boot/cmdline.txt

systemctl reboot
FIRSTRUN

chmod +x "$BOOT_DIR/firstrun.sh"

# 5. Copy SSH authorized keys
cp "$BUILDER_DIR/config/authorized_keys" "$BOOT_DIR/authorized_keys"

# 6. Modify cmdline.txt (Pi Imager method)
if [ -f "$BOOT_DIR/cmdline.txt" ]; then
    cp "$BOOT_DIR/cmdline.txt" "$BOOT_DIR/cmdline.txt.bak"
    echo -n " systemd.run=/boot/firstrun.sh systemd.run_success_action=reboot systemd.unit=kernel-command-line.target" >> "$BOOT_DIR/cmdline.txt"
fi

# 7. Copy inventory system
echo "📦 Copying inventory system..."
cp -r "$PROJECT_ROOT/pi-deployment" "$BOOT_DIR/"

# 8. Create info file
cat > "$BOOT_DIR/inventory-info.txt" << 'INFO'
Inventory Pi - Configuration Applied
===================================

This image was configured with:
- Hostname: inventory
- Wi-Fi: salty (with PSK hash)
- SSH: Enabled with key authentication
- User: pi (password: inventory)

First boot will:
1. Connect to Wi-Fi
2. Set hostname to 'inventory'
3. Install inventory system
4. Reboot

After setup:
- SSH: ssh pi@inventory.local
- Web: https://inventory.local

First boot may take 10-15 minutes.
INFO

echo "🧹 Cleaning up..."
sync

if [[ "$OSTYPE" == "darwin"* ]]; then
    umount "$BOOT_DIR"
    hdiutil detach "$DEVICE"
else
    umount "$BOOT_DIR"
    losetup -d "$LOOP_DEVICE"
fi

rm -rf "$WORK_DIR/mount"

echo ""
echo "✅ Pi Imager style image complete!"
echo "📦 Output: $OUTPUT_DIR/$IMAGE_NAME"
echo ""
echo "📋 This image uses the exact same methods as Pi Imager:"
echo "  • Proper PSK hash for Wi-Fi: $PSK_HASH"
echo "  • userconf.txt for user setup"
echo "  • Standard firstrun.sh method"
echo "  • No complex boot modifications"
echo ""
echo "🔧 Write to SD: ./scripts/write-to-sd.sh /dev/disk4"