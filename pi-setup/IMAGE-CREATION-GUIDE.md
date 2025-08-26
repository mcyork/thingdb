# 📀 Raspberry Pi Image Creation Guide

Complete workflow for creating distributable Raspberry Pi images with the Inventory System + BTBerryWifi

## 🎯 Overview

This process creates a compressed, distributable SD card image that users can flash to their own SD cards and boot on their Raspberry Pis with full WiFi setup capability via BTBerryWifi.

## 📋 Prerequisites

### Required Tools (Mac):
```bash
# Install required tools via Homebrew
brew install pv xz bc
```

### Hardware:
- Mac with SD card reader (built-in or USB)
- 64GB SD card with deployed system
- Working Pi deployment with BTBerryWifi

## 🚀 Complete Workflow

### Step 1: Deploy and Test System

```bash
# Create deployment package with BTBerryWifi
./deploy-prepare.sh --provision

# Deploy to Pi
./scripts/deploy-remote.sh --provision

# Test that everything works:
# - Inventory web interface accessible
# - BTBerryWifi app can connect and configure WiFi
# - Both Ethernet and WiFi work
```

### Step 2: Prepare Pi for Imaging

```bash
# This cleans credentials and prepares for first boot
./scripts/prepare-for-imaging.sh
```

**What this does:**
- ✅ Removes SSH keys, WiFi passwords, user data
- ✅ Clears logs and temporary files
- ✅ Resets machine-specific identifiers
- ✅ Ensures BTBerryWifi ready for first boot
- ✅ Shuts down Pi cleanly

**⚠️ Wait for Pi to fully shutdown before removing SD card!**

### Step 3: Create Distributable Image

```bash
# Remove SD card from Pi and insert into Mac
./scripts/create-distributable-image.sh
```

**What this does:**
- 📀 Detects SD card automatically
- 🖼️ Creates raw disk image with progress monitoring
- 🗜️ Compresses with XZ for maximum space savings
- ✅ Verifies integrity and creates checksums
- 📁 Creates distribution package with info

## 📊 Expected Results

### Typical Compression:
- **Raw 64GB image**: ~64GB
- **Compressed image**: ~8-15GB (depending on data)
- **Compression ratio**: 4:1 to 8:1

### Output Files:
```
~/inventory-pi-images/
├── inventory-pi-YYYYMMDD-HHMMSS.img.xz    # Main image file
├── inventory-pi-YYYYMMDD-HHMMSS.sha256    # Checksum
└── inventory-pi-YYYYMMDD-HHMMSS-info.txt  # Distribution info
```

## 📱 User Distribution Workflow

### For End Users:

1. **Download Files**:
   - `inventory-pi-YYYYMMDD-HHMMSS.img.xz` (compressed image)
   - `inventory-pi-YYYYMMDD-HHMMSS.sha256` (checksum)

2. **Flash to SD Card**:
   ```bash
   # Option 1: Use Raspberry Pi Imager (Recommended)
   # - Install Raspberry Pi Imager
   # - Select "Use custom image"  
   # - Choose the .img.xz file (Imager handles decompression automatically)
   # - Flash to 32GB+ SD card
   
   # Option 2: Command line (Advanced users)
   # Decompress first:
   xz -d inventory-pi-YYYYMMDD-HHMMSS.img.xz
   # Flash with dd:
   sudo dd if=inventory-pi-YYYYMMDD-HHMMSS.img of=/dev/diskN bs=4M status=progress
   ```

3. **First Boot Setup**:
   - Insert SD card into Pi and power on
   - Wait 2-3 minutes for first boot initialization
   - Pi will generate new SSH keys and setup services

4. **Configure WiFi via BTBerryWifi**:
   - Install BTBerryWifi app on phone (iOS/Android)
   - Look for "inventory" Bluetooth device
   - Connect and scan for WiFi networks
   - Select network and enter password
   - Pi connects automatically

5. **Access System**:
   - Web interface: `https://[pi-ip-address]`
   - SSH: Pi will have new unique SSH keys

## 🔧 Troubleshooting

### Image Creation Issues:

**"Disk not found"**:
```bash
diskutil list  # Check available disks
```

**"Permission denied"**:
```bash
sudo ./scripts/create-distributable-image.sh
```

**"Compression taking too long"**:
- Normal for 64GB images (15-45 minutes)
- Progress is shown via `pv`

### Distribution Issues:

**"Image too large"**:
- Use 32GB+ SD cards
- Consider shrinking unused partitions

**"Checksum mismatch"**:
```bash
shasum -a 256 -c inventory-pi-YYYYMMDD-HHMMSS.sha256
```

## 🎛️ Advanced Options

### Custom Image Names:
```bash
# Edit create-distributable-image.sh
IMAGE_NAME="my-custom-inventory-$(date +%Y%m%d)"
```

### Different Compression:
```bash
# For faster compression (larger file):
xz -6 --threads=0 < raw_image.img > compressed.img.xz

# For maximum compression (slower):
xz -9 -e --threads=0 < raw_image.img > compressed.img.xz
```

### Shrinking Images:
```bash
# Advanced: Use pishrink to minimize image size
wget https://raw.githubusercontent.com/Drewsif/PiShrink/master/pishrink.sh
chmod +x pishrink.sh
sudo ./pishrink.sh inventory-pi.img
```

## 📏 Image Size Optimization

### Pre-Imaging Optimization:
```bash
# On Pi before imaging:
sudo apt-get clean
sudo apt-get autoremove
sudo rm -rf /var/cache/apt/archives/*
sudo find /var/log -type f -name "*.log" -delete
```

### Post-Creation Optimization:
- Use `pishrink` to trim unused filesystem space
- Consider separate data partition for user content
- Remove development packages if not needed

## ✅ Quality Assurance

### Test Checklist:
- [ ] Image flashes successfully to test SD card
- [ ] Pi boots and generates new SSH keys
- [ ] Services start automatically (nginx, inventory-app, btwifiset)
- [ ] BTBerryWifi app can discover "inventory" device
- [ ] WiFi configuration works through app
- [ ] Web interface accessible at https://[pi-ip]
- [ ] Database initialized and working
- [ ] Both Ethernet and WiFi interfaces functional

## 🎉 Success Criteria

Your distributable image is ready when:
- ✅ **Size**: Compressed to <20GB for easy distribution
- ✅ **Integrity**: Passes checksum verification
- ✅ **Boot**: Boots successfully on fresh Pi hardware
- ✅ **WiFi Setup**: BTBerryWifi works on first boot
- ✅ **Functionality**: All inventory system features work
- ✅ **Security**: No sensitive data in distributed image

## 📞 Support

**For Image Creation**:
- Check script output for specific errors
- Ensure SD card is properly connected
- Verify sufficient disk space on Mac

**For Distribution**:
- Provide users with clear flashing instructions
- Include BTBerryWifi app download links
- Document expected first boot behavior

**Files to Include in Distribution**:
- `*.img.xz` (compressed image)
- `*.sha256` (checksum file)
- `*-info.txt` (user instructions)
- BTBerryWifi app store links