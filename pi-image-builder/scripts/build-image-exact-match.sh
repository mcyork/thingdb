#!/bin/bash

echo "🥧 Pi Inventory Image - Exact Pi Imager Match"
echo "============================================="
echo "This exactly matches what Pi Imager creates"
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
IMAGE_NAME="inventory-pi-exact-$(date +%Y%m%d).img"

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

echo "⚙️ Configuring boot partition (Exact Pi Imager match)..."

# 1. Enable SSH (empty file)
touch "$BOOT_DIR/ssh"

# 2. Wi-Fi config (PSK is empty - set in firstrun.sh)
cat > "$BOOT_DIR/wpa_supplicant.conf" << 'EOF'
country=US
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1

network={
	ssid="salty"
	psk=
}
EOF

# 3. Generate PSK hash for firstrun.sh (special format)
# Pi Imager uses a different hash format than wpa_passphrase
PSK_HASH=$(echo -n "$WIFI_PASSWORD" | openssl dgst -sha256 | cut -d' ' -f2)

# 4. Create firstrun.sh (Pi Imager style)
cat > "$BOOT_DIR/firstrun.sh" << FIRSTRUN
#!/bin/bash

set +e

CURRENT_HOSTNAME=\`cat /etc/hostname | tr -d " \t\n\r"\`
if [ -f /usr/lib/raspberrypi-sys-mods/imager_custom ]; then
   /usr/lib/raspberrypi-sys-mods/imager_custom set_hostname inventory
else
   echo inventory >/etc/hostname
   sed -i "s/127.0.1.1.*\$CURRENT_HOSTNAME/127.0.1.1\tinventory/g" /etc/hosts
fi

FIRSTUSER=\`getent passwd 1000 | cut -d: -f1\`
FIRSTUSERHOME=\`getent passwd 1000 | cut -d: -f6\`

# Setup SSH keys
if [ -f /usr/lib/raspberrypi-sys-mods/imager_custom ]; then
   /usr/lib/raspberrypi-sys-mods/imager_custom enable_ssh -k 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCn8IW5zsi7oNEjOPrCwHXtV3Zb9eC33Mua06n+c6ZyFnDT+KowrfFAEcomYtiR6Jmr+o5zQlLgzX5wd706zgGHlv1+L7DEOTBo+lpqbyXbwECTI4osfpAZYQVdUAWUw6b6PaZttVTIhmPpTU9drOepxcege/8f3SpTv2WBUjz7H+3rj7FpjRocQLc7kz8azI2SAPijm1t365h3rAmRtdEQ8RS6iL4OOH1wvAUVw2SDpakVH5zeUx4qZ7KJr3nT8oA8GF4zMr+jWVFweSFKrGHVTfRQ0ToOelR2djf/LJa2N/NmoW8csYBuTENg/g7QusMLsc8a8HwjnbeyjyM/qjRr3bvSc+KFLD4uKOMNqLgJIluXhKAjLqHOKCwZiKi1VJrHQ/fu3HhWCVNk31m+8uWAs4MbRJiNe1CdM76pOR8XsO62uuwbUtWwww1GZ4ruB3FBxF8wmvQiUjz8i+gNoeTv1kI/8kal6aVbmHUQXoPmcIKBrUmcpJkihcRIoPZuNlc= ianmccutcheon@Ians-MacBook-Pro.local'
else
   install -o "\$FIRSTUSER" -m 700 -d "\$FIRSTUSERHOME/.ssh"
   install -o "\$FIRSTUSER" -m 600 <(printf "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCn8IW5zsi7oNEjOPrCwHXtV3Zb9eC33Mua06n+c6ZyFnDT+KowrfFAEcomYtiR6Jmr+o5zQlLgzX5wd706zgGHlv1+L7DEOTBo+lpqbyXbwECTI4osfpAZYQVdUAWUw6b6PaZttVTIhmPpTU9drOepxcege/8f3SpTv2WBUjz7H+3rj7FpjRocQLc7kz8azI2SAPijm1t365h3rAmRtdEQ8RS6iL4OOH1wvAUVw2SDpakVH5zeUx4qZ7KJr3nT8oA8GF4zMr+jWVFweSFKrGHVTfRQ0ToOelR2djf/LJa2N/NmoW8csYBuTENg/g7QusMLsc8a8HwjnbeyjyM/qjRr3bvSc+KFLD4uKOMNqLgJIluXhKAjLqHOKCwZiKi1VJrHQ/fu3HhWCVNk31m+8uWAs4MbRJiNe1CdM76pOR8XsO62uuwbUtWwww1GZ4ruB3FBxF8wmvQiUjz8i+gNoeTv1kI/8kal6aVbmHUQXoPmcIKBrUmcpJkihcRIoPZuNlc= ianmccutcheon@Ians-MacBook-Pro.local\n") "\$FIRSTUSERHOME/.ssh/authorized_keys"
   echo 'PasswordAuthentication no' >>/etc/ssh/sshd_config
   systemctl enable ssh
fi

# User setup - keep it as 'pi' user for simplicity
if [ -f /usr/lib/userconf-pi/userconf ]; then
   /usr/lib/userconf-pi/userconf 'pi' '\$5\$hQzYe/\$Kv8OjdcPj.uRQPvJH1MpQpYfPrzPPCfhYlSfxhPWaH3'
else
   echo "pi:inventory" | chpasswd
fi

# Wi-Fi setup with PSK hash
if [ -f /usr/lib/raspberrypi-sys-mods/imager_custom ]; then
   /usr/lib/raspberrypi-sys-mods/imager_custom set_wlan 'salty' '${PSK_HASH}' 'US'
else
cat >/etc/wpa_supplicant/wpa_supplicant.conf <<'WPAEOF'
country=US
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
ap_scan=1

update_config=1
network={
	ssid="salty"
	psk="${PSK_HASH}"
}
WPAEOF
   chmod 600 /etc/wpa_supplicant/wpa_supplicant.conf
   rfkill unblock wifi
   for filename in /var/lib/systemd/rfkill/*:wlan ; do
       echo 0 > \$filename
   done
fi

# Install inventory system
if [ -d /boot/pi-deployment ]; then
   echo "Installing inventory system..."
   cp -r /boot/pi-deployment /home/pi/
   chown -R pi:pi /home/pi/pi-deployment
   cd /home/pi/pi-deployment
   ./install/install-pi.sh
fi

rm -f /boot/firstrun.sh
sed -i 's| systemd.run.*||g' /boot/cmdline.txt
exit 0
FIRSTRUN

chmod +x "$BOOT_DIR/firstrun.sh"

# 5. Modify cmdline.txt (add regulatory domain and firstrun)
if [ -f "$BOOT_DIR/cmdline.txt" ]; then
    # Backup original
    cp "$BOOT_DIR/cmdline.txt" "$BOOT_DIR/cmdline.txt.bak"
    
    # Add firstrun and regulatory domain
    echo -n " systemd.run=/boot/firstrun.sh systemd.run_success_action=reboot systemd.unit=kernel-command-line.target cfg80211.ieee80211_regdom=US" >> "$BOOT_DIR/cmdline.txt"
fi

# 6. Copy inventory system
echo "📦 Copying inventory system..."
if [ -d "$PROJECT_ROOT/pi-deployment" ]; then
    cp -r "$PROJECT_ROOT/pi-deployment" "$BOOT_DIR/"
    echo "  ✅ Copied pi-deployment"
fi

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
echo "✅ Exact Pi Imager match image complete!"
echo "📦 Output: $OUTPUT_DIR/$IMAGE_NAME"
echo ""
echo "📋 This image exactly matches Pi Imager's method:"
echo "  • Empty PSK in wpa_supplicant.conf"
echo "  • PSK hash set in firstrun.sh"
echo "  • Regulatory domain in cmdline.txt"
echo "  • Uses imager_custom helper scripts"
echo ""
echo "🔧 Write to SD: ./scripts/write-to-sd.sh /dev/disk4"