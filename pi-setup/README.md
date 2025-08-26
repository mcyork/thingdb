# BTBerryWifi Deployment Guide

This directory contains the scripts needed to deploy BTBerryWifi on a Raspberry Pi for WiFi configuration over Bluetooth.

## 🎯 What This Does

BTBerryWifi allows users to configure WiFi on a headless Raspberry Pi using a mobile app over Bluetooth Low Energy (BLE). This is perfect for:
- **Headless Pi deployments** where WiFi needs to be configured
- **IoT devices** that need WiFi setup without physical access
- **Distributable images** that users can configure themselves

## 📱 How It Works

1. **Pi broadcasts Bluetooth** - Shows as "inventory" device
2. **User connects** with BTBerryWifi mobile app
3. **App scans WiFi** - Lists available networks
4. **User selects network** - Enters password
5. **Pi connects** - WiFi configured automatically

## 🚀 Deployment Process

### 1. Prepare Deployment Package

```bash
# Create deployment package with BTBerryWifi provisioning
./deploy-prepare.sh --provision
```

### 2. Deploy to Pi

```bash
# Deploy with BTBerryWifi provisioning
./scripts/deploy-remote.sh --provision
```

### 3. Verify Deployment

```bash
# SSH to Pi and run verification
sudo /tmp/pi-setup/verify-deployment.sh
```

## 🔧 What Gets Installed

### Core Services
- **BTBerryWifi** - Main BLE service for WiFi configuration
- **Bluetooth** - Modified service with `--experimental -P battery` flags
- **wpa_supplicant** - WiFi connection management

### Configuration
- **Bluetooth service** - Modified for proper BLE support
- **wpa_supplicant.conf** - Properly configured for interface management
- **Network coexistence** - Both Ethernet and WiFi work simultaneously

### Security Features
- **10-minute timer** - Bluetooth auto-disables after 10 minutes
- **Clean credentials** - No WiFi passwords stored in distributed image

## 📋 Scripts Overview

### `install.sh`
Main installation script that:
- Installs BTBerryWifi using official installer
- Configures Bluetooth service for BLE
- Sets up WiFi interface and wpa_supplicant
- Forces BTBerryWifi to use wpa_supplicant method
- Configures network coexistence

### `test-wifi-scan.sh`
Comprehensive WiFi testing script that:
- Checks WiFi interface status
- Tests RF-kill and interface activation
- Verifies wpa_supplicant management
- Tests WiFi scanning capability
- Validates BTBerryWifi configuration

### `verify-deployment.sh`
Deployment verification script that:
- Checks all service statuses
- Validates configuration files
- Tests WiFi functionality
- Provides deployment summary

## 🔍 Troubleshooting

### WiFi Scanning Issues
```bash
# Run comprehensive WiFi test
sudo /usr/local/bin/test-wifi-scan.sh

# Check wpa_supplicant status
sudo wpa_cli -i wlan0 status

# Test manual scanning
sudo iwlist wlan0 scan
```

### Bluetooth Issues
```bash
# Check Bluetooth service
sudo systemctl status bluetooth

# Verify BLE flags
sudo systemctl show bluetooth --property=ExecStart

# Restart Bluetooth
sudo systemctl restart bluetooth
```

### BTBerryWifi Issues
```bash
# Check service status
sudo systemctl status btwifiset.service

# View logs
sudo journalctl -u btwifiset.service -f

# Verify configuration
sudo grep "return False" /usr/local/btwifiset/btwifiset.py
```

## 📱 Mobile App

### BTBerryWifi App
- **iOS**: Available on Apple App Store
- **Android**: Available on Google Play Store
- **Search**: "BTBerryWifi" in your app store

### Usage
1. Install BTBerryWifi app
2. Power on Pi (Bluetooth broadcasts for 10 minutes)
3. Open app and look for "inventory" device
4. Connect and scan for WiFi networks
5. Select network and enter password
6. Pi connects automatically

## 🎯 Key Features

### ✅ What Works
- **WiFi scanning** - Discovers available networks
- **Network listing** - Shows networks in mobile app
- **Connection attempts** - Accepts passwords from app
- **Network coexistence** - Ethernet + WiFi simultaneously
- **Security timer** - Bluetooth auto-disables

### 🔧 Configuration
- **Forced wpa_supplicant** - Reliable WiFi management
- **Proper Bluetooth flags** - BLE support enabled
- **Interface management** - wlan0 properly configured
- **Service dependencies** - Correct startup order

## 🚨 Important Notes

### Before Distribution
- Run `wipe-credentials.sh` to clear all credentials
- This ensures clean image for end users
- No WiFi passwords or SSH keys in distributed image

### Security
- Bluetooth only active for 10 minutes after boot
- No persistent Bluetooth exposure
- Clean credential management

### Network Setup
- Both Ethernet and WiFi interfaces work
- No network conflicts
- Proper interface priority management

## 📞 Support

If you encounter issues:
1. Run `verify-deployment.sh` for diagnostics
2. Check service logs with `journalctl`
3. Test WiFi with `test-wifi-scan.sh`
4. Verify Bluetooth configuration

The deployment should work automatically on fresh Pi installations with these scripts.
