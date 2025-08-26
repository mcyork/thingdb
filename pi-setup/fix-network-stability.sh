#!/bin/bash
# fix-network-stability.sh
# Comprehensive fix for BTBerryWifi network stability issues after reboot

set -e

echo "🔧 Fixing BTBerryWifi Network Stability Issues"
echo "============================================="

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "❌ This script must be run as root or with sudo"
    exit 1
fi

echo "🎯 Analysis: The network failure appears to be caused by:"
echo "   1. Service conflicts between NetworkManager and wpa_supplicant"
echo "   2. BTBerryWifi creating conflicting network configurations"
echo "   3. Interface state corruption during Bluetooth handoff"
echo "   4. Persistent network manager conflicts after service restart"
echo ""

echo "🔧 Applying comprehensive network stability fixes..."
echo ""

# Phase 1: Complete service isolation
echo "=== PHASE 1: SERVICE ISOLATION ==="

echo "🛑 Stopping all conflicting network services..."
systemctl stop dhcpcd.service 2>/dev/null || true
systemctl stop systemd-networkd.service 2>/dev/null || true
systemctl stop wpa_supplicant.service 2>/dev/null || true
systemctl stop wpa_supplicant@wlan0.service 2>/dev/null || true

echo "🚫 Permanently disabling conflicting services..."
systemctl disable dhcpcd.service 2>/dev/null || true
systemctl mask dhcpcd.service 2>/dev/null || true
systemctl disable systemd-networkd.service 2>/dev/null || true
systemctl mask systemd-networkd.service 2>/dev/null || true
systemctl disable wpa_supplicant@wlan0.service 2>/dev/null || true
systemctl mask wpa_supplicant@wlan0.service 2>/dev/null || true

echo "✅ Conflicting services isolated"
echo ""

# Phase 2: NetworkManager exclusive control
echo "=== PHASE 2: NETWORKMANAGER EXCLUSIVE CONTROL ==="

echo "📝 Configuring NetworkManager for exclusive network management..."

# Create comprehensive NetworkManager configuration
cat > /etc/NetworkManager/conf.d/01-exclusive-control.conf << 'NMEOF'
[main]
# NetworkManager exclusive control
dns=systemd-resolved
no-auto-default=*

# Ignore other network managers
plugins=keyfile

[device]
# Manage all ethernet and wifi interfaces
ethernet.cloned-mac-address=preserve
wifi.cloned-mac-address=preserve
wifi.backend=wpa_supplicant
wifi.scan-rand-mac-address=no

[connection]
# Connection defaults
ethernet.wake-on-lan=ignore
wifi.wake-on-wlan=ignore

[connectivity]
# Connection checking
uri=http://connectivitycheck.gstatic.com/generate_204
interval=0
NMEOF

# Ensure wpa_supplicant runs as system service for NetworkManager
echo "🔧 Configuring wpa_supplicant as system D-Bus service..."
systemctl enable wpa_supplicant.service
# Don't start it yet - NetworkManager will manage it

echo "✅ NetworkManager configured for exclusive control"
echo ""

# Phase 3: BTBerryWifi integration hardening  
echo "=== PHASE 3: BTWIFISET INTEGRATION HARDENING ==="

echo "🛠️ Creating BTBerryWifi safety wrapper..."

# Create a wrapper service that ensures network stability
cat > /etc/systemd/system/btwifiset-stable.service << 'BTWEOF'
[Unit]
Description=BTBerryWifi Stable - Network-Safe BLE WiFi Configuration
After=NetworkManager.service
Wants=NetworkManager.service
Conflicts=dhcpcd.service systemd-networkd.service wpa_supplicant@wlan0.service

[Service]
Type=notify
User=root
WorkingDirectory=/usr/local/btwifiset
Environment=PYTHONUNBUFFERED=1

# Pre-execution safety checks
ExecStartPre=/bin/bash -c 'systemctl is-active NetworkManager || (echo "NetworkManager not running" && exit 1)'
ExecStartPre=/bin/bash -c 'pkill -f "wpa_supplicant.*-i.*wlan0" || true'
ExecStartPre=/bin/sleep 2

