#!/bin/bash
# package-network-install.sh
# Creates a deployable package for BTBerryWifi network installation

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PACKAGE_DIR="/tmp/network-install-package"

echo "📦 Creating BTBerryWifi network installation package..."

# Clean and create package directory
rm -rf "$PACKAGE_DIR"
mkdir -p "$PACKAGE_DIR"

echo "📋 Copying installation files..."

# Copy core files needed for BTBerryWifi
cp "$SCRIPT_DIR/install.sh" "$PACKAGE_DIR/"
cp "$SCRIPT_DIR/btwifiset.py" "$PACKAGE_DIR/"
cp "$SCRIPT_DIR/ble-dbus.conf" "$PACKAGE_DIR/"
cp "$SCRIPT_DIR/wpa_supplicant.conf" "$PACKAGE_DIR/"

# Copy diagnostic and troubleshooting tools
cp "$SCRIPT_DIR/fix-network-stability.sh" "$PACKAGE_DIR/"
cp "$SCRIPT_DIR/diagnose-network-failure.sh" "$PACKAGE_DIR/"
cp "$SCRIPT_DIR/verify-fixes.sh" "$PACKAGE_DIR/"
cp "$SCRIPT_DIR/test-wifi-scan.sh" "$PACKAGE_DIR/"
cp "$SCRIPT_DIR/NETWORK-TROUBLESHOOTING.md" "$PACKAGE_DIR/"

# Create a focused network-only install script
cat > "$PACKAGE_DIR/network-install.sh" << 'EOF'
#!/bin/bash
# network-install.sh - Focused BTBerryWifi installation for network testing

set -e

# This script must be run as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root or with sudo"
    exit 1
fi

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

echo "🔧 Installing BTBerryWifi Network Configuration..."
echo "📍 Working directory: $SCRIPT_DIR"

# Install BTBerryWifi service using official installer
echo "📥 Installing BTBerryWifi service..."
curl -L https://raw.githubusercontent.com/nksan/Rpi-SetWiFi-viaBluetooth/main/btwifisetInstall.sh | bash

# Copy D-Bus configuration
echo "🔧 Installing D-Bus configuration..."
cp "$SCRIPT_DIR/ble-dbus.conf" /etc/dbus-1/system.d/

# Configure Bluetooth service for BLE
echo "📶 Configuring Bluetooth for BLE support..."
cp /lib/systemd/system/bluetooth.service /etc/systemd/system/
sed -i 's|ExecStart=/usr/libexec/bluetooth/bluetoothd|ExecStart=/usr/libexec/bluetooth/bluetoothd --experimental -P battery|' /etc/systemd/system/bluetooth.service

# Create Bluetooth security timer
echo "⏰ Setting up Bluetooth security timer..."
tee /etc/systemd/system/bluetooth-security-timer.service > /dev/null << 'TIMER_EOF'
[Unit]
Description=Bluetooth Security Timer - Disables Bluetooth after 10 minutes
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

# CRITICAL: Network service conflict resolution
echo "🚨 Resolving network service conflicts..."

# Install required packages first
apt update
apt install -y network-manager wireless-tools wpasupplicant rfkill

# Check what network services are currently enabled
echo "📊 Current network service status:"
systemctl is-enabled NetworkManager 2>/dev/null || echo "NetworkManager: not installed"
systemctl is-enabled systemd-networkd.service 2>/dev/null || echo "systemd-networkd: disabled" 
systemctl is-enabled dhcpcd.service 2>/dev/null || echo "dhcpcd: not found"

# Disable ALL conflicting network services before enabling NetworkManager
echo "🛑 Disabling conflicting network services..."
systemctl stop dhcpcd.service 2>/dev/null || true
systemctl disable dhcpcd.service 2>/dev/null || true  
systemctl mask dhcpcd.service 2>/dev/null || true

systemctl stop systemd-networkd.service 2>/dev/null || true
systemctl disable systemd-networkd.service 2>/dev/null || true
systemctl mask systemd-networkd.service 2>/dev/null || true
systemctl disable systemd-networkd.socket 2>/dev/null || true

# Clean up any interface-specific wpa_supplicant services
systemctl stop wpa_supplicant@wlan0.service 2>/dev/null || true
systemctl disable wpa_supplicant@wlan0.service 2>/dev/null || true
systemctl mask wpa_supplicant@wlan0.service 2>/dev/null || true

# Kill any running conflicting processes
pkill dhcpcd || true
pkill -f "wpa_supplicant.*-i.*wlan0" || true
sleep 2

# Configure NetworkManager as the EXCLUSIVE network manager
echo "🔧 Setting up NetworkManager as exclusive network manager..."

# Ensure WiFi hardware is available
if [ -e /sys/class/net/wlan0 ]; then
    echo "✅ WiFi interface wlan0 found"
    rfkill unblock wifi || true
    ip link set wlan0 up || true
else
    echo "⚠️ No WiFi interface found"
fi

# Enable and start NetworkManager
systemctl enable NetworkManager
systemctl start NetworkManager
sleep 5

# Enable wpa_supplicant as D-Bus service (required for NetworkManager)
systemctl enable wpa_supplicant.service
systemctl start wpa_supplicant.service
sleep 2

# Configure NetworkManager for WiFi management
mkdir -p /etc/NetworkManager/conf.d
cat > /etc/NetworkManager/conf.d/99-wifi-backend.conf << 'NM_EOF'
[device]
wifi.backend=wpa_supplicant
wifi.scan-rand-mac-address=no

