#!/bin/bash
# prepare-for-imaging.sh
# Prepares the Pi for SD card image creation by cleaning sensitive data and resetting to first-boot state

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
PI_CLI="/Users/ianmccutcheon/projects/pi-shell/pi"
if [ ! -f "$PI_CLI" ]; then
    print_error "pi CLI tool not found at $PI_CLI"
    exit 1
fi

# Get the default Pi
DEFAULT_PI=$("$PI_CLI" list | grep "Yes" | awk '{print $1}')
if [ -z "$DEFAULT_PI" ]; then
    print_error "No default Pi found. Please set a default Pi first"
    exit 1
fi

print_status "Preparing $DEFAULT_PI for SD card imaging..."

# Warning about what this will do
print_warning "This will clean the Pi for distribution. It will:"
echo "   • Remove all SSH keys and WiFi credentials"
echo "   • Clear system logs and temporary files"  
echo "   • Reset machine-specific identifiers"
echo "   • Prepare BTBerryWifi for first boot"
echo "   • Shutdown the Pi for SD card removal"
echo ""

read -p "Continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_error "Cancelled by user"
    exit 1
fi

print_status "Starting Pi cleanup for imaging..."

# Run the comprehensive cleanup script on the Pi
CLEANUP_SCRIPT=$(cat << 'EOF'
#!/bin/bash
set -e

echo "🧹 Preparing Pi for SD card image creation..."

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

echo "📋 Phase 1: Cleaning credentials and sensitive data..."

# Run wipe-credentials script if it exists
if [ -f /tmp/pi-setup/wipe-credentials.sh ]; then
    echo "Running wipe-credentials script..."
    bash /tmp/pi-setup/wipe-credentials.sh
else
    echo "No wipe-credentials script found, doing manual cleanup..."
    
    # Clear SSH host keys (will be regenerated on first boot)
    rm -f /etc/ssh/ssh_host_*
    
    # Clear user SSH keys
    find /home -name ".ssh" -type d -exec rm -rf {} + 2>/dev/null || true
    rm -rf /root/.ssh 2>/dev/null || true
    
    # Clear WiFi configurations
    cat > /etc/wpa_supplicant/wpa_supplicant.conf << 'WPAEOF'
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=US
WPAEOF
    
    # Clear any NetworkManager connections
    rm -rf /etc/NetworkManager/system-connections/* 2>/dev/null || true
fi

echo "📋 Phase 2: Clearing logs and temporary files..."

# Clear system logs
journalctl --vacuum-time=1s 2>/dev/null || true
find /var/log -type f -name "*.log" -delete 2>/dev/null || true
find /var/log -type f -name "*.log.*" -delete 2>/dev/null || true
rm -rf /var/log/journal/* 2>/dev/null || true

# Clear temporary files
rm -rf /tmp/* 2>/dev/null || true
rm -rf /var/tmp/* 2>/dev/null || true
find /home -name ".bash_history" -delete 2>/dev/null || true
rm -f /root/.bash_history 2>/dev/null || true

# Clear package cache
apt-get clean 2>/dev/null || true
rm -rf /var/cache/apt/archives/* 2>/dev/null || true

echo "📋 Phase 3: Resetting machine-specific identifiers..."

# Clear machine ID (will be regenerated)
rm -f /etc/machine-id
rm -f /var/lib/dbus/machine-id
systemd-machine-id-setup

# Clear DHCP leases
rm -f /var/lib/dhcp/* 2>/dev/null || true
rm -f /var/lib/dhcpcd5/* 2>/dev/null || true

# Clear network interface persistent rules
rm -f /etc/udev/rules.d/70-persistent-net.rules 2>/dev/null || true

echo "📋 Phase 4: Preparing BTBerryWifi for first boot..."

# Ensure BTBerryWifi service is enabled for first boot
systemctl enable btwifiset.service 2>/dev/null || true
systemctl enable bluetooth.service 2>/dev/null || true

# Ensure NetworkManager is enabled and configured correctly  
systemctl enable NetworkManager 2>/dev/null || true

# Clear any existing WiFi connections from NetworkManager
rm -rf /etc/NetworkManager/system-connections/* 2>/dev/null || true

# Ensure wlan0 is unblocked and ready
rfkill unblock wifi 2>/dev/null || true

echo "📋 Phase 5: Final system optimization..."

# Sync filesystem
sync
sleep 2

# Clear kernel messages
dmesg -c > /dev/null 2>&1 || true

# Update file database
updatedb 2>/dev/null || true

echo "✅ Pi preparation complete!"
echo "🔧 First boot will:"
echo "   • Generate new SSH host keys"
echo "   • Create new machine ID" 
echo "   • Start BTBerryWifi for WiFi configuration"
echo "   • Be ready for inventory system use"

# Final sync before shutdown
sync
sleep 3

echo "🛑 Shutting down Pi for SD card imaging..."
sleep 2
shutdown -h now
EOF
)

# Send and execute the cleanup script
print_status "Running cleanup script on Pi..."
echo "$CLEANUP_SCRIPT" | "$PI_CLI" send --pi "$DEFAULT_PI" - /tmp/cleanup-for-imaging.sh
"$PI_CLI" run --pi "$DEFAULT_PI" "chmod +x /tmp/cleanup-for-imaging.sh"
"$PI_CLI" run --pi "$DEFAULT_PI" "sudo /tmp/cleanup-for-imaging.sh"

print_success "Pi cleanup completed and shutdown initiated"
print_status "Wait for Pi to fully shutdown, then remove SD card for imaging"
print_status "Next step: Run ./scripts/create-distributable-image.sh with the SD card in your Mac"