#!/bin/bash
# BTBerryWifi Deployment Verification Script
# This script verifies that the BTBerryWifi service is properly configured and working

echo "🔍 Verifying BTBerryWifi Deployment..."

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "❌ This script must be run as root or with sudo"
    exit 1
fi

echo ""
echo "📱 Checking BTBerryWifi Service..."

# Check if BTBerryWifi service is running
if systemctl is-active --quiet btwifiset.service; then
    echo "✅ BTBerryWifi service is running"
    
    # Check service status
    echo "   Service details:"
    systemctl status btwifiset.service --no-pager | grep -E "(Active|Main PID|Tasks)"
else
    echo "❌ BTBerryWifi service is not running"
    echo "   Attempting to start service..."
    systemctl start btwifiset.service
    sleep 3
    
    if systemctl is-active --quiet btwifiset.service; then
        echo "✅ BTBerryWifi service started successfully"
    else
        echo "❌ Failed to start BTBerryWifi service"
        echo "   Check logs with: journalctl -u btwifiset.service -n 20"
        exit 1
    fi
fi

echo ""
echo "🔵 Checking Bluetooth Configuration..."

# Check if Bluetooth service has the correct configuration
if systemctl show bluetooth --property=ExecStart | grep -q "experimental.*battery"; then
    echo "✅ Bluetooth service configured with --experimental -P battery flags"
else
    echo "❌ Bluetooth service missing required flags"
    echo "   Current configuration:"
    systemctl show bluetooth --property=ExecStart
    echo "   Expected: --experimental -P battery"
fi

# Check if Bluetooth is running
if systemctl is-active --quiet bluetooth; then
    echo "✅ Bluetooth service is running"
else
    echo "❌ Bluetooth service is not running"
    echo "   Starting Bluetooth service..."
    systemctl start bluetooth
    sleep 3
fi

echo ""
echo "📡 Checking WiFi Configuration..."

# Check if wpa_supplicant.conf exists and is correct
if [ -f /etc/wpa_supplicant/wpa_supplicant.conf ]; then
    echo "✅ wpa_supplicant.conf exists"
    
    # Check for required configuration
    if grep -q "ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev" /etc/wpa_supplicant/wpa_supplicant.conf; then
        echo "✅ wpa_supplicant.conf has correct ctrl_interface"
    else
        echo "❌ wpa_supplicant.conf missing ctrl_interface configuration"
    fi
    
    if grep -q "country=US" /etc/wpa_supplicant/wpa_supplicant.conf; then
        echo "✅ wpa_supplicant.conf has country code"
    else
        echo "❌ wpa_supplicant.conf missing country code"
    fi
    
    if grep -q "update_config=1" /etc/wpa_supplicant/wpa_supplicant.conf; then
        echo "✅ wpa_supplicant.conf has update_config enabled"
    else
        echo "❌ wpa_supplicant.conf missing update_config"
    fi
else
    echo "❌ wpa_supplicant.conf not found"
fi

# Check if wpa_supplicant is managing wlan0
if [ -f /var/run/wpa_supplicant.pid ]; then
    PID=$(cat /var/run/wpa_supplicant.pid)
    if ps -p $PID > /dev/null 2>&1; then
        echo "✅ wpa_supplicant is running (PID: $PID)"
        
        # Check if it's managing wlan0
        if wpa_cli -i wlan0 status 2>/dev/null | grep -q "wpa_state"; then
            WPA_STATE=$(wpa_cli -i wlan0 status | grep "wpa_state" | cut -d= -f2)
            echo "✅ wpa_supplicant managing wlan0 (state: $WPA_STATE)"
        else
            echo "❌ wpa_supplicant not managing wlan0 interface"
        fi
    else
        echo "❌ wpa_supplicant PID file exists but process not running"
    fi
else
    echo "❌ wpa_supplicant not running"
    echo "   Starting wpa_supplicant..."
    wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf -P /var/run/wpa_supplicant.pid
    sleep 3
fi

echo ""
echo "🔧 Checking BTBerryWifi Configuration..."

# Check if BTBerryWifi is configured to use wpa_supplicant method
if grep -q "return False  # Force wpa_supplicant method" /usr/local/btwifiset/btwifiset.py; then
    echo "✅ BTBerryWifi configured to use wpa_supplicant method"
else
    echo "❌ BTBerryWifi not configured to use wpa_supplicant method"
    echo "   This will cause connection issues"
fi

echo ""
echo "📶 Testing WiFi Scanning..."

# Test if WiFi scanning works
if command -v iwlist >/dev/null 2>&1; then
    echo "   Testing with iwlist..."
    SCAN_RESULT=$(timeout 10 iwlist wlan0 scan 2>/dev/null | grep -c "ESSID" || echo "0")
    
    if [ "$SCAN_RESULT" -gt 0 ]; then
        echo "✅ WiFi scanning working - found $SCAN_RESULT networks"
    else
        echo "❌ WiFi scanning failed - no networks found"
    fi
else
    echo "❌ iwlist command not available"
fi

# Test wpa_supplicant scanning
echo "   Testing with wpa_supplicant..."
if wpa_cli -i wlan0 scan >/dev/null 2>&1; then
    echo "✅ wpa_supplicant scan triggered successfully"
    sleep 3
    
    SCAN_RESULTS=$(wpa_cli -i wlan0 scan_results 2>/dev/null | grep -c "ESSID" || echo "0")
    if [ "$SCAN_RESULTS" -gt 0 ]; then
        echo "✅ wpa_supplicant scan results available - found $SCAN_RESULTS networks"
    else
        echo "❌ wpa_supplicant scan results empty"
    fi
else
    echo "❌ wpa_supplicant scan failed"
fi

echo ""
echo "🎯 Deployment Verification Complete!"
echo ""
echo "📋 Summary:"
echo "   • BTBerryWifi Service: $(if systemctl is-active --quiet btwifiset.service; then echo "RUNNING"; else echo "STOPPED"; fi)"
echo "   • Bluetooth Configuration: $(if systemctl show bluetooth --property=ExecStart | grep -q "experimental.*battery"; then echo "CORRECT"; else echo "INCORRECT"; fi)"
echo "   • wpa_supplicant: $(if [ -f /var/run/wpa_supplicant.pid ] && ps -p $(cat /var/run/wpa_supplicant.pid) >/dev/null 2>&1; then echo "RUNNING"; else echo "STOPPED"; fi)"
echo "   • WiFi Scanning: $(if [ "$SCAN_RESULT" -gt 0 ] || [ "$SCAN_RESULTS" -gt 0 ]; then echo "WORKING"; else echo "FAILED"; fi)"
echo "   • BTBerryWifi Method: $(if grep -q "return False  # Force wpa_supplicant method" /usr/local/btwifiset/btwifiset.py; then echo "WPA_SUPPLICANT"; else echo "NETWORKMANAGER"; fi)"
echo ""
echo "💡 If all checks pass, BTBerryWifi should work correctly"
echo "🔧 If any checks fail, run the WiFi test script: sudo /usr/local/bin/test-wifi-scan.sh"
echo ""
echo "📱 To test the full functionality:"
echo "   1. Use the BTBerryWifi mobile app"
echo "   2. Connect to the 'inventory' Bluetooth device"
echo "   3. The app should show available WiFi networks"
echo "   4. Select a network and enter password to test connection"
