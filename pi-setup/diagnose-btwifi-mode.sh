#!/bin/bash
# diagnose-btwifi-mode.sh - Check which mode BTBerryWifi is using

echo "🔍 BTBerryWifi Mode Diagnostic"
echo "=============================="

# Check BTBerryWifi's detection of NetworkManager
echo "1️⃣ Checking BTBerryWifi's NetworkManager detection:"
pi run-stream --pi pi1 "
sudo journalctl -u btwifiset.service --since='5 minutes ago' --no-pager | grep -E 'NetworkManager|nmcli|wpa_cli|version' | tail -20
"

echo ""
echo "2️⃣ NetworkManager Status:"
pi run --pi pi1 "
systemctl is-active NetworkManager
nmcli general status 2>/dev/null || echo 'nmcli not working'
"

echo ""
echo "3️⃣ Testing WiFi scan methods:"
echo "   NetworkManager scan (should work if NM is managing):"
pi run --pi pi1 "
timeout 5 nmcli -t device wifi list 2>/dev/null | wc -l || echo 'NM scan failed'
"

echo "   WPA Supplicant direct scan:"
pi run --pi pi1 "
sudo wpa_cli -i wlan0 status 2>/dev/null | head -5 || echo 'wpa_cli failed'
"

echo ""
echo "4️⃣ Interface management status:"
pi run --pi pi1 "
nmcli device status 2>/dev/null || echo 'nmcli device failed'
"

echo ""
echo "5️⃣ Service start order check:"
pi run --pi pi1 "
systemctl show -p After NetworkManager.service | grep -o 'After=.*'
systemctl show -p After btwifiset.service | grep -o 'After=.*'
systemctl show -p Before btwifiset.service | grep -o 'Before=.*'
"

echo ""
echo "6️⃣ BTBerryWifi Python check for NM:"
pi run --pi pi1 "
# Check what BTBerryWifi would detect
python3 -c \"
import subprocess
result = subprocess.run('systemctl is-active NetworkManager', shell=True, capture_output=True, text=True)
print(f'NetworkManager check result: {result.stdout.strip()}')
print(f'Would use NetworkManager: {result.stdout.strip() == \\\"active\\\"}')
\"
"