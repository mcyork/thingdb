#!/bin/bash
# WiFi Test Script for BTBerryWifi
# This script tests the WiFi setup to ensure BTBerryWifi can scan and connect

echo "🔍 Testing WiFi setup for BTBerryWifi..."

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "❌ This script must be run as root or with sudo"
    exit 1
fi

echo ""
echo "📡 Checking WiFi interface status..."

# Check if wlan0 exists
if [ ! -e /sys/class/net/wlan0 ]; then
    echo "❌ WiFi interface wlan0 not found"
    echo "   This Pi may not have WiFi capability"
    exit 1
fi

echo "✅ WiFi interface wlan0 found"

# Check interface status
INTERFACE_STATUS=$(ip link show wlan0 | grep -o "state [A-Z]*")
echo "   Interface status: $INTERFACE_STATUS"

# Check RF-kill status
echo ""
echo "🔒 Checking RF-kill status..."
if command -v rfkill >/dev/null 2>&1; then
    RFKILL_STATUS=$(rfkill list wifi | grep -o "blocked: [a-z]*")
    echo "   RF-kill status: $RFKILL_STATUS"
    
    if echo "$RFKILL_STATUS" | grep -q "blocked: yes"; then
        echo "   ⚠️  WiFi is blocked by RF-kill, unblocking..."
        rfkill unblock wifi
        sleep 2
    fi
else
    echo "   ⚠️  rfkill command not available"
fi

# Check wpa_supplicant status
echo ""
echo "📱 Checking wpa_supplicant status..."
if [ -f /var/run/wpa_supplicant.pid ]; then
    PID=$(cat /var/run/wpa_supplicant.pid)
    if ps -p $PID > /dev/null 2>&1; then
        echo "✅ wpa_supplicant is running (PID: $PID)"
    else
        echo "❌ wpa_supplicant PID file exists but process not running"
        echo "   Starting wpa_supplicant..."
        wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf -P /var/run/wpa_supplicant.pid
        sleep 3
    fi
else
    echo "❌ wpa_supplicant not running"
    echo "   Starting wpa_supplicant..."
    wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf -P /var/run/wpa_supplicant.pid
    sleep 3
fi

# Test wpa_supplicant interface management
echo ""
echo "🔧 Testing wpa_supplicant interface management..."
if wpa_cli -i wlan0 status 2>/dev/null | grep -q "wpa_state"; then
    WPA_STATE=$(wpa_cli -i wlan0 status | grep "wpa_state" | cut -d= -f2)
    echo "✅ wpa_supplicant managing wlan0 (state: $WPA_STATE)"
else
    echo "❌ wpa_supplicant not managing wlan0 interface"
    exit 1
fi

# Test WiFi scanning
echo ""
echo "📶 Testing WiFi scanning capability..."
echo "   Scanning for networks (this may take a few seconds)..."
SCAN_RESULT=$(timeout 15 iwlist wlan0 scan 2>/dev/null | grep -c "ESSID" || echo "0")

if [ "$SCAN_RESULT" -gt 0 ]; then
    echo "✅ WiFi scanning working - found $SCAN_RESULT networks"
    
    # Show some network names
    echo "   Sample networks found:"
    iwlist wlan0 scan 2>/dev/null | grep "ESSID" | head -5 | sed 's/.*ESSID:"\([^"]*\)".*/     - \1/'
else
    echo "❌ WiFi scanning failed - no networks found"
    echo "   This may indicate a hardware or driver issue"
fi

# Test wpa_supplicant scanning
echo ""
echo "📱 Testing wpa_supplicant scanning..."
echo "   Triggering wpa_supplicant scan..."
if wpa_cli -i wlan0 scan >/dev/null 2>&1; then
    echo "✅ wpa_supplicant scan triggered successfully"
    
    echo "   Waiting for scan results..."
    sleep 3
    
    SCAN_RESULTS=$(wpa_cli -i wlan0 scan_results 2>/dev/null | grep -c "ESSID" || echo "0")
    if [ "$SCAN_RESULT" -gt 0 ]; then
        echo "✅ wpa_supplicant scan results available - found $SCAN_RESULTS networks"
    else
        echo "❌ wpa_supplicant scan results empty"
    fi
else
    echo "❌ wpa_supplicant scan failed"
fi

# Check BTBerryWifi service
echo ""
echo "🔵 Checking BTBerryWifi service..."
if systemctl is-active --quiet btwifiset.service; then
    echo "✅ BTBerryWifi service is running"
    
    # Check if it's using wpa_supplicant method
    if grep -q "return False  # Force wpa_supplicant method" /usr/local/btwifiset/btwifiset.py; then
        echo "✅ BTBerryWifi configured to use wpa_supplicant method"
    else
        echo "❌ BTBerryWifi not configured to use wpa_supplicant method"
        echo "   This may cause connection issues"
    fi
else
    echo "❌ BTBerryWifi service not running"
    echo "   Start it with: sudo systemctl start btwifiset.service"
fi

echo ""
echo "🎯 WiFi Setup Test Complete!"
echo ""
echo "📋 Summary:"
echo "   • WiFi Interface: $(ip link show wlan0 | grep -o "state [A-Z]*" | cut -d' ' -f2)"
echo "   • wpa_supplicant: $(wpa_cli -i wlan0 status 2>/dev/null | grep "wpa_state" | cut -d= -f2 || echo "UNKNOWN")"
echo "   • WiFi Scanning: $(if [ "$SCAN_RESULT" -gt 0 ]; then echo "WORKING"; else echo "FAILED"; fi)"
echo "   • BTBerryWifi: $(if systemctl is-active --quiet btwifiset.service; then echo "RUNNING"; else echo "STOPPED"; fi)"
echo ""
echo "💡 If all tests pass, BTBerryWifi should be able to:"
echo "   1. Scan and list WiFi networks"
echo "   2. Accept connection requests"
echo "   3. Connect to selected networks"
echo ""
echo "🔧 If tests fail, check the specific error messages above"
