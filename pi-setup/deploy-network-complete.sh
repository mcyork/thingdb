#!/bin/bash
# deploy-network-complete.sh - Complete network and serial deployment for Raspberry Pi
# Deploys BTBerryWifi, NetworkManager configuration, and serial agent

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

# Check for Pi name argument
if [ $# -lt 1 ]; then
    echo "Usage: $0 <pi-name> [--skip-serial]"
    echo "Example: $0 pi1"
    echo "         $0 pi2 --skip-serial"
    exit 1
fi

PI_NAME="$1"
SKIP_SERIAL=false

if [ "${2:-}" = "--skip-serial" ]; then
    SKIP_SERIAL=true
fi

# Paths
PI_SERIAL_PATH="/Users/ianmccutcheon/projects/pi-serial"
PI_SETUP_PATH="$(dirname "$0")"

print_status "🚀 Starting complete network deployment for $PI_NAME"
echo "==========================================="

# Check if we're running on the Pi itself or from host
if [ -f "/boot/config.txt" ] || [ -f "/boot/firmware/config.txt" ]; then
    # We're running directly on the Pi
    print_status "Running directly on Pi - skipping connectivity check"
    IS_LOCAL=true
else
    # We're running from host, check Pi connectivity
    print_status "Checking Pi connectivity..."
    if pi status | grep -q "$PI_NAME.*ONLINE"; then
        print_success "$PI_NAME is online"
    else
        print_error "$PI_NAME is not accessible via SSH"
        print_warning "Please ensure the Pi is connected and accessible"
        exit 1
    fi
    IS_LOCAL=false
fi

# Step 1: Deploy Serial Agent (unless skipped and if running from host)
if [ "$SKIP_SERIAL" = false ] && [ "$IS_LOCAL" = false ]; then
    print_status "📡 Deploying Serial Agent..."
    
    # Check if pi-serial exists
    if [ ! -d "$PI_SERIAL_PATH" ]; then
        print_error "pi-serial directory not found at $PI_SERIAL_PATH"
        print_warning "Serial agent deployment will be skipped"
    else
        cd "$PI_SERIAL_PATH"
        
        # Build the serial agent package if needed
        if [ ! -f "dist/pi-serial-agent.tar.gz" ]; then
            print_status "Building serial agent package..."
            if [ -f "scripts/build_pi_agent_tar.sh" ]; then
                ./scripts/build_pi_agent_tar.sh
            else
                print_warning "Build script not found, skipping serial agent"
            fi
        fi
        
        # Deploy serial agent
        if [ -f "dist/pi-serial-agent.tar.gz" ]; then
            print_status "Deploying serial agent to $PI_NAME..."
            # Deploy with ttyAMA0 as default (most common for Pi UART)
            if [ -f "scripts/deploy_pi_agent.sh" ]; then
                ./scripts/deploy_pi_agent.sh --pi "$PI_NAME" --tty ttyAMA0
                print_success "Serial agent deployed"
            else
                # Manual deployment if script doesn't exist
                pi send --pi "$PI_NAME" dist/pi-serial-agent.tar.gz /tmp/pi-serial-agent.tar.gz
                pi run-stream --pi "$PI_NAME" "
                    sudo rm -rf /tmp/pi-serial-agent && 
                    sudo mkdir -p /tmp/pi-serial-agent && 
                    sudo tar -xzf /tmp/pi-serial-agent.tar.gz -C /tmp/pi-serial-agent && 
                    cd /tmp/pi-serial-agent && 
                    sudo TTY=ttyAMA0 bash ./install.sh
                "
                print_success "Serial agent deployed (manual method)"
            fi
        else
            print_warning "Serial agent package not found, skipping"
        fi
    fi
elif [ "$IS_LOCAL" = true ]; then
    print_warning "Serial agent must be deployed from host machine, skipping"
else
    print_warning "Skipping serial agent deployment (--skip-serial flag)"
fi

# Step 2: Create and deploy network installation script
print_status "📱 Preparing BTBerryWifi network installation..."

if [ "$IS_LOCAL" = false ]; then
    cd "$PI_SETUP_PATH"
fi

# Create the installation script
if [ "$IS_LOCAL" = true ]; then
    # Running directly on Pi - create script locally
    cat > /tmp/network-install.sh << 'INSTALL_EOF'
#!/bin/bash
set -e

if [ \"\$EUID\" -ne 0 ]; then
    echo \"Must run as root\"
    exit 1
fi

echo \"🔧 Installing BTBerryWifi with network fixes...\"

# Update package lists
echo \"📦 Updating package lists...\"
apt-get update -qq

# Install network prerequisites
echo \"📥 Installing network prerequisites...\"
apt-get install -y -qq network-manager wireless-tools wpasupplicant rfkill

# Install BTBerryWifi
echo \"📥 Installing BTBerryWifi...\"
curl -s -L https://raw.githubusercontent.com/nksan/Rpi-SetWiFi-viaBluetooth/main/btwifisetInstall.sh | bash

# Install Python dependencies that might be missing
echo \"📦 Installing Python dependencies...\"
apt-get install -y -qq python3-cryptography python3-gi python3-dbus

# Configure Bluetooth for BLE
echo \"📶 Configuring Bluetooth...\"
if [ ! -f /etc/systemd/system/bluetooth.service ]; then
    cp /lib/systemd/system/bluetooth.service /etc/systemd/system/
fi
sed -i 's|ExecStart=/usr/libexec/bluetooth/bluetoothd|ExecStart=/usr/libexec/bluetooth/bluetoothd --experimental -P battery|' /etc/systemd/system/bluetooth.service

# Fix network service conflicts
echo \"🚨 Fixing network service conflicts...\"

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

# Configure NetworkManager
echo \"🔧 Configuring NetworkManager...\"
mkdir -p /etc/NetworkManager/conf.d
cat > /etc/NetworkManager/conf.d/99-wifi-backend.conf << 'NM_EOF'
[device]
wifi.backend=wpa_supplicant
wifi.scan-rand-mac-address=no

[main]
no-auto-default=*
NM_EOF

# Create NetworkManager override for proper startup
echo \"⚙️ Creating service overrides...\"
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
Environment=\"PYTHONUNBUFFERED=1\"
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
echo \"🚀 Enabling services...\"
systemctl daemon-reload
systemctl enable NetworkManager
systemctl enable wpa_supplicant.service
systemctl enable bluetooth.service
systemctl enable btwifiset.service
systemctl enable network-interface-protection.service

# Start services in correct order
systemctl start NetworkManager
sleep 2
systemctl start wpa_supplicant.service
sleep 2
systemctl start bluetooth.service
sleep 2
systemctl restart btwifiset.service

# Force interface management
if [ -e /sys/class/net/wlan0 ]; then
    rfkill unblock wifi 2>/dev/null || true
    ip link set wlan0 up 2>/dev/null || true
fi

nmcli radio wifi on 2>/dev/null || true
nmcli device set wlan0 managed yes 2>/dev/null || true
nmcli device set eth0 managed yes 2>/dev/null || true
nmcli device connect eth0 2>/dev/null || true

echo \"✅ Installation complete!\"
echo \"📊 Status:\"
echo \"  NetworkManager: \$(systemctl is-active NetworkManager)\"
echo \"  Bluetooth: \$(systemctl is-active bluetooth)\"
echo \"  BTBerryWifi: \$(systemctl is-active btwifiset.service)\" 
echo \"  systemd-networkd: \$(systemctl is-active systemd-networkd.service 2>/dev/null || echo 'masked')\"
echo \"  Ethernet: \$(ip addr show eth0 | grep 'inet ' | awk '{print \$2}' || echo 'No IP')\"
echo \"\"
echo \"⚠️ A reboot is recommended to ensure all services start correctly\"
INSTALL_EOF

chmod +x network-install.sh
echo \"Installation script created at /tmp/network-install.sh\"
"

print_success "Network installation script prepared on Pi"

# Step 3: Run the installation
print_status "🛠️ Running network installation..."
pi run --pi "$PI_NAME" "cd /tmp && sudo ./network-install.sh"

print_success "Network installation completed"

# Step 4: Verification
print_status "📊 Verifying installation..."
pi run --pi "$PI_NAME" "
echo '=== Service Status ==='
echo 'NetworkManager:' \$(systemctl is-active NetworkManager)
echo 'Bluetooth:' \$(systemctl is-active bluetooth)
echo 'BTBerryWifi:' \$(systemctl is-active btwifiset.service)
echo 'Serial Agent:' \$(systemctl is-active serial-agent@ttyAMA0 2>/dev/null || echo 'not installed')
echo ''
echo '=== Network Status ==='
echo 'Ethernet:' \$(ip addr show eth0 2>/dev/null | grep 'inet ' | awk '{print \$2}' || echo 'No IP')
echo 'WiFi:' \$(ip addr show wlan0 2>/dev/null | grep 'inet ' | awk '{print \$2}' || echo 'Not connected')
echo ''
echo '=== Bluetooth Status ==='
hciconfig hci0 2>/dev/null | head -3 || echo 'Bluetooth interface not found'
"

print_success "✅ DEPLOYMENT COMPLETE!"
echo ""
print_warning "📝 Next Steps:"
echo "  1. Reboot the Pi: pi run --pi $PI_NAME 'sudo reboot'"
echo "  2. Wait 60 seconds for reboot"
echo "  3. Verify connectivity: pi status"
echo "  4. Test BTBerryWifi app - look for device named '$(pi run --pi $PI_NAME 'hostname' 2>/dev/null | tr -d '\n')'"
if [ "$SKIP_SERIAL" = false ]; then
    echo "  5. Test serial console: python3 $PI_SERIAL_PATH/scripts/serial_bridge run --port_name pi_console 'hostname'"
fi
echo ""
print_warning "⚠️ Note: If Pi loses network after reboot, use serial console to run:"
echo "  nmcli device connect eth0"