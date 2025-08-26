#!/bin/bash
# diagnose-network-failure.sh
# Comprehensive diagnostic script to identify why BTBerryWifi causes network failure after reboot

set -e

echo "🔍 Comprehensive Network Failure Diagnostic"
echo "==========================================="

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "❌ This script must be run as root or with sudo"
    exit 1
fi

LOG_DIR="/var/log/network-diagnostics"
mkdir -p "$LOG_DIR"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
DIAG_FILE="$LOG_DIR/network_diagnostic_$TIMESTAMP.log"

echo "📝 Logging diagnostics to: $DIAG_FILE"
exec > >(tee -a "$DIAG_FILE") 2>&1

echo ""
echo "🕐 Diagnostic started at: $(date)"
echo ""

# Phase 1: Pre-BTBerryWifi baseline
echo "=== PHASE 1: PRE-BTWIFISET BASELINE ==="
echo ""

echo "📡 Network Interfaces Status:"
ip addr show | grep -E "^[0-9]+:|inet " || true
echo ""

echo "📊 Network Interface Details:"
for iface in eth0 wlan0; do
    if [ -e "/sys/class/net/$iface" ]; then
        echo "  $iface:"
        echo "    - State: $(cat /sys/class/net/$iface/operstate 2>/dev/null || echo 'unknown')"
        echo "    - Carrier: $(cat /sys/class/net/$iface/carrier 2>/dev/null || echo 'unknown')"
        echo "    - Address: $(cat /sys/class/net/$iface/address 2>/dev/null || echo 'unknown')"
        echo "    - MTU: $(cat /sys/class/net/$iface/mtu 2>/dev/null || echo 'unknown')"
    else
        echo "  $iface: NOT FOUND"
    fi
done
echo ""

echo "🔧 Service Status (Before):"
for service in NetworkManager wpa_supplicant.service wpa_supplicant@wlan0.service btwifiset.service dhcpcd.service systemd-networkd.service; do
    STATUS=$(systemctl is-active "$service" 2>/dev/null || echo "inactive")
    ENABLED=$(systemctl is-enabled "$service" 2>/dev/null || echo "disabled")
    MASKED=$(systemctl is-masked "$service" 2>/dev/null && echo " [MASKED]" || echo "")
    echo "  $service: $STATUS ($ENABLED)$MASKED"
done
echo ""

echo "📋 Active Network Processes:"
ps aux | grep -E "(NetworkManager|wpa_supplicant|dhcp)" | grep -v grep || echo "  No network processes found"
echo ""

echo "🌐 Routing Table:"
ip route show || true
echo ""

echo "🔍 NetworkManager Device Status:"
if systemctl is-active --quiet NetworkManager; then
    nmcli device status 2>/dev/null || echo "  nmcli failed"
    echo ""
    echo "🔍 NetworkManager General Status:"
    nmcli general status 2>/dev/null || echo "  nmcli general failed"
else
    echo "  NetworkManager not running"
fi
echo ""

echo "🔒 RF Kill Status:"
if command -v rfkill >/dev/null 2>&1; then
    rfkill list all || echo "  rfkill failed"
else
    echo "  rfkill command not available"
fi
echo ""

# Phase 2: BTBerryWifi interaction monitoring
echo "=== PHASE 2: BTWIFISET INTERACTION MONITORING ==="
echo ""

echo "🎯 Starting BTBerryWifi monitoring..."
echo "📱 Please use BTBerryWifi app to scan for networks, then CANCEL the operation"
echo "⏰ Monitoring for 120 seconds..."

# Monitor logs in background
journalctl -u btwifiset.service -f --since="now" > "$LOG_DIR/btwifiset_interaction_$TIMESTAMP.log" 2>&1 &
JOURNAL_PID=$!

# Monitor NetworkManager in background  
if systemctl is-active --quiet NetworkManager; then
    journalctl -u NetworkManager -f --since="now" > "$LOG_DIR/networkmanager_interaction_$TIMESTAMP.log" 2>&1 &
    NM_PID=$!
fi

# Monitor interface state changes
MONITOR_FILE="$LOG_DIR/interface_changes_$TIMESTAMP.log"
echo "$(date): Starting interface monitoring" > "$MONITOR_FILE"

for i in $(seq 1 120); do
    echo "--- Second $i ---" >> "$MONITOR_FILE"
    
    # Check interface states
    for iface in eth0 wlan0; do
        if [ -e "/sys/class/net/$iface" ]; then
            STATE=$(cat /sys/class/net/$iface/operstate 2>/dev/null || echo 'unknown')
            CARRIER=$(cat /sys/class/net/$iface/carrier 2>/dev/null || echo 'unknown')
            echo "$iface: state=$STATE carrier=$CARRIER" >> "$MONITOR_FILE"
        fi
    done
    
    # Check if interfaces disappear or change
    IP_STATUS=$(ip addr show 2>/dev/null | grep -E "^[0-9]+: (eth0|wlan0)" || echo "interfaces missing")
    echo "IP interfaces: $IP_STATUS" >> "$MONITOR_FILE"
    
    # Check routing table changes
    ROUTES=$(ip route show 2>/dev/null | wc -l)
    echo "Route count: $ROUTES" >> "$MONITOR_FILE"
    
    sleep 1
done

# Stop background monitoring
kill $JOURNAL_PID 2>/dev/null || true
kill $NM_PID 2>/dev/null || true

