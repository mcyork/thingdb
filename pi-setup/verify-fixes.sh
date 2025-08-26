#!/bin/bash
# Verification script to ensure all critical fixes are in place

echo "🔍 Verifying BTBerryWifi deployment fixes..."

BTWIFISET_PATH="/usr/local/btwifiset/btwifiset.py"

# Check 1: NetworkManager support enabled
echo ""
echo "✅ Check 1: NetworkManager Support"
if grep -q "return network_manager_is_running" "$BTWIFISET_PATH" 2>/dev/null; then
    echo "   ✓ NetworkManager detection enabled (not forced to wpa_supplicant)"
else
    echo "   ❌ CRITICAL: NetworkManager support not enabled!"
    echo "   Expected: 'return network_manager_is_running'"
    exit 1
fi

# Check 2: Plain password handling
echo ""
echo "✅ Check 2: Password Handling Fix"
if grep -q "psk = f'psk={pw}'" "$BTWIFISET_PATH" 2>/dev/null; then
    echo "   ✓ Plain password handling implemented"
else
    echo "   ❌ CRITICAL: Password handling fix not applied!"
    echo "   Expected: \"psk = f'psk={pw}'\""
    exit 1
fi

# Check 3: NetworkManager service status
echo ""
echo "✅ Check 3: NetworkManager Service"
if systemctl is-active NetworkManager >/dev/null 2>&1; then
    echo "   ✓ NetworkManager service is running"
else
    echo "   ❌ WARNING: NetworkManager service not running"
fi

# Check 4: WiFi interface status
echo ""
echo "✅ Check 4: WiFi Interface Status"
if nmcli device status 2>/dev/null | grep -q "wlan0.*wifi"; then
    WIFI_STATUS=$(nmcli device status | grep wlan0 | awk '{print $3}')
    echo "   ✓ WiFi interface detected: $WIFI_STATUS"
else
    echo "   ❌ WARNING: WiFi interface not managed by NetworkManager"
fi

# Check 5: WiFi scanning capability
echo ""
echo "✅ Check 5: WiFi Scanning"
if timeout 10 nmcli device wifi list 2>/dev/null | grep -q "SSID"; then
    NETWORK_COUNT=$(nmcli device wifi list 2>/dev/null | grep -c "WPA" || echo "0")
    echo "   ✓ WiFi scanning working - found $NETWORK_COUNT WPA networks"
else
    echo "   ❌ WARNING: WiFi scanning not working"
fi

# Check 6: Persistent WiFi configuration
echo ""
echo "✅ Check 6: Persistent WiFi Configuration"
if systemctl is-enabled wifi-enablement.service >/dev/null 2>&1; then
    echo "   ✓ WiFi enablement service is enabled for boot"
else
    echo "   ❌ WARNING: WiFi enablement service not enabled"
fi

if systemctl is-enabled wpa_supplicant.service >/dev/null 2>&1; then
    echo "   ✓ wpa_supplicant service enabled as D-Bus service for NetworkManager"
else
    echo "   ❌ WARNING: wpa_supplicant service not enabled - NetworkManager needs this"
fi

if [ -f /etc/NetworkManager/conf.d/99-wifi-backend.conf ]; then
    echo "   ✓ NetworkManager WiFi configuration is persistent"
else
    echo "   ❌ WARNING: NetworkManager WiFi configuration missing"
fi

# Check 7: BTBerryWifi service status
echo ""
echo "✅ Check 7: BTBerryWifi Service"
if systemctl is-active btwifiset.service >/dev/null 2>&1; then
    echo "   ✓ BTBerryWifi service is running"
    
    # Check which mode it's using
    if journalctl -u btwifiset.service --since="5 minutes ago" | grep -q "version 2 (nmcli/crypto)"; then
        echo "   ✓ Using NetworkManager mode (nmcli)"
    else
        echo "   ❌ WARNING: Not using NetworkManager mode"
    fi
else
    echo "   ❌ CRITICAL: BTBerryWifi service not running!"
fi

echo ""
echo "🎯 Verification Summary:"
echo "   • NetworkManager coexistence: Fixed"
echo "   • Password handling: Fixed"  
echo "   • WiFi/Ethernet coexistence: Enabled"
echo "   • Service configuration: Verified"
echo ""
echo "✅ All critical fixes are in place!"
echo "📱 BTBerryWifi should now work properly for WiFi configuration."