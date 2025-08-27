#!/bin/bash
# prep-network-simple.sh - Deploy network installation directly to Pi

set -e

# Show usage if help is requested
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo "Usage: $0 [PI_TARGET]"
    echo ""
    echo "Deploy BTBerryWifi network installation to specified Raspberry Pi"
    echo ""
    echo "Arguments:"
    echo "  PI_TARGET    Name of the Pi to target (default: pi2)"
    echo ""
    echo "Examples:"
    echo "  $0           # Use default pi2"
    echo "  $0 pi1      # Target pi1"
    echo "  $0 pi2      # Target pi2"
    echo "  $0 epi1     # Target epi1"
    echo ""
    echo "Available Pis:"
    pi list
    exit 0
fi

# Get Pi target from command line argument, default to pi2
PI_TARGET=${1:-pi2}

echo "🚀 Preparing BTBerryWifi network installation on Pi: $PI_TARGET"

# Validate Pi target
if ! pi list | grep -q "^$PI_TARGET"; then
    echo "❌ Error: Pi '$PI_TARGET' not found in configuration"
    echo "Available Pis:"
    pi list
    exit 1
fi

# Check if Pi is online
if ! pi status "$PI_TARGET" | grep -q "ONLINE"; then
    echo "❌ Error: Pi '$PI_TARGET' is not online"
    echo "Current status:"
    pi status "$PI_TARGET"
    exit 1
fi

echo "✅ Pi '$PI_TARGET' is online and ready"

# Just create the installation script remotely instead of sending files
pi run --pi "$PI_TARGET" "
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

# CRITICAL: Connect eth0 to restore Ethernet connectivity
echo \"🔌 Connecting Ethernet interface...\"
if [ -e /sys/class/net/eth0 ]; then
    nmcli device connect eth0 2>/dev/null || true
    sleep 3
    # Verify eth0 has an IP
    if ! ip addr show eth0 | grep -q \"inet \"; then
        echo \"⚠️  Warning: eth0 still has no IP, attempting manual connection...\"
        nmcli device connect eth0
        sleep 5
    fi
fi

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
echo \"  eth0 IP: \$(ip addr show eth0 | grep 'inet ' | awk '{print \$2}' || echo 'No IP')\"
echo \"\"
echo \"🧪 CRITICAL: Reboot test required to verify Ethernet stability\"
INSTALL_EOF

chmod +x network-install.sh
echo \"Installation script created at /tmp/network-install.sh\"
"

echo "✅ Network installation script prepared on Pi: $PI_TARGET"
echo "🚀 Ready to run: ./deploy-network.sh $PI_TARGET"