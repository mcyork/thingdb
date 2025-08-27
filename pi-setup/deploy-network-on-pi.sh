#!/bin/bash
# deploy-network-on-pi.sh - Run directly on Pi to install BTBerryWifi and network fixes
# This script is designed to be run ON the Pi itself, not from the host

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run as root (use sudo)"
    exit 1
fi

print_status "🚀 Starting BTBerryWifi network installation on $(hostname)"
echo "==========================================="

# Update package lists
print_status "📦 Updating package lists..."
apt-get update -qq

# Install network prerequisites
print_status "📥 Installing network prerequisites..."
apt-get install -y -qq network-manager wireless-tools wpasupplicant rfkill || true

# Install Python dependencies first
print_status "📦 Installing Python dependencies..."
apt-get install -y -qq python3-cryptography python3-gi python3-dbus || true

# Install BTBerryWifi
print_status "📥 Installing BTBerryWifi service..."
curl -s -L https://raw.githubusercontent.com/nksan/Rpi-SetWiFi-viaBluetooth/main/btwifisetInstall.sh | bash

# Configure Bluetooth for BLE
print_status "📶 Configuring Bluetooth..."
if [ ! -f /etc/systemd/system/bluetooth.service ]; then
    cp /lib/systemd/system/bluetooth.service /etc/systemd/system/ 2>/dev/null || true
fi
sed -i 's|ExecStart=/usr/libexec/bluetooth/bluetoothd|ExecStart=/usr/libexec/bluetooth/bluetoothd --experimental -P battery|' /etc/systemd/system/bluetooth.service 2>/dev/null || true

# Fix network service conflicts
print_status "🚨 Fixing network service conflicts..."

# Stop and disable conflicting services
systemctl stop dhcpcd.service 2>/dev/null || true
systemctl disable dhcpcd.service 2>/dev/null || true
systemctl mask dhcpcd.service 2>/dev/null || true

systemctl stop systemd-networkd.service 2>/dev/null || true  
systemctl disable systemd-networkd.service 2>/dev/null || true
systemctl mask systemd-networkd.service 2>/dev/null || true

systemctl stop wpa_supplicant@wlan0.service 2>/dev/null || true
systemctl disable wpa_supplicant@wlan0.service 2>/dev/null || true
systemctl mask wpa_supplicant@wlan0.service 2>/dev/null || true

# Kill conflicting processes
pkill dhcpcd 2>/dev/null || true
pkill -f "wpa_supplicant.*-i.*wlan0" 2>/dev/null || true
sleep 2

# Configure NetworkManager
print_status "🔧 Configuring NetworkManager..."
mkdir -p /etc/NetworkManager/conf.d
cat > /etc/NetworkManager/conf.d/99-wifi-backend.conf << 'NM_EOF'
[device]
wifi.backend=wpa_supplicant
wifi.scan-rand-mac-address=no

[main]
no-auto-default=*
NM_EOF

# Create NetworkManager override for proper startup
print_status "⚙️ Creating service overrides..."
mkdir -p /etc/systemd/system/NetworkManager.service.d
cat > /etc/systemd/system/NetworkManager.service.d/override.conf << 'EOF'
[Unit]
After=network-pre.target dbus.service
Before=network.target network-online.target
Wants=network.target

[Service]
ExecStartPre=/bin/bash -c 'sleep 2; rfkill unblock wifi 2>/dev/null || true'
Restart=on-failure
RestartSec=5
EOF

# Ensure BTBerryWifi starts after NetworkManager
mkdir -p /etc/systemd/system/btwifiset.service.d
cat > /etc/systemd/system/btwifiset.service.d/override.conf << 'EOF'
[Unit]
After=NetworkManager.service network-online.target bluetooth.service
Wants=NetworkManager.service
Requires=bluetooth.service

[Service]
ExecStartPre=/bin/bash -c 'until systemctl is-active NetworkManager; do sleep 2; done'
ExecStartPre=/bin/bash -c 'sleep 5'
Restart=on-failure
RestartSec=10
Environment="PYTHONUNBUFFERED=1"
EOF

# Create network interface protection service
cat > /etc/systemd/system/network-interface-protection.service << 'EOF'
[Unit]
Description=Protect Network Interfaces from being unmanaged
After=NetworkManager.service
Wants=NetworkManager.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=/bin/bash -c 'sleep 10'
ExecStart=/bin/bash -c 'nmcli device set eth0 managed yes 2>/dev/null || true; nmcli device set wlan0 managed yes 2>/dev/null || true'
ExecStart=/bin/bash -c 'ip link set eth0 up 2>/dev/null || true'

[Install]
WantedBy=multi-user.target
EOF

# Ensure WPA Supplicant is configured properly
mkdir -p /etc/systemd/system/wpa_supplicant.service.d
cat > /etc/systemd/system/wpa_supplicant.service.d/override.conf << 'EOF'
[Unit]
After=dbus.service
Before=NetworkManager.service

[Service]
ExecStartPre=/bin/bash -c 'rfkill unblock wifi 2>/dev/null || true'
EOF

# Enable services
print_status "🚀 Enabling services..."
systemctl daemon-reload
systemctl enable NetworkManager 2>/dev/null || true
systemctl enable wpa_supplicant.service 2>/dev/null || true
systemctl enable bluetooth.service 2>/dev/null || true
systemctl enable btwifiset.service 2>/dev/null || true
systemctl enable network-interface-protection.service 2>/dev/null || true

# Start/restart services in correct order
print_warning "⚠️ Network may briefly disconnect during service restart..."
systemctl restart NetworkManager || true
sleep 3
systemctl restart wpa_supplicant.service || true
sleep 2
systemctl restart bluetooth.service || true
sleep 2
systemctl restart btwifiset.service || true

# Force interface management
if [ -e /sys/class/net/wlan0 ]; then
    rfkill unblock wifi 2>/dev/null || true
    ip link set wlan0 up 2>/dev/null || true
fi

nmcli radio wifi on 2>/dev/null || true
nmcli device set wlan0 managed yes 2>/dev/null || true
nmcli device set eth0 managed yes 2>/dev/null || true

# Try to reconnect ethernet
print_status "Reconnecting ethernet..."
nmcli device connect eth0 2>/dev/null || true

print_success "✅ Installation complete!"
echo ""
print_status "📊 Current Status:"
echo "  NetworkManager: $(systemctl is-active NetworkManager 2>/dev/null || echo 'inactive')"
echo "  Bluetooth: $(systemctl is-active bluetooth 2>/dev/null || echo 'inactive')"
echo "  BTBerryWifi: $(systemctl is-active btwifiset.service 2>/dev/null || echo 'inactive')" 
echo "  systemd-networkd: $(systemctl is-active systemd-networkd.service 2>/dev/null || echo 'masked')"
echo "  Ethernet: $(ip addr show eth0 2>/dev/null | grep 'inet ' | awk '{print $2}' || echo 'No IP')"
echo ""
print_warning "⚠️ IMPORTANT: A reboot is strongly recommended!"
print_warning "   Run: sudo reboot"
echo ""
print_status "After reboot:"
echo "  - BTBerryWifi will be available as '$(hostname)' via Bluetooth"
echo "  - Default password: inventory"
echo "  - Ethernet should reconnect automatically"
echo ""
print_warning "If ethernet doesn't reconnect after reboot, use serial console or keyboard to run:"
echo "  sudo nmcli device connect eth0"