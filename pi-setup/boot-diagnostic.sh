#!/bin/bash
# boot-diagnostic.sh  
# Boot-time diagnostic that captures network failure to accessible storage
# Place this in /boot/ partition so we can access logs even when Pi is unreachable

BOOT_MOUNT="/boot"
LOG_FILE="$BOOT_MOUNT/network-failure-log.txt"

# Ensure we can write to boot partition
if [ ! -w "$BOOT_MOUNT" ]; then
    echo "Cannot write to $BOOT_MOUNT - trying /boot/firmware"
    BOOT_MOUNT="/boot/firmware"
    LOG_FILE="$BOOT_MOUNT/network-failure-log.txt"
fi

# Create or append to log file
{
    echo "=========================================="
    echo "BOOT DIAGNOSTIC: $(date)"
    echo "=========================================="
    echo ""
    
    echo "Initial Network State:"
    ip addr show 2>/dev/null || echo "IP command failed"
    echo ""
    
    echo "Initial Service Status:"
    systemctl is-active NetworkManager 2>/dev/null || echo "NetworkManager inactive"
    systemctl is-active btwifiset.service 2>/dev/null || echo "BTBerryWifi inactive" 
    systemctl is-active wpa_supplicant.service 2>/dev/null || echo "wpa_supplicant inactive"
    echo ""
    
    echo "Initial Process List:"
    ps aux | grep -E "(NetworkManager|wpa_supplicant|dhcp)" | grep -v grep
    echo ""
    
    echo "Initial Routing:"
    ip route show 2>/dev/null || echo "No routes"
    echo ""
    
    echo "Bluetooth Status:"
    systemctl is-active bluetooth 2>/dev/null || echo "Bluetooth inactive"
    hciconfig 2>/dev/null || echo "No Bluetooth interfaces"
    echo ""
    
    # Monitor for network failures every 30 seconds
    echo "Starting continuous monitoring..."
    for i in $(seq 1 240); do  # Monitor for 2 hours
        TIMESTAMP=$(date '+%H:%M:%S')
        
        # Quick health check
        NM_STATUS=$(systemctl is-active NetworkManager 2>/dev/null || echo "dead")
        ETH_STATE=$(cat /sys/class/net/eth0/operstate 2>/dev/null || echo "missing")
        WLAN_STATE=$(cat /sys/class/net/wlan0/operstate 2>/dev/null || echo "missing") 
        ROUTE_COUNT=$(ip route show 2>/dev/null | wc -l || echo "0")
        
        echo "[$TIMESTAMP] NM:$NM_STATUS eth0:$ETH_STATE wlan0:$WLAN_STATE routes:$ROUTE_COUNT"
        
        # Check for critical failures
        if [ "$NM_STATUS" = "dead" ] || [ "$ROUTE_COUNT" = "0" ]; then
            echo "[$TIMESTAMP] CRITICAL FAILURE DETECTED!"
            echo "  Full network state:"
            ip addr show 2>/dev/null || echo "  IP command failed"
            echo "  Process snapshot:"
            ps aux | grep -E "(NetworkManager|wpa_supplicant)" | grep -v grep
            echo "  Recent logs:"
            journalctl --since="5 minutes ago" -n 50 --no-pager 2>/dev/null || echo "  Cannot access journal"
            echo ""
        fi
        
        sleep 30
    done
    
    echo "Boot diagnostic monitoring completed"
    echo "=========================================="
    
} >> "$LOG_FILE" 2>&1 &

# Also create a simple status indicator
echo "Boot diagnostic started at $(date)" > "$BOOT_MOUNT/diagnostic-status.txt"