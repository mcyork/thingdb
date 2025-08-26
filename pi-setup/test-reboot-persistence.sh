#!/bin/bash
# test-reboot-persistence.sh
# Tests that WiFi/NetworkManager fixes persist across reboots

echo "🔄 Testing Reboot Persistence of WiFi Fixes..."

BTWIFISET_PATH="/usr/local/btwifiset/btwifiset.py"

echo ""
echo "📋 Pre-Reboot Check:"
echo "   • NetworkManager: $(systemctl is-active NetworkManager 2>/dev/null || echo 'INACTIVE')"
echo "   • wpa_supplicant: $(systemctl is-active wpa_supplicant 2>/dev/null || echo 'INACTIVE')"
echo "   • wpa_supplicant masked: $(systemctl is-masked wpa_supplicant.service >/dev/null 2>&1 && echo 'YES' || echo 'NO')"
echo "   • WiFi enablement service: $(systemctl is-enabled wifi-enablement.service 2>/dev/null || echo 'DISABLED')"
echo "   • BTBerryWifi service: $(systemctl is-active btwifiset.service 2>/dev/null || echo 'INACTIVE')"

echo ""
echo "🔄 Rebooting Pi to test persistence..."
echo "⚠️  This will reboot the Pi and disconnect SSH!"
echo ""

read -p "Continue with reboot test? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled by user"
    exit 1
fi

# Create a script that will run after reboot to verify persistence
cat > /tmp/post-reboot-check.sh << 'EOF'
#!/bin/bash
# Post-reboot verification script

echo "🔄 Post-Reboot Persistence Check - $(date)"

echo ""
echo "📋 Service Status After Reboot:"
echo "   • NetworkManager: $(systemctl is-active NetworkManager 2>/dev/null || echo 'INACTIVE')"
echo "   • wpa_supplicant: $(systemctl is-active wpa_supplicant 2>/dev/null || echo 'INACTIVE')" 
echo "   • wpa_supplicant masked: $(systemctl is-masked wpa_supplicant.service >/dev/null 2>&1 && echo 'YES' || echo 'NO')"
echo "   • WiFi enablement service: $(systemctl is-active wifi-enablement.service 2>/dev/null || echo 'INACTIVE')"
echo "   • BTBerryWifi service: $(systemctl is-active btwifiset.service 2>/dev/null || echo 'INACTIVE')"

echo ""
echo "📡 WiFi Interface Status:"
echo "   • wlan0 state: $(ip link show wlan0 2>/dev/null | grep -o 'state [A-Z]*' || echo 'NOT FOUND')"
echo "   • RF-kill status: $(rfkill list wifi 2>/dev/null | grep -o 'blocked: [a-z]*' || echo 'UNKNOWN')"
echo "   • NetworkManager device: $(nmcli device status 2>/dev/null | grep wlan0 | awk '{print $3}' || echo 'NOT MANAGED')"

echo ""
echo "🔍 WiFi Scanning Test:"
SCAN_COUNT=$(timeout 10 nmcli device wifi list 2>/dev/null | grep -c "WPA" || echo "0")
if [ "$SCAN_COUNT" -gt 0 ]; then
    echo "   ✅ WiFi scanning working - found $SCAN_COUNT networks"
else
    echo "   ❌ WiFi scanning failed or no networks found"
fi

echo ""
echo "🔧 BTBerryWifi Mode Check:"
if systemctl is-active --quiet btwifiset.service; then
    if journalctl -u btwifiset.service --since="5 minutes ago" -q | grep -q "version 2 (nmcli/crypto)"; then
        echo "   ✅ BTBerryWifi using NetworkManager mode"
    else
        echo "   ❌ BTBerryWifi not using NetworkManager mode"
    fi
else
    echo "   ❌ BTBerryWifi service not running"
fi

echo ""
if [ "$SCAN_COUNT" -gt 0 ] && systemctl is-active --quiet NetworkManager && systemctl is-active --quiet btwifiset.service; then
    echo "✅ PERSISTENCE TEST PASSED - All fixes survived reboot!"
else
    echo "❌ PERSISTENCE TEST FAILED - Some fixes did not survive reboot"
    echo ""
    echo "🔧 Troubleshooting:"
    echo "   • Check systemctl status NetworkManager"
    echo "   • Check systemctl status btwifiset.service" 
    echo "   • Check systemctl status wifi-enablement.service"
    echo "   • Run: sudo /usr/local/bin/verify-fixes.sh"
fi

echo ""
echo "📝 Reboot persistence test completed at $(date)"
EOF

chmod +x /tmp/post-reboot-check.sh

# Schedule the post-reboot check to run automatically
echo "📅 Scheduling post-reboot verification..."
echo "/tmp/post-reboot-check.sh > /tmp/reboot-test-results.txt 2>&1" | at now + 3 minutes 2>/dev/null || {
    # Fallback: add to rc.local if at command not available
    echo "Adding to rc.local for post-reboot check..."
    sed -i '/exit 0/i /tmp/post-reboot-check.sh > /tmp/reboot-test-results.txt 2>&1 &' /etc/rc.local 2>/dev/null || true
}

echo "✅ Post-reboot check scheduled"
echo "📄 Results will be saved to: /tmp/reboot-test-results.txt"
echo ""
echo "🔄 Rebooting now..."
sleep 3

# Reboot the system
reboot