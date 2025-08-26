#!/bin/bash
# prep-network-simple.sh - Deploy network installation directly to Pi

set -e

echo "🚀 Preparing BTBerryWifi network installation on Pi..."

# Just create the installation script remotely instead of sending files
pi run --pi epi1 "
cd /tmp
cat > network-install.sh << 'INSTALL_EOF'
#!/bin/bash
set -e

if [ \"\$EUID\" -ne 0 ]; then
    echo \"Must run as root\"
    exit 1
fi

echo \"🔧 Installing BTBerryWifi with network fixes...\"

# Install BTBerryWifi service
echo \"📥 Installing BTBerryWifi...\"
curl -s -L https://raw.githubusercontent.com/nksan/Rpi-SetWiFi-viaBluetooth/main/btwifisetInstall.sh | bash

# Configure Bluetooth for BLE
echo \"📶 Configuring Bluetooth...\"
cp /lib/systemd/system/bluetooth.service /etc/systemd/system/
sed -i 's|ExecStart=/usr/libexec/bluetooth/bluetoothd|ExecStart=/usr/libexec/bluetooth/bluetoothd --experimental -P battery|' /etc/systemd/system/bluetooth.service

# Create security timer
cat > /etc/systemd/system/bluetooth-security-timer.service << 'TIMER_EOF'
[Unit]
Description=Bluetooth Security Timer
After=bluetooth.service
Wants=bluetooth.service

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'sleep 600 && systemctl stop bluetooth && systemctl disable bluetooth'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
TIMER_EOF

systemctl enable bluetooth-security-timer.service

# CRITICAL: Fix network service conflicts
echo \"🚨 Fixing network conflicts...\"
apt update -qq
apt install -y -qq network-manager wireless-tools wpasupplicant rfkill

# Stop and disable conflicting services
systemctl stop dhcpcd.service 2>/dev/null || true
systemctl disable dhcpcd.service 2>/dev/null || true
systemctl mask dhcpcd.service 2>/dev/null || true

systemctl stop systemd-networkd.service 2>/dev/null || true  
systemctl disable systemd-networkd.service 2>/dev/null || true
systemctl mask systemd-networkd.service 2>/dev/null || true
systemctl disable systemd-networkd.socket 2>/dev/null || true

systemctl stop wpa_supplicant@wlan0.service 2>/dev/null || true
systemctl disable wpa_supplicant@wlan0.service 2>/dev/null || true
systemctl mask wpa_supplicant@wlan0.service 2>/dev/null || true

# Kill conflicting processes
pkill dhcpcd 2>/dev/null || true
pkill -f \"wpa_supplicant.*-i.*wlan0\" 2>/dev/null || true
sleep 2

# Configure NetworkManager as exclusive manager
echo \"🔧 Configuring NetworkManager...\"
if [ -e /sys/class/net/wlan0 ]; then
    rfkill unblock wifi 2>/dev/null || true
    ip link set wlan0 up 2>/dev/null || true
fi

systemctl enable NetworkManager
systemctl start NetworkManager
sleep 5

systemctl enable wpa_supplicant.service
systemctl start wpa_supplicant.service
sleep 2

# Create NetworkManager config
mkdir -p /etc/NetworkManager/conf.d
cat > /etc/NetworkManager/conf.d/99-wifi-backend.conf << 'NM_EOF'
[device]
wifi.backend=wpa_supplicant
wifi.scan-rand-mac-address=no

[main]
no-auto-default=*
NM_EOF

# Force interface management
nmcli radio wifi on 2>/dev/null || true
nmcli device set wlan0 managed yes 2>/dev/null || true
nmcli device set eth0 managed yes 2>/dev/null || true

# Start BTBerryWifi
echo \"🚀 Starting BTBerryWifi...\"
systemctl daemon-reload
systemctl enable btwifiset.service
systemctl start btwifiset.service

echo \"✅ Installation complete!\"
echo \"📊 Status:\"
echo \"  NetworkManager: \$(systemctl is-active NetworkManager)\"
echo \"  BTBerryWifi: \$(systemctl is-active btwifiset.service)\" 
echo \"  systemd-networkd: \$(systemctl is-active systemd-networkd.service 2>/dev/null || echo 'masked')\"
echo \"\"
echo \"🧪 CRITICAL: Reboot test required to verify Ethernet stability\"
INSTALL_EOF

chmod +x network-install.sh
echo \"Installation script created at /tmp/network-install.sh\"
"

echo "✅ Network installation script prepared on Pi"
echo "🚀 Ready to run: ./deploy-network.sh"