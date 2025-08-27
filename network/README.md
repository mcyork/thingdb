# Network Installer

This directory contains standalone network installation tools for Raspberry Pi devices, specifically for setting up BTBerryWifi network management.

## Overview

The network installer provides a complete, automated setup for:
- **BTBerryWifi**: Bluetooth-based WiFi configuration tool
- **NetworkManager**: Modern network management service
- **Bluetooth LE**: Enhanced Bluetooth configuration
- **Network service optimization**: Proper service dependencies and conflict resolution

## Files

### `install-network.sh`
- **Purpose**: Core network installation script that runs directly on the Pi
- **Usage**: Execute this script ON the Raspberry Pi (not from the host)
- **Requirements**: Must be run as root (`sudo`)
- **Features**: 
  - Installs all required packages
  - Configures NetworkManager and Bluetooth
  - Sets up BTBerryWifi service
  - Resolves network service conflicts
  - Provides detailed status reporting

### `install-network-remote.sh`
- **Purpose**: Remote installer that uses the `pi` CLI tool
- **Usage**: Run from your development machine to install on a remote Pi
- **Requirements**: 
  - `pi` CLI tool installed and configured
  - Default Pi configuration set up
  - Target Pi must be online
- **Features**:
  - Transfers installer script to Pi
  - Executes installation remotely
  - Monitors installation progress
  - Handles reboot and post-reboot testing
  - Provides comprehensive status reporting

## Prerequisites

### For Remote Installation
1. **pi CLI tool** installed and configured
2. **Default Pi configuration** set up
3. **Target Pi online** and accessible via SSH
4. **SSH key authentication** configured

### For Direct Installation
1. **Root access** on the Pi
2. **Internet connectivity** for package downloads
3. **Working Ethernet connection** (for stability during installation)

## Quick Start

### Remote Installation (Recommended)
```bash
# From your development machine
cd network/
./install-network-remote.sh
```

### Direct Installation
```bash
# On the Raspberry Pi
cd network/
sudo ./install-network.sh
```

## What Gets Installed

### Packages
- `network-manager`: Primary network management service
- `wireless-tools`: WiFi management utilities
- `wpasupplicant`: WiFi authentication
- `rfkill`: Radio frequency control
- `python3-cryptography`: Encryption support
- `python3-gi`: GObject introspection
- `python3-dbus`: D-Bus communication

### Services
- **NetworkManager**: Modern network management
- **BTBerryWifi**: Bluetooth WiFi configuration
- **Bluetooth**: Enhanced Bluetooth with LE support
- **Network Interface Protection**: Ensures interfaces stay managed

### Configuration
- NetworkManager WiFi backend configuration
- Bluetooth service optimizations
- Service dependency management
- Network interface protection rules

## Post-Installation

### Required Actions
1. **Reboot the Pi** for all changes to take effect
2. **Test BTBerryWifi** with mobile app
3. **Verify network stability** after reboot

### Expected Results
- BTBerryWifi appears as Bluetooth device (hostname)
- Default password: `inventory`
- Ethernet reconnects automatically
- WiFi scanning and configuration via Bluetooth

## Troubleshooting

### Common Issues

#### Bluetooth Service Won't Start
- Check if `dtoverlay=disable-bt` is in `/boot/firmware/config.txt`
- Remove or comment out this line if present
- Reboot the Pi

#### Network Interfaces Not Managed
- Run: `sudo nmcli device connect eth0`
- Check NetworkManager service status
- Verify interface configuration

#### BTBerryWifi Not Working
- Ensure Bluetooth service is running
- Check service logs: `journalctl -u btwifiset.service -f`
- Verify NetworkManager is active

### Recovery Commands
```bash
# Check service status
sudo systemctl status btwifiset.service
sudo systemctl status bluetooth.service
sudo systemctl status NetworkManager

# View logs
sudo journalctl -u btwifiset.service -f
sudo journalctl -u bluetooth.service -f

# Manual network reconnection
sudo nmcli device connect eth0
sudo nmcli device connect wlan0

# Restart services
sudo systemctl restart NetworkManager
sudo systemctl restart bluetooth.service
sudo systemctl restart btwifiset.service
```

## Integration with Main Project

This network installer is designed to work alongside the main `inv2-dev` project:

- **Serial installer** (`serial/`) provides console fallback
- **Network installer** (`network/`) provides WiFi configuration
- **Main deployment** uses these as building blocks

## Security Notes

- BTBerryWifi uses default password `inventory`
- Bluetooth is configured with experimental features enabled
- Network interfaces are protected from being unmanaged
- All services run with appropriate systemd security contexts

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review service logs for error details
3. Verify all prerequisites are met
4. Test with a fresh Pi image if problems persist
