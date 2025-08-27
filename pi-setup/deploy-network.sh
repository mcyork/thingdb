#!/bin/bash
# deploy-network.sh - Deploy and test BTBerryWifi network installation

set -e

# Show usage if help is requested
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo "Usage: $0 [PI_TARGET]"
    echo ""
    echo "Deploy and test BTBerryWifi network installation on specified Raspberry Pi"
    echo ""
    echo "Arguments:"
    echo "  PI_TARGET    Name of the Pi to target (default: pi2)"
    echo ""
    echo "Examples:"
    echo "  $0           # Use default pi2"
    echo "  $0 pi1      # Target pi1"
    echo "  $0 pi2      # Target pi2"
    echo "  $0 epi1     # Target epi1"
    echo ""
    echo "Available Pis:"
    pi list
    exit 0
fi

# Get Pi target from command line argument, default to pi2
PI_TARGET=${1:-pi2}

echo "🚀 Deploying BTBerryWifi Network Installation"
echo "==========================================="
echo "Target Pi: $PI_TARGET"

# Validate Pi target
if ! pi list | grep -q "^$PI_TARGET"; then
    echo "❌ Error: Pi '$PI_TARGET' not found in configuration"
    echo "Available Pis:"
    pi list
    exit 1
fi

# Check if Pi is online
if ! pi status "$PI_TARGET" | grep -q "ONLINE"; then
    echo "❌ Error: Pi '$PI_TARGET' is not online"
    echo "Current status:"
    pi status "$PI_TARGET"
    exit 1
fi

echo "✅ Pi '$PI_TARGET' is online and ready"

# Show pre-installation status
echo "📊 PRE-INSTALLATION STATUS:"
pi run --pi "$PI_TARGET" "
echo 'Network services:'
systemctl is-enabled NetworkManager 2>/dev/null | head -1 || echo 'NetworkManager: not found'
systemctl is-enabled systemd-networkd.service 2>/dev/null | head -1 || echo 'systemd-networkd: disabled'  
systemctl is-enabled dhcpcd.service 2>/dev/null | head -1 || echo 'dhcpcd: not found'
echo ''
echo 'Network interfaces:'
ip addr show | grep -E 'eth0|wlan0' -A 1 | grep -E 'eth0|wlan0|inet ' || echo 'No interfaces with IPs'
echo ''
echo 'Network processes:'
ps aux | grep -E '(NetworkManager|dhcp|networkd)' | grep -v grep | head -3 || echo 'None'
"

echo ""
echo "🛠️ RUNNING INSTALLATION..."
pi run --pi "$PI_TARGET" "cd /tmp && sudo ./network-install.sh"

echo ""
echo "📊 POST-INSTALLATION STATUS:"
pi run --pi "$PI_TARGET" "
echo 'Service status:'
echo '  NetworkManager:' \$(systemctl is-active NetworkManager 2>/dev/null)
echo '  systemd-networkd:' \$(systemctl is-active systemd-networkd.service 2>/dev/null || echo 'masked')
echo '  dhcpcd:' \$(systemctl is-active dhcpcd.service 2>/dev/null || echo 'masked')  
echo '  BTBerryWifi:' \$(systemctl is-active btwifiset.service 2>/dev/null)
echo ''
echo 'Network interfaces:'
ip addr show | grep -E 'eth0|wlan0' -A 1 | grep -E 'eth0|wlan0|inet ' || echo 'No IPs assigned'
echo ''
echo 'WiFi scan test:'
timeout 10 nmcli device wifi list 2>/dev/null | head -3 || echo 'WiFi scan failed'
echo ''
echo 'BTBerryWifi mode check:'
journalctl -u btwifiset.service -n 5 --no-pager | grep -E '(version|NetworkManager)' || echo 'No version info'
"

echo ""
echo "🔄 CRITICAL REBOOT TEST"
echo "======================="
echo "Testing network stability after reboot..."

# Using specified Pi for reboot test
echo "Initiating reboot..."
pi run --pi "$PI_TARGET" "sudo reboot" || echo "Reboot command sent"

echo "⏰ Waiting for reboot to complete..."
sleep 60

echo "🧪 Testing post-reboot connectivity..."
for attempt in {1..10}; do
    echo "Attempt $attempt/10..."
    if pi run --pi "$PI_TARGET" "echo 'Pi is back online!'" 2>/dev/null; then
        echo "✅ REBOOT TEST PASSED - Pi is accessible!"
        break
    elif [ $attempt -eq 10 ]; then
        echo "🚨 REBOOT TEST FAILED - Pi not accessible after reboot"
        echo "This indicates network stability issues persist"
        exit 1
    else
        sleep 10
    fi
done

echo ""
echo "📊 POST-REBOOT NETWORK STATUS:"
pi run --pi "$PI_TARGET" "
echo 'Interface status:'
echo '  Ethernet:' \$(ip addr show eth0 | grep 'inet ' | awk '{print \$2}' || echo 'No IP')
echo '  WiFi:' \$(ip addr show wlan0 | grep 'inet ' | awk '{print \$2}' || echo 'No IP')
echo ''
echo 'Service status:'
echo '  NetworkManager:' \$(systemctl is-active NetworkManager)
echo '  BTBerryWifi:' \$(systemctl is-active btwifiset.service)
echo ''
echo 'BTBerryWifi scanning mode:'
journalctl -u btwifiset.service --since='2 minutes ago' --no-pager | grep -E '(version|NetworkManager|nmcli)' | head -3 || echo 'No recent logs'
echo ''
echo 'WiFi networks found:'
timeout 10 nmcli device wifi list 2>/dev/null | wc -l || echo 'Scan failed'
"

echo ""
echo "🎯 SSID SCANNING INVESTIGATION:"
echo "==============================="
pi run --pi "$PI_TARGET" "
echo 'Testing direct NetworkManager scan:'
nmcli -t device wifi list 2>/dev/null | head -5 | while IFS=':' read -r bssid freq rate signal bars security active ssid mode; do
    echo \"  SSID: \$ssid (Signal: \$signal)\"
done
echo ''
echo 'BTBerryWifi service logs for scanning behavior:'
journalctl -u btwifiset.service --since='5 minutes ago' --no-pager | grep -E '(scan|SSID|AP|network)' | tail -10 || echo 'No scanning logs found'
"

echo ""
echo "✅ NETWORK DEPLOYMENT COMPLETE!"
echo "==============================="
echo ""
echo "🧪 Test Results Summary:"
echo "• Ethernet connectivity: $(pi run --pi "$PI_TARGET" "ip addr show eth0 | grep 'inet ' >/dev/null 2>&1 && echo 'WORKING' || echo 'FAILED')"
echo "• NetworkManager active: $(pi run --pi "$PI_TARGET" "systemctl is-active NetworkManager 2>/dev/null")"
echo "• BTBerryWifi service: $(pi run --pi "$PI_TARGET" "systemctl is-active btwifiset.service 2>/dev/null")"
echo "• Reboot stability: PASSED"
echo ""
echo "📱 Next Steps:"
echo "• Test BTBerryWifi with mobile app"
echo "• Check for single vs duplicate SSIDs"
echo "• Verify NetworkManager mode is being used"