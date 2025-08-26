#!/bin/bash

# This script must be run as root
if [ "$EUID" -ne 0 ]
  then echo "Please run as root or with sudo"
  exit
fi

set -e

echo ">>> Installing BTBerryWifi BLE Service..."

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

echo ">>> Installing BTBerryWifi service..."
# Install the btwifiset service using the official installer
curl -L https://raw.githubusercontent.com/nksan/Rpi-SetWiFi-viaBluetooth/main/btwifisetInstall.sh | bash

# Copy the D-Bus configuration file for BlueZ and wpa_supplicant
echo ">>> Installing D-Bus configuration..."
sudo cp "$SCRIPT_DIR/ble-dbus.conf" /etc/dbus-1/system.d/

# Apply Bluetooth/Wi-Fi coexistence firmware patch
echo ">>> Applying Wi-Fi/Bluetooth coexistence firmware patch..."
FIRMWARE_FILE="/usr/lib/firmware/brcm/brcmfmac43455-sdio.txt"

OLD_COEXISTENCE_CONFIG="# Improved Bluetooth coexistence parameters from Cypress\nbtc_mode=1\nbtc_params8=0x4e20\nbtc_params1=0x7530\nbtc_params50=0x972c"
NEW_COEXISTENCE_CONFIG="# Improved Bluetooth coexistence parameters from Cypress\nbtc_mode=4\n# btc_params8=0x4e20\n# btc_params1=0x7530\n# btc_params50=0x972c"

sudo sed -i "s|${OLD_COEXISTENCE_CONFIG}|${NEW_COEXISTENCE_CONFIG}|g" "$FIRMWARE_FILE"

# CRITICAL: Modify Bluetooth service for proper BLE support
echo ">>> Configuring Bluetooth service for BLE support..."
# Copy and modify the bluetooth service file
sudo cp /lib/systemd/system/bluetooth.service /etc/systemd/system/
sudo sed -i 's|ExecStart=/usr/libexec/bluetooth/bluetoothd|ExecStart=/usr/libexec/bluetooth/bluetoothd --experimental -P battery|' /etc/systemd/system/bluetooth.service

# Reload systemd to pick up the modified service
sudo systemctl daemon-reload

# Setup Bluetooth security timer service
echo ">>> Setting up Bluetooth security timer service..."
sudo tee /etc/systemd/system/bluetooth-security-timer.service > /dev/null << 'EOF'
[Unit]
Description=Bluetooth Security Timer - Disables Bluetooth after 10 minutes
After=bluetooth.service
Wants=bluetooth.service

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'sleep 600 && systemctl stop bluetooth && systemctl disable bluetooth'
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Enable the security timer service
sudo systemctl enable bluetooth-security-timer.service

# CRITICAL: Configure NetworkManager for WiFi/Ethernet coexistence
echo ">>> Configuring NetworkManager for WiFi and Ethernet coexistence..."

# Install required packages
echo ">>> Installing network management packages..."
apt install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" network-manager wireless-tools wpasupplicant rfkill

# Wait for packages to be available
sleep 2

# Ensure wpa_supplicant.conf is properly configured (for fallback if needed)
echo ">>> Setting up wpa_supplicant configuration..."
sudo cp "$SCRIPT_DIR/wpa_supplicant.conf" /etc/wpa_supplicant/

# Check if WiFi interface exists
if [ -e /sys/class/net/wlan0 ]; then
    echo ">>> WiFi interface wlan0 found, configuring for NetworkManager..."
    
    # Unblock WiFi radio
    echo ">>> Unblocking WiFi radio..."
    if command -v rfkill >/dev/null 2>&1; then
        rfkill unblock wifi
        sleep 2
        echo ">>> WiFi radio unblocked"
    else
        echo ">>> Warning: rfkill command not available"
    fi
    
    # Bring up WiFi interface
    echo ">>> Activating WiFi interface..."
    ip link set wlan0 up 2>/dev/null || echo ">>> Warning: Could not bring up wlan0"
    sleep 2
    
    # Ensure NetworkManager is enabled and running
    echo ">>> Starting NetworkManager service..."
    systemctl enable NetworkManager
    systemctl start NetworkManager
    sleep 3
    
    # CRITICAL FIX: Prevent systemd-networkd conflicts that cause reboot failures
    echo ">>> Preventing systemd-networkd conflicts..."
    systemctl disable systemd-networkd.service 2>/dev/null || true
    systemctl mask systemd-networkd.service 2>/dev/null || true
    systemctl disable systemd-networkd.socket 2>/dev/null || true
    systemctl disable systemd-network-generator.service 2>/dev/null || true
    echo ">>> Network service conflicts resolved - system will survive reboot"
    
    # CRITICAL: Configure wpa_supplicant for NetworkManager compatibility
    echo ">>> Configuring wpa_supplicant for NetworkManager compatibility..."
    
    # Stop any interface-specific wpa_supplicant services that conflict
    systemctl stop wpa_supplicant@wlan0.service 2>/dev/null || true
    systemctl disable wpa_supplicant@wlan0.service 2>/dev/null || true
    systemctl mask wpa_supplicant@wlan0.service 2>/dev/null || true
    
    # Kill any interface-specific wpa_supplicant processes
    pkill -f "wpa_supplicant.*-i.*wlan0" || true
    sleep 2
    
    # Enable the main wpa_supplicant service (NetworkManager needs this as D-Bus service)
    systemctl enable wpa_supplicant.service
    systemctl start wpa_supplicant.service
    sleep 2
    
    echo ">>> wpa_supplicant configured as D-Bus service for NetworkManager"
    
    # Enable WiFi in NetworkManager and make persistent
    echo ">>> Enabling WiFi in NetworkManager..."
    nmcli radio wifi on
    nmcli device set wlan0 managed yes
    
    # Create persistent NetworkManager configuration for WiFi
    echo ">>> Creating persistent NetworkManager WiFi configuration..."
    mkdir -p /etc/NetworkManager/conf.d
    cat > /etc/NetworkManager/conf.d/99-wifi-backend.conf << 'NMEOF'
