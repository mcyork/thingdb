#!/bin/bash
# fix-network-order.sh - Fix service ordering and dependencies for stable networking

echo "🔧 Fixing Network Service Order & Dependencies"
echo "=============================================="

pi run --pi pi1 "
sudo bash << 'FIX_EOF'
set -e

echo '1️⃣ Creating NetworkManager override to ensure proper startup...'
mkdir -p /etc/systemd/system/NetworkManager.service.d
cat > /etc/systemd/system/NetworkManager.service.d/override.conf << 'EOF'
[Unit]
After=network-pre.target dbus.service
Before=network.target network-online.target
Wants=network.target

[Service]
ExecStartPre=/bin/bash -c 'sleep 2; rfkill unblock wifi 2>/dev/null || true'
Restart=on-failure
RestartSec=5
EOF

echo '2️⃣ Ensuring BTBerryWifi starts AFTER NetworkManager is ready...'
mkdir -p /etc/systemd/system/btwifiset.service.d
cat > /etc/systemd/system/btwifiset.service.d/override.conf << 'EOF'
[Unit]
After=NetworkManager.service network-online.target bluetooth.service
Wants=NetworkManager.service
Requires=bluetooth.service

[Service]
ExecStartPre=/bin/bash -c 'until systemctl is-active NetworkManager; do sleep 2; done'
ExecStartPre=/bin/bash -c 'sleep 5'
Restart=on-failure
RestartSec=10
Environment="PYTHONUNBUFFERED=1"
EOF

echo '3️⃣ Creating network interface protection service...'
cat > /etc/systemd/system/network-interface-protection.service << 'EOF'
[Unit]
Description=Protect Network Interfaces from being unmanaged
After=NetworkManager.service
Wants=NetworkManager.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=/bin/bash -c 'sleep 10'
ExecStart=/bin/bash -c 'nmcli device set eth0 managed yes 2>/dev/null || true; nmcli device set wlan0 managed yes 2>/dev/null || true'
ExecStart=/bin/bash -c 'ip link set eth0 up 2>/dev/null || true'

[Install]
WantedBy=multi-user.target
EOF

echo '4️⃣ Ensuring WPA Supplicant is properly configured...'
mkdir -p /etc/systemd/system/wpa_supplicant.service.d
cat > /etc/systemd/system/wpa_supplicant.service.d/override.conf << 'EOF'
[Unit]
After=dbus.service
Before=NetworkManager.service

[Service]
ExecStartPre=/bin/bash -c 'rfkill unblock wifi 2>/dev/null || true'
EOF

echo '5️⃣ Creating startup diagnostics service...'
cat > /etc/systemd/system/network-startup-diagnostic.service << 'EOF'
[Unit]
Description=Network Startup Diagnostic Logger
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'echo \"=== Network Diagnostic at Boot ===\" > /var/log/network-boot.log; \
  echo \"Time: \$(date)\" >> /var/log/network-boot.log; \
  echo \"NetworkManager: \$(systemctl is-active NetworkManager)\" >> /var/log/network-boot.log; \
  echo \"BTBerryWifi: \$(systemctl is-active btwifiset.service)\" >> /var/log/network-boot.log; \
  echo \"Interfaces:\" >> /var/log/network-boot.log; \
  ip addr show >> /var/log/network-boot.log 2>&1; \
  echo \"NM Devices:\" >> /var/log/network-boot.log; \
  nmcli device status >> /var/log/network-boot.log 2>&1; \
  echo \"=== End Diagnostic ===\" >> /var/log/network-boot.log'

[Install]
WantedBy=multi-user.target
EOF

echo '6️⃣ Applying fixes...'
systemctl daemon-reload
systemctl enable network-interface-protection.service
systemctl enable network-startup-diagnostic.service

echo '7️⃣ Verifying service dependencies...'
echo 'NetworkManager dependencies:'
systemctl show -p After,Before,Wants,Requires NetworkManager.service | head -4

echo ''
echo 'BTBerryWifi dependencies:'
systemctl show -p After,Before,Wants,Requires btwifiset.service | head -4

echo ''
echo '✅ Service ordering fixes applied!'
echo ''
echo '⚠️  IMPORTANT: A reboot is required to test these fixes'
echo '   After reboot, check /var/log/network-boot.log for diagnostics'
FIX_EOF
"

echo ""
echo "🔍 Current service status:"
pi run --pi pi1 "
echo 'NetworkManager:' \$(systemctl is-active NetworkManager)
echo 'BTBerryWifi:' \$(systemctl is-active btwifiset.service)
echo 'Ethernet:' \$(ip addr show eth0 2>/dev/null | grep 'inet ' | awk '{print \$2}')
"

echo ""
echo "✅ Fix script completed!"
echo "📝 Next steps:"
echo "   1. Run: pi run --pi epi1 'sudo reboot'"
echo "   2. Wait 60 seconds"
echo "   3. Test connection and run: ./diagnose-btwifi-mode.sh"
echo "   4. Check: pi run --pi epi1 'cat /var/log/network-boot.log'"