[main]
no-auto-default=*
NM_EOF

# Force NetworkManager to manage all interfaces
nmcli radio wifi on 2>/dev/null || true
nmcli device set wlan0 managed yes 2>/dev/null || true
nmcli device set eth0 managed yes 2>/dev/null || true

# Test network functionality
echo "🧪 Testing network functionality..."
sleep 5

echo "📊 Network interface status:"
ip addr show | grep -E "eth0|wlan0" -A 2 || true

echo "📊 NetworkManager device status:"
nmcli device status || true

echo "📊 Service status:"
echo "  NetworkManager: $(systemctl is-active NetworkManager 2>/dev/null || echo 'inactive')"
echo "  wpa_supplicant: $(systemctl is-active wpa_supplicant.service 2>/dev/null || echo 'inactive')"
echo "  systemd-networkd: $(systemctl is-active systemd-networkd.service 2>/dev/null || echo 'masked')"
echo "  dhcpcd: $(systemctl is-active dhcpcd.service 2>/dev/null || echo 'masked')"

# Install our fixed BTBerryWifi script
echo "📱 Installing fixed BTBerryWifi script..."
cp "$SCRIPT_DIR/btwifiset.py" /usr/local/btwifiset/

# Install diagnostic tools
echo "🔍 Installing diagnostic tools..."
cp "$SCRIPT_DIR"/*.sh /usr/local/bin/ 2>/dev/null || true
chmod +x /usr/local/bin/*.sh 2>/dev/null || true

# Start BTBerryWifi
echo "🚀 Starting BTBerryWifi service..."
systemctl daemon-reload
systemctl enable btwifiset.service
systemctl start btwifiset.service

echo ""
echo "✅ BTBerryWifi network installation completed!"
echo ""
echo "🔍 Final system status:"
echo "  Ethernet: $(ip addr show eth0 | grep 'inet ' | awk '{print $2}' || echo 'No IP assigned')"
echo "  WiFi: $(ip addr show wlan0 | grep 'inet ' | awk '{print $2}' || echo 'No IP assigned')"
echo "  BTBerryWifi: $(systemctl is-active btwifiset.service 2>/dev/null || echo 'inactive')"
echo ""
echo "🧪 CRITICAL TEST: Please reboot now and verify Ethernet comes back up!"
echo "    If Ethernet fails after reboot, we have more conflicts to resolve."
echo ""

EOF

chmod +x "$PACKAGE_DIR/network-install.sh"

# Create deployment script
cat > "$PACKAGE_DIR/deploy-to-pi.sh" << 'EOF'
#!/bin/bash
# deploy-to-pi.sh - Deploy the network installation package to Pi

set -e

PI_HOST="${1:-192.168.43.200}"
PI_USER="${2:-pi}"

if [ "$#" -eq 0 ]; then
    echo "Usage: $0 [pi_host] [pi_user]"
    echo "Default: $0 192.168.43.200 pi"
    echo ""
    echo "Will deploy to: $PI_USER@$PI_HOST"
    read -p "Press Enter to continue or Ctrl+C to cancel..."
fi

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

echo "📡 Deploying BTBerryWifi installation to $PI_USER@$PI_HOST..."

# Create remote directory
ssh "$PI_USER@$PI_HOST" "mkdir -p ~/network-install"

# Copy all files
echo "📂 Copying installation files..."
scp "$SCRIPT_DIR"/* "$PI_USER@$PI_HOST:~/network-install/"

echo "✅ Files deployed successfully!"
echo ""
echo "🚀 To install, SSH to the Pi and run:"
echo "    ssh $PI_USER@$PI_HOST"
echo "    cd ~/network-install"
echo "    sudo ./network-install.sh"
echo ""
echo "📋 After installation, test with:"
echo "    sudo reboot"
echo "    # Wait for boot, then test Ethernet connectivity"
echo "    # Test BTBerryWifi with mobile app"

EOF

chmod +x "$PACKAGE_DIR/deploy-to-pi.sh"

# Create README
cat > "$PACKAGE_DIR/README.md" << 'EOF'
# BTBerryWifi Network Installation Package

This package contains everything needed to install and configure BTBerryWifi on a Raspberry Pi with proper network stability.

## Files:
- `network-install.sh` - Main installation script (run as root)  
- `deploy-to-pi.sh` - Deploy package to Pi remotely
- `btwifiset.py` - Fixed BTBerryWifi script with NetworkManager support
- `ble-dbus.conf` - D-Bus configuration for Bluetooth
- Various diagnostic and troubleshooting tools

## Installation:
1. Deploy to Pi: `./deploy-to-pi.sh [pi_ip] [username]`
2. SSH to Pi: `ssh pi@[pi_ip]`  
3. Install: `cd ~/network-install && sudo ./network-install.sh`
4. Test: `sudo reboot` and verify Ethernet/WiFi work
5. Test BTBerryWifi with mobile app

## Critical Fix:
This installation resolves service conflicts between NetworkManager, systemd-networkd, and dhcpcd that cause network failures on reboot.
EOF

echo "📦 Package created at: $PACKAGE_DIR"
echo ""
echo "📋 Package contents:"
ls -la "$PACKAGE_DIR"
echo ""
echo "🚀 To deploy to Pi:"
echo "    cd $PACKAGE_DIR"
echo "    ./deploy-to-pi.sh [pi_ip] [username]"
echo ""
echo "🧪 Then SSH to Pi and run:"
echo "    cd ~/network-install"  
echo "    sudo ./network-install.sh"