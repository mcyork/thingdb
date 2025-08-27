#!/bin/bash
# install-network-remote.sh - Remote Network Installation using pi CLI tool
# This script remotely installs BTBerryWifi network management on a Raspberry Pi

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

# Check if pi CLI tool is available
if ! command -v pi &> /dev/null; then
    print_error "pi CLI tool not found. Please install it first."
    exit 1
fi

# Check if default Pi configuration exists
if ! pi list | grep -q "Yes"; then
    print_error "No default Pi configuration found. Please configure a default Pi first."
    echo "Available Pis:"
    pi list
    exit 1
fi

# Get the default Pi name
DEFAULT_PI=$(pi list | grep "Yes" | awk '{print $1}')
print_status "Using default Pi: $DEFAULT_PI"

# Check if Pi is online
if ! pi status "$DEFAULT_PI" | grep -q "ONLINE"; then
    print_error "Pi '$DEFAULT_PI' is not online"
    echo "Current status:"
    pi status "$DEFAULT_PI"
    exit 1
fi

print_status "✅ Pi '$DEFAULT_PI' is online and ready"

# Check if the network installer script exists
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_SCRIPT="$SCRIPT_DIR/install-network.sh"

if [ ! -f "$INSTALL_SCRIPT" ]; then
    print_error "Network installer script not found: $INSTALL_SCRIPT"
    exit 1
fi

print_status "Found network installer script: $INSTALL_SCRIPT"

# Transfer the installer script to the Pi
print_status "📤 Transferring network installer to Pi..."
if pi send --pi "$DEFAULT_PI" "$INSTALL_SCRIPT" "/tmp/install-network.sh"; then
    print_success "Network installer transferred successfully"
else
    print_error "Failed to transfer network installer"
    exit 1
fi

# Make the script executable on the Pi
print_status "🔧 Making script executable on Pi..."
pi run --pi "$DEFAULT_PI" "chmod +x /tmp/install-network.sh"

# Show pre-installation status
print_status "📊 PRE-INSTALLATION STATUS:"
pi run --pi "$DEFAULT_PI" "
echo 'Network services:'
systemctl is-enabled NetworkManager 2>/dev/null | head -1 || echo 'NetworkManager: not found'
systemctl is-enabled systemd-networkd.service 2>/dev/null | head -1 || echo 'systemd-networkd: disabled'  
systemctl is-enabled dhcpcd.service 2>/dev/null | head -1 || echo 'dhcpcd: not found'
echo ''
echo 'Network interfaces:'
ip addr show | grep -E 'eth0|wlan0' -A 1 | grep -E 'eth0|wlan0|inet ' || echo 'No interfaces with IPs'
"

echo ""
print_warning "⚠️ NETWORK INSTALLATION STARTING..."
print_warning "   This will temporarily disconnect network services"
print_warning "   The Pi may become briefly inaccessible during installation"
echo ""

# Execute the network installation
print_status "🚀 Running network installation on Pi..."
if pi run-stream --pi "$DEFAULT_PI" "sudo /tmp/install-network.sh"; then
    print_success "Network installation completed successfully!"
else
    print_error "Network installation failed or was interrupted"
    print_warning "Check the Pi's status and logs for more details"
    exit 1
fi

echo ""
print_status "📊 POST-INSTALLATION STATUS:"
pi run --pi "$DEFAULT_PI" "
echo 'Service status:'
echo '  NetworkManager:' \$(systemctl is-active NetworkManager 2>/dev/null)
echo '  systemd-networkd:' \$(systemctl is-active systemd-networkd.service 2>/dev/null || echo 'masked')
echo '  dhcpcd:' \$(systemctl is-active dhcpcd.service 2>/dev/null || echo 'masked')  
echo '  BTBerryWifi:' \$(systemctl is-active btwifiset.service 2>/dev/null)
echo '  Bluetooth:' \$(systemctl is-active bluetooth.service 2>/dev/null)
echo ''
echo 'Network interfaces:'
ip addr show | grep -E 'eth0|wlan0' -A 1 | grep -E 'eth0|wlan0|inet ' || echo 'No IPs assigned'
"

echo ""
print_warning "⚠️ IMPORTANT: A reboot is required for all changes to take effect!"
print_warning "   The Pi needs to be rebooted to ensure stable network operation"
echo ""

# Ask user if they want to reboot now
read -p "Do you want to reboot the Pi now? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_status "🔄 Rebooting Pi..."
    pi run --pi "$DEFAULT_PI" "sudo reboot"
    
    print_status "⏰ Waiting for reboot to complete..."
    sleep 60
    
    print_status "🧪 Testing post-reboot connectivity..."
    for attempt in {1..10}; do
        echo "Attempt $attempt/10..."
        if pi run --pi "$DEFAULT_PI" "echo 'Pi is back online!'" 2>/dev/null; then
            print_success "✅ REBOOT SUCCESSFUL - Pi is accessible!"
            break
        elif [ $attempt -eq 10 ]; then
            print_warning "⚠️ Pi not accessible after reboot - this may indicate network issues"
            print_warning "   Use serial console to check status and run: sudo nmcli device connect eth0"
            break
        else
            sleep 10
        fi
    done
    
    echo ""
    print_status "📊 POST-REBOOT NETWORK STATUS:"
    pi run --pi "$DEFAULT_PI" "
    echo 'Interface status:'
    echo '  Ethernet:' \$(ip addr show eth0 | grep 'inet ' | awk '{print \$2}' || echo 'No IP')
    echo '  WiFi:' \$(ip addr show wlan0 | grep 'inet ' | awk '{print \$2}' || echo 'No IP')
    echo ''
    echo 'Service status:'
    echo '  NetworkManager:' \$(systemctl is-active NetworkManager)
    echo '  BTBerryWifi:' \$(systemctl is-active btwifiset.service)
    echo '  Bluetooth:' \$(systemctl is-active bluetooth.service)
    "
else
    print_status "Manual reboot required. Run this command when ready:"
    echo "  pi run --pi $DEFAULT_PI 'sudo reboot'"
fi

echo ""
print_success "🎯 NETWORK INSTALLATION COMPLETE!"
echo "========================================="
echo ""
echo "📱 Next Steps:"
echo "• Test BTBerryWifi with mobile app (should appear as '$(pi run --pi "$DEFAULT_PI" 'hostname')')"
echo "• Default password: inventory"
echo "• Ethernet should reconnect automatically after reboot"
echo ""
echo "🔧 Troubleshooting:"
echo "• If network issues persist, use serial console to run: sudo nmcli device connect eth0"
echo "• Check service status: pi run --pi $DEFAULT_PI 'systemctl status btwifiset.service'"
echo "• View logs: pi run --pi $DEFAULT_PI 'journalctl -u btwifiset.service -f'"