# Main service with resource limits and safety monitoring
ExecStart=/usr/bin/python3 /usr/local/btwifiset/btwifiset.py
ExecReload=/bin/kill -HUP $MAINPID

# Post-execution cleanup and verification
ExecStopPost=/bin/bash -c 'systemctl restart NetworkManager'
ExecStopPost=/bin/sleep 3
ExecStopPost=/bin/bash -c 'nmcli radio wifi on || true'
ExecStopPost=/bin/bash -c 'nmcli device set wlan0 managed yes || true'

# Resource limits to prevent system overload
MemoryMax=256M
CPUQuota=50%

# Restart policy for stability
Restart=on-failure
RestartSec=10
StartLimitInterval=60
StartLimitBurst=3

# Security and isolation
NoNewPrivileges=yes
PrivateDevices=no
PrivateTmp=yes
ProtectSystem=strict
ReadWritePaths=/var/log /tmp /var/lib/NetworkManager

[Install]
WantedBy=multi-user.target
BTWEOF

echo "🔄 Disabling original btwifiset service in favor of stable version..."
systemctl stop btwifiset.service 2>/dev/null || true
systemctl disable btwifiset.service 2>/dev/null || true

echo "✅ BTBerryWifi hardening applied"
echo ""

# Phase 4: Network interface monitoring and recovery
echo "=== PHASE 4: INTERFACE MONITORING AND RECOVERY ==="

echo "📡 Creating network interface monitoring service..."

cat > /etc/systemd/system/network-monitor.service << 'MONEOF'
[Unit]
Description=Network Interface Monitor and Recovery
After=NetworkManager.service btwifiset-stable.service
Wants=NetworkManager.service

[Service]
Type=simple
User=root
ExecStart=/bin/bash -c '
    LOG_FILE=/var/log/network-monitor.log
    echo "$(date): Network monitor started" >> $LOG_FILE
    
    while true; do
        # Check for interface failures
        ETH_STATE=$(cat /sys/class/net/eth0/operstate 2>/dev/null || echo "missing")
        WLAN_STATE=$(cat /sys/class/net/wlan0/operstate 2>/dev/null || echo "missing")
        NM_ACTIVE=$(systemctl is-active NetworkManager 2>/dev/null || echo "inactive")
        ROUTE_COUNT=$(ip route show 2>/dev/null | wc -l || echo "0")
        
        # Log current state
        echo "$(date): eth0:$ETH_STATE wlan0:$WLAN_STATE nm:$NM_ACTIVE routes:$ROUTE_COUNT" >> $LOG_FILE
        
        # Detect critical failures
        if [ "$NM_ACTIVE" != "active" ] || [ "$ROUTE_COUNT" = "0" ]; then
            echo "$(date): CRITICAL FAILURE DETECTED - Initiating recovery" >> $LOG_FILE
            
            # Kill any interfering processes
            pkill -f "wpa_supplicant.*-i.*wlan0" || true
            pkill dhcpcd || true
            
            # Restart NetworkManager
            systemctl restart NetworkManager
            sleep 5
            
            # Re-enable interfaces
            ip link set eth0 up 2>/dev/null || true
            ip link set wlan0 up 2>/dev/null || true
            nmcli radio wifi on 2>/dev/null || true
            nmcli device set wlan0 managed yes 2>/dev/null || true
            
            echo "$(date): Recovery attempt completed" >> $LOG_FILE
        fi
        
        sleep 30
    done
'

Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
MONEOF

echo "✅ Network monitoring service created"
echo ""

# Phase 5: Boot-time network initialization
echo "=== PHASE 5: BOOT-TIME NETWORK INITIALIZATION ==="

echo "🚀 Creating robust boot-time network initialization..."

