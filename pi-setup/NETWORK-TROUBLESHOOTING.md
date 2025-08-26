# BTBerryWifi Network Stability Troubleshooting

## Problem Description

After deployment and reboot, using BTBerryWifi (Bluetooth WiFi configuration) can cause complete network failure where both Ethernet and WiFi become unreachable, making the Pi completely inaccessible remotely.

## Root Cause Analysis

The network failure is caused by several interacting issues:

1. **Service Conflicts**: Multiple network managers (NetworkManager, dhcpcd, systemd-networkd) competing for interface control
2. **wpa_supplicant Interference**: Multiple wpa_supplicant processes causing WiFi state corruption
3. **BTBerryWifi Integration Issues**: The service doesn't properly handle NetworkManager coexistence
4. **Interface State Corruption**: Network interfaces lose proper state during Bluetooth/WiFi handoff
5. **Routing Table Destruction**: Network reconfiguration destroys routing entries

## Diagnostic Tools

### 1. Real-time Monitoring (while Pi is accessible)
```bash
# Run comprehensive diagnostic
sudo /usr/local/bin/diagnose-network-failure.sh
```

This script:
- Captures pre-BTBerryWifi baseline
- Monitors interface changes during BTBerryWifi usage
- Analyzes post-interaction failures
- Saves detailed logs to `/var/log/network-diagnostics/`

### 2. Boot-time Diagnostic (for unreachable Pi)
```bash
# Copy to boot partition for offline analysis
sudo cp /path/to/boot-diagnostic.sh /boot/
# or /boot/firmware/ depending on Pi model

# Make it run at boot
sudo cp /path/to/boot-diagnostic.sh /etc/init.d/
sudo update-rc.d boot-diagnostic.sh defaults
```

The boot diagnostic saves logs to the boot partition which can be accessed by removing the SD card.

### 3. Quick Status Check
```bash
# Verify current fixes are applied
sudo /usr/local/bin/verify-fixes.sh
```

## Solutions

### Option 1: Comprehensive Stability Fix (Recommended)
```bash
# Apply all stability fixes at once
sudo /usr/local/bin/fix-network-stability.sh
```

This script applies:
- Service isolation (disables conflicting network managers)
- NetworkManager exclusive control
- BTBerryWifi service hardening with safety wrapper
- Network interface monitoring and auto-recovery
- Robust boot-time network initialization

### Option 2: Manual Step-by-step Fix

#### Step 1: Service Isolation
```bash
# Disable conflicting services
sudo systemctl stop dhcpcd.service
sudo systemctl disable dhcpcd.service  
sudo systemctl mask dhcpcd.service

sudo systemctl stop systemd-networkd.service
sudo systemctl disable systemd-networkd.service
sudo systemctl mask systemd-networkd.service

sudo systemctl disable wpa_supplicant@wlan0.service
sudo systemctl mask wpa_supplicant@wlan0.service
```

#### Step 2: NetworkManager Hardening
```bash
# Create exclusive NetworkManager config
sudo tee /etc/NetworkManager/conf.d/01-exclusive-control.conf > /dev/null << 'EOF'
[main]
dns=systemd-resolved
no-auto-default=*
plugins=keyfile

[device]
ethernet.cloned-mac-address=preserve
wifi.cloned-mac-address=preserve
wifi.backend=wpa_supplicant
wifi.scan-rand-mac-address=no

[connectivity]
uri=http://connectivitycheck.gstatic.com/generate_204
interval=0
EOF

sudo systemctl restart NetworkManager
```

#### Step 3: BTBerryWifi Service Wrapper
```bash
# Replace original service with stable version
sudo systemctl stop btwifiset.service
sudo systemctl disable btwifiset.service

# Use the stable service created by fix-network-stability.sh
sudo systemctl enable btwifiset-stable.service
sudo systemctl start btwifiset-stable.service
```

### Option 3: Emergency Recovery (when Pi is unreachable)

1. **Physical Access Required**:
   - Remove SD card from Pi
   - Mount on another system
   - Edit files directly on SD card

2. **Mount SD card partitions**:
   ```bash
   # On Linux/macOS
   ls /Volumes/  # Look for bootfs and rootfs
   
   # Access boot partition
   cat /Volumes/bootfs/network-failure-log.txt  # Check diagnostic logs
   
   # If you can mount root partition:
   sudo mount /dev/disk2s2 /mnt/pi-root  # Adjust device as needed
   ```

