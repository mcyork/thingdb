# Raspberry Pi SD Card Image Builder

This directory contains scripts to build a complete, ready-to-boot SD card image for the Home Inventory System.

## What This Creates

A custom Raspberry Pi OS image with:
- ✅ Home Inventory System pre-installed and configured
- ✅ Database with all your items pre-loaded
- ✅ Wi-Fi credentials pre-configured
- ✅ SSH enabled with your public key
- ✅ All system updates applied
- ✅ Auto-start on boot
- ✅ mDNS configured (inventory.local)

## Requirements

- macOS or Linux build machine
- 16GB+ free disk space
- Internet connection for downloading Pi OS
- `qemu` for ARM emulation (optional, for chroot method)

## Quick Start

1. Configure your settings in `config/settings.conf`
2. Run the build script:
   ```bash
   ./scripts/build-image.sh
   ```
3. Write the image to SD card:
   ```bash
   ./scripts/write-to-sd.sh /dev/disk2  # Use your SD card device
   ```
4. Boot your Pi and access at https://inventory.local

## Configuration Files

- `config/settings.conf` - Main configuration (Wi-Fi, hostname, etc.)
- `config/authorized_keys` - SSH public keys for passwordless access
- `config/wpa_supplicant.conf` - Wi-Fi configuration
- `overlay/` - Files to be copied to the image

## Build Methods

1. **Download & Modify** - Downloads official Pi OS and modifies it
2. **From Running Pi** - Creates image from your configured Pi
3. **Docker Build** - Uses Docker to build image (experimental)