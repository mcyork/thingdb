# Network and Serial Deployment Guide

## Overview
This guide covers deploying the inventory system to a Raspberry Pi with optional network provisioning (BTBerryWifi + serial agent).

## Prerequisites
- Fresh Raspberry Pi with Raspbian/Raspberry Pi OS
- Pi connected via Ethernet (for initial deployment)
- `pi` CLI tool configured (`pi-shell`)
- Serial cable connected (optional but recommended)

## Deployment Options

### Basic Deployment (Application Only)
Deploy just the inventory application without network tools:
```bash
./deploy-prepare.sh
./scripts/deploy-remote.sh
```

### Full Deployment with Network Provisioning
Deploy application + BTBerryWifi + serial agent:
```bash
./deploy-prepare.sh --provision
./scripts/deploy-remote.sh --provision
```

## What Gets Deployed with `--provision`

### 1. BTBerryWifi
- Bluetooth LE WiFi configuration tool
- Allows WiFi setup via mobile app
- NetworkManager-based (no duplicate SSIDs)
- Auto-starts on boot

### 2. Serial Agent
- Emergency console access when network fails
- Works like SSH but over serial port
- No pagers, clean output for automation
- Installed on `/dev/ttyAMA0` by default

### 3. Network Fixes
- NetworkManager as primary network manager
- Proper service ordering (NetworkManager → BTBerryWifi)
- Ethernet persistence across reboots
- Disabled conflicting services (dhcpcd, systemd-networkd)

## Post-Deployment Steps

After deployment with `--provision`:

1. **Reboot the Pi**
   ```bash
   pi run --pi pi1 'sudo reboot'
   ```

2. **Wait 60 seconds for boot**

3. **Verify connectivity**
   ```bash
   pi status
   ```

4. **Test BTBerryWifi**
   - Open BTBerryWifi mobile app
   - Look for device named as Pi's hostname
   - Default password: "inventory"

5. **Test Serial Console** (if serial cable connected)
   ```bash
   cd /Users/ianmccutcheon/projects/pi-serial
   python3 scripts/serial_bridge run --port_name pi_console "hostname"
   ```

## Troubleshooting

### If Pi loses network after reboot
Use serial console to reconnect:
```bash
python3 scripts/serial_bridge run --port_name pi_console "nmcli device connect eth0"
```

### If BTBerryWifi doesn't appear
Check services via SSH or serial:
```bash
systemctl status bluetooth
systemctl status btwifiset.service
```

### Manual Network Deployment
If you need to deploy network tools to an existing Pi:
```bash
cd pi-setup
./deploy-network-complete.sh pi1
```

## Service Status Check
To verify all services are running:
```bash
pi run --pi pi1 "
systemctl is-active NetworkManager
systemctl is-active bluetooth  
systemctl is-active btwifiset.service
systemctl is-active serial-agent@ttyAMA0
"
```

## Components Location
- Main deployment scripts: `/deploy-prepare.sh`, `/scripts/deploy-remote.sh`
- Network deployment: `/pi-setup/deploy-network-complete.sh`
- Serial agent source: `/Users/ianmccutcheon/projects/pi-serial`
- BTBerryWifi config: Deployed to `/usr/local/btwifiset/`

## Security Notes
- BTBerryWifi has a 15-minute timeout
- Default Bluetooth password: "inventory" (change in production)
- Serial console requires physical access
- SSH keys should be configured for passwordless deployment