echo ""
echo "⏰ Monitoring period completed"

# Phase 3: Post-interaction analysis
echo ""
echo "=== PHASE 3: POST-INTERACTION ANALYSIS ==="
echo ""

echo "📡 Network Interfaces Status (After):"
ip addr show | grep -E "^[0-9]+:|inet " || echo "  IP command failed or no interfaces"
echo ""

echo "🔧 Service Status (After):"
for service in NetworkManager wpa_supplicant.service wpa_supplicant@wlan0.service btwifiset.service dhcpcd.service systemd-networkd.service; do
    STATUS=$(systemctl is-active "$service" 2>/dev/null || echo "inactive")
    ENABLED=$(systemctl is-enabled "$service" 2>/dev/null || echo "disabled")
    MASKED=$(systemctl is-masked "$service" 2>/dev/null && echo " [MASKED]" || echo "")
    echo "  $service: $STATUS ($ENABLED)$MASKED"
done
echo ""

echo "🌐 Routing Table (After):"
ip route show || echo "  No routes or ip command failed"
echo ""

echo "🔍 NetworkManager Status (After):"
if systemctl is-active --quiet NetworkManager; then
    nmcli device status 2>/dev/null || echo "  nmcli device failed"
    nmcli general status 2>/dev/null || echo "  nmcli general failed"
else
    echo "  NetworkManager not running"
fi
echo ""

# Phase 4: Critical failure detection
echo "=== PHASE 4: FAILURE PATTERN ANALYSIS ==="
echo ""

# Check for common failure patterns
echo "🔍 Analyzing failure patterns..."

# Check if NetworkManager crashed
if ! systemctl is-active --quiet NetworkManager; then
    echo "❌ CRITICAL: NetworkManager is no longer running!"
    echo "   Last NetworkManager logs:"
    journalctl -u NetworkManager -n 20 --no-pager || echo "   Could not retrieve logs"
fi

# Check if wpa_supplicant processes are interfering
WPA_PROCESSES=$(pgrep -f wpa_supplicant | wc -l)
if [ "$WPA_PROCESSES" -gt 1 ]; then
    echo "⚠️ WARNING: Multiple wpa_supplicant processes detected ($WPA_PROCESSES)"
    ps aux | grep wpa_supplicant | grep -v grep
fi

# Check if interfaces are down
for iface in eth0 wlan0; do
    if [ -e "/sys/class/net/$iface" ]; then
        STATE=$(cat /sys/class/net/$iface/operstate 2>/dev/null || echo 'unknown')
        if [ "$STATE" = "down" ]; then
            echo "❌ CRITICAL: Interface $iface is DOWN"
        fi
    fi
done

# Check for routing table corruption
ROUTE_COUNT=$(ip route show 2>/dev/null | wc -l)
if [ "$ROUTE_COUNT" -eq 0 ]; then
    echo "❌ CRITICAL: No routes in routing table!"
fi

# Check for DHCP client issues
if pgrep dhcpcd >/dev/null 2>&1; then
    echo "⚠️ WARNING: dhcpcd is running (may conflict with NetworkManager)"
fi

echo ""
echo "=== PHASE 5: RECOVERY RECOMMENDATIONS ==="
echo ""

echo "🔧 Immediate recovery steps:"
echo "1. Restart NetworkManager: systemctl restart NetworkManager"
echo "2. Bring up interfaces: ip link set eth0 up; ip link set wlan0 up"
echo "3. Kill conflicting processes: pkill -f 'wpa_supplicant.*-i.*wlan0'"
echo "4. Restart BTBerryWifi: systemctl restart btwifiset.service"
echo ""

echo "🎯 Root cause investigation:"
echo "1. Check BTBerryWifi logs: $LOG_DIR/btwifiset_interaction_$TIMESTAMP.log"
echo "2. Check NetworkManager logs: $LOG_DIR/networkmanager_interaction_$TIMESTAMP.log"
echo "3. Check interface changes: $LOG_DIR/interface_changes_$TIMESTAMP.log"
echo "4. Full diagnostic log: $DIAG_FILE"
echo ""

echo "🕐 Diagnostic completed at: $(date)"
echo "📁 All diagnostic files saved in: $LOG_DIR"

# Create a summary file
SUMMARY_FILE="$LOG_DIR/diagnostic_summary_$TIMESTAMP.txt"
cat > "$SUMMARY_FILE" << 'EOF'
NETWORK FAILURE DIAGNOSTIC SUMMARY
===================================

SYMPTOMS:
- After reboot, using BTBerryWifi causes complete network failure
- Both Ethernet (eth0) and WiFi (wlan0) become unreachable
- Pi becomes completely inaccessible remotely

INVESTIGATION APPROACH:
1. Baseline network state before BTBerryWifi interaction
2. Monitor interface/service changes during BTBerryWifi usage
3. Analyze post-interaction state for failures
4. Identify root cause patterns

LIKELY ROOT CAUSES:
- Service conflicts between NetworkManager and wpa_supplicant
- Interface state corruption during Bluetooth WiFi handoff
- Routing table destruction during network reconfiguration
- Multiple wpa_supplicant processes causing interference

NEXT STEPS:
1. Review detailed logs in /var/log/network-diagnostics/
2. Apply targeted fixes based on identified failure patterns
3. Test fix persistence across reboots
4. Update install.sh with permanent solution

EOF

echo "📋 Diagnostic summary: $SUMMARY_FILE"