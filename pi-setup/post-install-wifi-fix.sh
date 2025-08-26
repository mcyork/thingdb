#!/bin/bash
# post-install-wifi-fix.sh
# Additional fixes to run after initial deployment to ensure WiFi works properly

set -e

echo "🔧 Running post-installation WiFi fixes..."

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "❌ This script must be run as root or with sudo"
    exit 1
fi

echo "🔍 Phase 1: Comprehensive service cleanup..."

# Stop and mask ALL wpa_supplicant related services
for service in wpa_supplicant wpa_supplicant@wlan0 wpa_supplicant@.service; do
    systemctl stop "$service" 2>/dev/null || true
    systemctl disable "$service" 2>/dev/null || true
    systemctl mask "$service" 2>/dev/null || true
    echo "   ✓ $service disabled and masked"
done

# Kill any lingering wpa_supplicant processes
pkill -f wpa_supplicant || true
sleep 2

echo "🔍 Phase 2: WiFi hardware and driver verification..."

# Ensure WiFi hardware is available
if [ ! -e /sys/class/net/wlan0 ]; then
    echo "❌ WiFi interface wlan0 not found - this Pi may not have WiFi capability"
    exit 1
fi

# Check if rfkill is available and unblock
RFKILL_CMD=""
if [ -x /usr/sbin/rfkill ]; then
    RFKILL_CMD="/usr/sbin/rfkill"
elif [ -x /sbin/rfkill ]; then
    RFKILL_CMD="/sbin/rfkill"
elif command -v rfkill >/dev/null 2>&1; then
    RFKILL_CMD="rfkill"
fi

if [ -n "$RFKILL_CMD" ]; then
    echo "   ✓ Using rfkill at: $RFKILL_CMD"
    $RFKILL_CMD unblock wifi || echo "   ⚠️ rfkill unblock failed"
    sleep 2
else
    echo "   ⚠️ rfkill command not found - skipping RF unblock"
fi

# Ensure interface is up
ip link set wlan0 up 2>/dev/null || echo "   ⚠️ Could not bring up wlan0"
sleep 2

echo "🔍 Phase 3: NetworkManager reconfiguration..."

# Ensure NetworkManager is running
systemctl enable NetworkManager
systemctl restart NetworkManager
sleep 5

# Force NetworkManager to manage WiFi
nmcli radio wifi on 2>/dev/null || echo "   ⚠️ Could not enable WiFi radio"
nmcli device set wlan0 managed yes 2>/dev/null || echo "   ⚠️ Could not set wlan0 to managed"
sleep 3

# Try to trigger a device rescan
nmcli device disconnect wlan0 2>/dev/null || true
sleep 1
nmcli device connect wlan0 2>/dev/null || true
sleep 2

echo "🔍 Phase 4: Testing WiFi functionality..."

# Test WiFi scanning
echo "   Testing WiFi scanning capability..."
SCAN_RESULT=$(timeout 15 nmcli device wifi list 2>/dev/null | wc -l)
if [ "$SCAN_RESULT" -gt 1 ]; then
    echo "   ✅ WiFi scanning working - NetworkManager can see networks"
else
    echo "   ❌ WiFi scanning not working - trying alternative method"
    
    # Try iwlist as fallback
    if command -v iwlist >/dev/null 2>&1; then
        IWLIST_RESULT=$(timeout 10 iwlist wlan0 scan 2>/dev/null | grep -c ESSID || echo "0")
        if [ "$IWLIST_RESULT" -gt 0 ]; then
            echo "   ⚠️ iwlist can scan but NetworkManager cannot - driver issue"
        else
            echo "   ❌ No WiFi scanning working - hardware or driver problem"
        fi
    fi
fi

echo "🔍 Phase 5: BTBerryWifi service verification..."

# Restart BTBerryWifi to use the fixed NetworkManager setup
systemctl restart btwifiset.service
sleep 5

# Check if it's using NetworkManager mode
if journalctl -u btwifiset.service --since="1 minute ago" -q | grep -q "version 2 (nmcli/crypto)"; then
    echo "   ✅ BTBerryWifi using NetworkManager mode"
else
    echo "   ❌ BTBerryWifi not using NetworkManager mode - check logs"
    journalctl -u btwifiset.service -n 10 --no-pager
fi

echo "🔍 Phase 6: Final status check..."

# Show final status
echo ""
echo "📊 Final System Status:"
echo "   • NetworkManager: $(systemctl is-active NetworkManager 2>/dev/null || echo 'INACTIVE')"
echo "   • wpa_supplicant: $(systemctl is-active wpa_supplicant.service 2>/dev/null || echo 'INACTIVE/MASKED')"  
echo "   • wpa_supplicant masked: $(systemctl is-masked wpa_supplicant.service >/dev/null 2>&1 && echo 'YES' || echo 'NO')"
echo "   • BTBerryWifi: $(systemctl is-active btwifiset.service 2>/dev/null || echo 'INACTIVE')"
echo "   • wlan0 state: $(nmcli device status | grep wlan0 | awk '{print $3}' || echo 'UNKNOWN')"

# Test WiFi scanning one more time
FINAL_SCAN=$(timeout 10 nmcli device wifi list 2>/dev/null | wc -l)
if [ "$FINAL_SCAN" -gt 1 ]; then
    NETWORK_COUNT=$((FINAL_SCAN - 1))
    echo "   • WiFi scanning: ✅ Working ($NETWORK_COUNT networks found)"
else
    echo "   • WiFi scanning: ❌ Not working"
fi

echo ""
if [ "$FINAL_SCAN" -gt 1 ] && systemctl is-active --quiet btwifiset.service; then
    echo "✅ Post-installation WiFi fixes completed successfully!"
    echo "📱 BTBerryWifi should now work properly for WiFi configuration."
else
    echo "⚠️ Some WiFi issues remain - manual intervention may be required"
    echo "💡 Try rebooting the Pi and running this script again"
fi

echo ""
echo "🔧 For further troubleshooting:"
echo "   • Check: systemctl status NetworkManager"
echo "   • Check: systemctl status btwifiset.service"
echo "   • Test: nmcli device wifi list"
echo "   • Verify: /usr/local/bin/verify-fixes.sh"