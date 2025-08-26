#!/bin/bash
# deploy-network-test.sh - Quick deployment and testing of BTBerryWifi network fixes

set -e

PI_HOST="${1:-192.168.43.200}"  
PI_USER="${2:-pi}"

echo "🚀 BTBerryWifi Network Test Deployment"
echo "======================================"
echo "Target: $PI_USER@$PI_HOST"
echo ""

# Check if Pi is accessible
echo "📡 Testing Pi connectivity..."
if ! ssh -o ConnectTimeout=5 "$PI_USER@$PI_HOST" "echo 'Pi is accessible'" 2>/dev/null; then
    echo "❌ Cannot connect to $PI_USER@$PI_HOST"
    echo "   Make sure Pi is online and SSH is enabled"
    exit 1
fi
echo "✅ Pi is accessible"

# Create package if it doesn't exist
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PACKAGE_DIR="/tmp/network-install-package"

if [ ! -d "$PACKAGE_DIR" ]; then
    echo "📦 Creating installation package..."
    "$SCRIPT_DIR/package-network-install.sh"
fi

# Deploy package
echo "📂 Deploying installation package..."
ssh "$PI_USER@$PI_HOST" "rm -rf ~/network-install && mkdir -p ~/network-install"
scp "$PACKAGE_DIR"/* "$PI_USER@$PI_HOST:~/network-install/"

echo "✅ Package deployed!"
echo ""

# Show pre-installation status  
echo "📊 PRE-INSTALLATION STATUS:"
echo "============================="
ssh "$PI_USER@$PI_HOST" "
echo 'Current network services:'
systemctl is-enabled NetworkManager 2>/dev/null | head -1 || echo 'NetworkManager: not found'
systemctl is-enabled systemd-networkd.service 2>/dev/null | head -1 || echo 'systemd-networkd: disabled'
systemctl is-enabled dhcpcd.service 2>/dev/null | head -1 || echo 'dhcpcd: not found'
echo ''
echo 'Current network interfaces:'
ip addr show | grep -E 'eth0|wlan0' -A 1 | grep -E 'eth0|wlan0|inet ' || true
echo ''
echo 'Running network processes:'
ps aux | grep -E '(NetworkManager|dhcp|networkd)' | grep -v grep | head -3 || echo 'None found'
"

echo ""
echo "🛠️ READY TO INSTALL"
echo "==================="
echo ""
echo "Next steps:"
echo "1. SSH to Pi: ssh $PI_USER@$PI_HOST"
echo "2. Install: cd ~/network-install && sudo ./network-install.sh"
echo "3. CRITICAL TEST: sudo reboot"
echo "4. Verify Ethernet comes back up after reboot"
echo "5. Test BTBerryWifi with mobile app"
echo ""

# Offer to run installation automatically
read -p "🤖 Run installation automatically now? [y/N]: " AUTO_INSTALL

if [[ "$AUTO_INSTALL" =~ ^[Yy] ]]; then
    echo ""
    echo "🚀 Running automatic installation..."
    echo "===================================="
    
    ssh "$PI_USER@$PI_HOST" "cd ~/network-install && sudo ./network-install.sh"
    
    echo ""
    echo "📊 POST-INSTALLATION STATUS:"
    echo "============================="
    ssh "$PI_USER@$PI_HOST" "
    echo 'Network services after install:'
    echo '  NetworkManager:' \$(systemctl is-active NetworkManager 2>/dev/null || echo 'inactive')
    echo '  systemd-networkd:' \$(systemctl is-active systemd-networkd.service 2>/dev/null || echo 'masked')  
    echo '  dhcpcd:' \$(systemctl is-active dhcpcd.service 2>/dev/null || echo 'masked')
    echo '  BTBerryWifi:' \$(systemctl is-active btwifiset.service 2>/dev/null || echo 'inactive')
    echo ''
    echo 'Network interfaces after install:'
    ip addr show | grep -E 'eth0|wlan0' -A 1 | grep -E 'eth0|wlan0|inet ' || echo 'No interfaces with IPs'
    echo ''
    echo 'WiFi scan test:'
    timeout 10 nmcli device wifi list | head -3 2>/dev/null || echo 'WiFi scan failed or no WiFi'
    "
    
    echo ""
    echo "🚨 CRITICAL REBOOT TEST REQUIRED!"
    echo "================================="
    echo "The installation is complete, but we MUST test reboot stability."
    echo ""
    echo "What to do next:"
    echo "1. The Pi should be accessible at: $PI_HOST"
    echo "2. SSH is working and BTBerryWifi should be running"  
    echo "3. REBOOT TEST: ssh $PI_USER@$PI_HOST 'sudo reboot'"
    echo "4. Wait 60 seconds for reboot to complete"
    echo "5. Test: ssh $PI_USER@$PI_HOST (should work if Ethernet survives)"
    echo ""
    
    read -p "🔄 Proceed with reboot test now? [y/N]: " REBOOT_TEST
    
    if [[ "$REBOOT_TEST" =~ ^[Yy] ]]; then
        echo ""
        echo "🔄 Initiating reboot test..."
        echo "============================"
        
        ssh "$PI_USER@$PI_HOST" "sudo reboot" || echo "Pi is rebooting..."
        
        echo "⏰ Waiting 60 seconds for reboot to complete..."
        for i in {60..1}; do
            printf "\r   Waiting: %2d seconds" $i
            sleep 1
        done
        printf "\n"
        
        echo ""
        echo "🧪 Testing post-reboot connectivity..."
        echo "====================================="
        
        for attempt in {1..5}; do
            echo "Attempt $attempt/5..."
            if ssh -o ConnectTimeout=10 "$PI_USER@$PI_HOST" "echo 'SUCCESS: Pi accessible after reboot!'" 2>/dev/null; then
                echo "✅ REBOOT TEST PASSED!"
                echo ""
                
                # Show post-reboot status
                ssh "$PI_USER@$PI_HOST" "
                echo '📊 Post-reboot network status:'
                echo '  Ethernet:' \$(ip addr show eth0 | grep 'inet ' | awk '{print \$2}' || echo 'No IP')
                echo '  WiFi:' \$(ip addr show wlan0 | grep 'inet ' | awk '{print \$2}' || echo 'No IP')
                echo '  NetworkManager:' \$(systemctl is-active NetworkManager 2>/dev/null || echo 'inactive')
                echo '  BTBerryWifi:' \$(systemctl is-active btwifiset.service 2>/dev/null || echo 'inactive')
                "
                
                echo ""
                echo "🎉 SUCCESS! Network stability achieved!"
                echo "📱 Now test BTBerryWifi with mobile app"
                break
            else
                echo "❌ Connection failed, waiting 10 seconds..."
                sleep 10
            fi
            
            if [ $attempt -eq 5 ]; then
                echo ""
                echo "🚨 REBOOT TEST FAILED!"
                echo "======================"
                echo "The Pi is not accessible after reboot."
                echo "This indicates the network stability issue persists."
                echo ""
                echo "Troubleshooting needed:"
                echo "- Physical/console access to Pi required"
                echo "- Check systemctl status NetworkManager"  
                echo "- Check ip addr show"
                echo "- May need to adjust the network service conflicts"
            fi
        done
        
    else
        echo "⚠️ Manual reboot test required later"
    fi
    
else
    echo "📋 Manual installation steps:"
    echo "1. ssh $PI_USER@$PI_HOST"
    echo "2. cd ~/network-install"
    echo "3. sudo ./network-install.sh"
    echo "4. sudo reboot"
    echo "5. Test connectivity"
fi

echo ""
echo "🎯 Focus Areas for Testing:"
echo "=========================="
echo "• Ethernet survives reboot (main goal)"
echo "• BTBerryWifi shows single SSIDs (not duplicates)"
echo "• WiFi scanning works properly"
echo "• No service conflicts in systemctl status"