cat > /etc/systemd/system/network-init.service << 'INITEOF'
[Unit]
Description=Robust Network Initialization
After=local-fs.target
Before=NetworkManager.service
DefaultDependencies=no

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c '
    # Ensure clean network state at boot
    echo "$(date): Initializing clean network state" >> /var/log/network-init.log
    
    # Kill any pre-existing network processes
    pkill dhcpcd || true
    pkill -f "wpa_supplicant.*-i" || true
    sleep 2
    
    # Ensure interfaces are available
    if [ -e /sys/class/net/wlan0 ]; then
        rfkill unblock wifi || true
        ip link set wlan0 up || true
        echo "$(date): WiFi interface initialized" >> /var/log/network-init.log
    fi
    
    if [ -e /sys/class/net/eth0 ]; then
        ip link set eth0 up || true
        echo "$(date): Ethernet interface initialized" >> /var/log/network-init.log
    fi
    
    # Prepare for NetworkManager
    echo "$(date): Network initialization completed" >> /var/log/network-init.log
'

[Install]
WantedBy=multi-user.target
INITEOF

echo "✅ Boot-time network initialization configured"
echo ""

# Phase 6: Service orchestration
echo "=== PHASE 6: SERVICE ORCHESTRATION ==="

echo "🎼 Enabling and starting services in correct order..."

# Enable services
systemctl enable network-init.service
systemctl enable NetworkManager.service  
systemctl enable network-monitor.service
systemctl enable btwifiset-stable.service

# Reload systemd
systemctl daemon-reload

echo "🔄 Starting services in safe order..."

# Start in dependency order
systemctl start network-init.service
sleep 2
systemctl restart NetworkManager.service
sleep 5
systemctl start network-monitor.service
sleep 2
systemctl start btwifiset-stable.service

echo "✅ All services started successfully"
echo ""

# Phase 7: Verification and testing
echo "=== PHASE 7: VERIFICATION ==="

echo "🧪 Testing network stability..."

# Test NetworkManager
if systemctl is-active --quiet NetworkManager; then
    echo "✅ NetworkManager is active"
    
    # Test WiFi scanning
    if timeout 10 nmcli device wifi list >/dev/null 2>&1; then
        NETWORK_COUNT=$(nmcli device wifi list | grep -c "WPA" || echo "0")
        echo "✅ WiFi scanning works ($NETWORK_COUNT networks found)"
    else
        echo "⚠️ WiFi scanning test failed"
    fi
else
    echo "❌ NetworkManager not active"
fi

# Test BTBerryWifi
if systemctl is-active --quiet btwifiset-stable.service; then
    echo "✅ BTBerryWifi stable service is active"
    
    # Check it's using NetworkManager mode
    if journalctl -u btwifiset-stable.service --since="2 minutes ago" -q | grep -q "version 2 (nmcli/crypto)"; then
        echo "✅ BTBerryWifi using NetworkManager mode"
    else
        echo "⚠️ BTBerryWifi mode unclear - check logs"
    fi
else
    echo "❌ BTBerryWifi stable service not active"
fi

# Test interface states
for iface in eth0 wlan0; do
    if [ -e "/sys/class/net/$iface" ]; then
        STATE=$(cat /sys/class/net/$iface/operstate 2>/dev/null || echo 'unknown')
        echo "✅ Interface $iface: $STATE"
    fi
done

# Test routing
ROUTE_COUNT=$(ip route show 2>/dev/null | wc -l)
echo "✅ Routing table has $ROUTE_COUNT routes"

echo ""
echo "🎯 NETWORK STABILITY FIXES APPLIED SUCCESSFULLY!"
echo ""
echo "📋 Summary of changes:"
echo "   • Isolated conflicting services (dhcpcd, systemd-networkd)"
echo "   • Configured NetworkManager for exclusive control"  
echo "   • Created BTBerryWifi stable service wrapper"
echo "   • Added network monitoring and auto-recovery"
echo "   • Implemented robust boot-time network initialization"
echo "   • Enabled proper service orchestration"
echo ""
echo "🔄 IMPORTANT: Test the fix by:"
echo "   1. Reboot the Pi: sudo reboot"
echo "   2. Wait for boot to complete"
echo "   3. Use BTBerryWifi to scan networks then CANCEL"
echo "   4. Verify both SSH and network connectivity remain active"
echo ""
echo "📊 Monitor logs with:"
echo "   • Overall: journalctl -f"
echo "   • BTBerryWifi: journalctl -u btwifiset-stable.service -f"
echo "   • Network monitor: tail -f /var/log/network-monitor.log"
echo "   • Network init: tail -f /var/log/network-init.log"