3. **Apply fixes to mounted filesystem**:
   ```bash
   # Edit service files on mounted root
   sudo nano /mnt/pi-root/etc/systemd/system/btwifiset.service
   
   # Disable conflicting services
   sudo rm /mnt/pi-root/etc/systemd/system/multi-user.target.wants/dhcpcd.service
   ```

## Prevention Strategies

### 1. Updated install.sh (FIXED!)
The `install.sh` script now includes the critical network stability fix:
- **Automatically disables and masks systemd-networkd** to prevent conflicts
- **No longer requires manual fix after installation**
- **Ensures network stability survives reboots**

The fix is applied during the NetworkManager setup phase:
```bash
# CRITICAL FIX: Prevent systemd-networkd conflicts that cause reboot failures
systemctl disable systemd-networkd.service
systemctl mask systemd-networkd.service  
systemctl disable systemd-networkd.socket
systemctl disable systemd-network-generator.service
```

### 2. Pre-deployment Testing
```bash
# Test BTBerryWifi stability before creating image
sudo /usr/local/bin/diagnose-network-failure.sh

# Use BTBerryWifi to scan networks, then cancel
# Verify network connectivity remains stable
```

### 3. Image Creation with Fixes
```bash
# Apply stability fixes before creating image
sudo /usr/local/bin/fix-network-stability.sh

# Then create image
sudo /path/to/create-distributable-image.sh
```

## Service Architecture (After Fixes)

```
Boot Sequence:
1. network-init.service (cleans network state)
2. NetworkManager.service (exclusive network control)
3. network-monitor.service (monitors and recovers)
4. btwifiset-stable.service (hardened BTBerryWifi)

Disabled/Masked Services:
- dhcpcd.service (conflicts with NetworkManager)
- systemd-networkd.service (conflicts with NetworkManager)  
- wpa_supplicant@wlan0.service (interface-specific conflicts)
```

## Monitoring and Logs

### Service Status
```bash
# Check all network services
systemctl status NetworkManager btwifiset-stable network-monitor

# Check for conflicts
systemctl list-units --state=failed | grep network
```

### Log Files
```bash
# BTBerryWifi stable service
journalctl -u btwifiset-stable.service -f

# Network monitor
tail -f /var/log/network-monitor.log

# Network initialization  
tail -f /var/log/network-init.log

# Comprehensive diagnostics
ls /var/log/network-diagnostics/
```

## Testing Network Stability

### Basic Connectivity Test
```bash
# Before BTBerryWifi interaction
ping -c 5 8.8.8.8
ip route show
nmcli device status

# Use BTBerryWifi mobile app:
# 1. Scan for networks
# 2. Cancel operation (don't connect)

# After BTBerryWifi interaction  
ping -c 5 8.8.8.8  # Should still work
ssh user@pi-ip      # Should still be accessible
```

### Comprehensive Test
```bash
# Run full diagnostic during BTBerryWifi usage
sudo /usr/local/bin/diagnose-network-failure.sh

# Review logs for any failures
cat /var/log/network-diagnostics/diagnostic_summary_*.txt
```

## Recovery Commands (Emergency)

If the Pi becomes unreachable after BTBerryWifi usage:

### Via Serial Console (if available)
```bash
# Restart NetworkManager
sudo systemctl restart NetworkManager

# Bring up interfaces
sudo ip link set eth0 up
sudo ip link set wlan0 up

# Kill interfering processes
sudo pkill -f "wpa_supplicant.*-i.*wlan0"
sudo pkill dhcpcd

# Apply full fix
sudo /usr/local/bin/fix-network-stability.sh
```

### Via SD Card Edit (physical access required)
1. Remove SD card and mount on another system
2. Add a recovery script to run at next boot
3. Reinsert SD card and boot Pi

## Contact and Support

If network stability issues persist after applying these fixes:

1. Collect diagnostic logs from `/var/log/network-diagnostics/`
2. Include service status: `systemctl status NetworkManager btwifiset-stable`
3. Include interface status: `nmcli device status`
4. Include system logs: `journalctl --since="1 hour ago" | grep -E "(network|NetworkManager|wpa_supplicant)"`