[device]
# Ensure NetworkManager manages WiFi interface
wifi.backend=wpa_supplicant
wifi.scan-rand-mac-address=no

[main]
# Ensure WiFi is enabled by default
no-auto-default=*
NMEOF
    
    sleep 3
    
    # Create WiFi enablement service for persistent WiFi availability
    echo ">>> Creating WiFi enablement service for boot persistence..."
    cat > /etc/systemd/system/wifi-enablement.service << 'WIFIEOF'
[Unit]
Description=Enable WiFi Interface and Radio
After=network-pre.target
Before=NetworkManager.service
Wants=NetworkManager.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c 'rfkill unblock wifi; ip link set wlan0 up 2>/dev/null || true'
ExecStartPost=/bin/sleep 2

[Install]
WantedBy=multi-user.target network.target
WIFIEOF
    
    # Enable the WiFi enablement service
    systemctl enable wifi-enablement.service
    echo ">>> WiFi enablement service created and enabled"
    
    # Test NetworkManager WiFi scanning
    echo ">>> Testing WiFi scanning with NetworkManager..."
    if timeout 15 nmcli device wifi list | grep -q "SSID"; then
        echo ">>> NetworkManager WiFi scanning is working"
        SCAN_COUNT=$(nmcli device wifi list | grep -c "WPA" || echo "0")
        echo ">>> Found $SCAN_COUNT WPA networks"
    else
        echo ">>> Warning: NetworkManager WiFi scanning test failed"
    fi
    
    # Test both interfaces are available
    echo ">>> Testing network interface coexistence..."
    nmcli device status | grep -E "eth0|wlan0" || echo ">>> Warning: Interface status check failed"
    
else
    echo ">>> Warning: WiFi interface wlan0 not found"
    echo ">>> This Pi may not have WiFi capability"
fi

# Copy updated btwifiset.py with NetworkManager and password fixes
echo ">>> Installing fixed btwifiset.py with NetworkManager support..."
sudo cp "$SCRIPT_DIR/btwifiset.py" /usr/local/btwifiset/

# Copy WiFi test and diagnostic scripts
echo ">>> Installing WiFi test and diagnostic scripts..."
sudo cp "$SCRIPT_DIR/test-wifi-scan.sh" /usr/local/bin/
sudo cp "$SCRIPT_DIR/verify-fixes.sh" /usr/local/bin/
sudo cp "$SCRIPT_DIR/fix-network-stability.sh" /usr/local/bin/
sudo cp "$SCRIPT_DIR/diagnose-network-failure.sh" /usr/local/bin/
sudo chmod +x /usr/local/bin/test-wifi-scan.sh
sudo chmod +x /usr/local/bin/verify-fixes.sh
sudo chmod +x /usr/local/bin/fix-network-stability.sh
sudo chmod +x /usr/local/bin/diagnose-network-failure.sh

echo ">>> Setting up and starting BTBerryWifi service..."
systemctl daemon-reload

# Enable and start the btwifiset service (this is the main BLE service)
systemctl enable btwifiset.service
systemctl start btwifiset.service

echo ">>> Installation complete. The BTBerryWifi BLE service is now running."
echo ">>> Users can now use the BTBerryWifi mobile app to configure WiFi."
echo ">>> Bluetooth will automatically disable after 10 minutes for security."
echo ">>> IMPORTANT: Network stability fix applied - system will maintain connectivity after reboot."
echo ""
echo ">>> IMPORTANT: Before creating your distributable image, run:"
echo ">>> sudo /path/to/wipe-credentials.sh"
echo ">>> This will clear all credentials and prepare the Pi for distribution."
echo ""
echo ">>> NETWORK STABILITY: If you experience network failures after BTBerryWifi usage:"
echo ">>> sudo /usr/local/bin/fix-network-stability.sh"
echo ">>> This applies comprehensive stability fixes for problematic environments."

# Show service status
echo ">>> Service Status:"
systemctl status btwifiset.service --no-pager
echo ""
echo ">>> To check logs: journalctl -u btwifiset.service -f"
echo ">>> To restart: systemctl restart btwifiset.service"
echo ">>> To check if service is running: systemctl is-active btwifiset.service"
echo ""
echo ">>> Security Timer: Bluetooth will auto-disable in 10 minutes"
echo ">>> To re-enable Bluetooth: sudo systemctl enable bluetooth && sudo systemctl start bluetooth"
echo ""
echo ">>> Running deployment verification..."
/usr/local/bin/verify-fixes.sh
