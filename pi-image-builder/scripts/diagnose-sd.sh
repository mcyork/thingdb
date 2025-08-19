#!/bin/bash

echo "🔍 Raspberry Pi SD Card Diagnostic Tool"
echo "======================================="

if [ $# -ne 1 ]; then
    echo "Usage: $0 /dev/diskX"
    echo ""
    echo "Find your SD card device:"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "  macOS: diskutil list"
    else
        echo "  Linux: lsblk"
    fi
    exit 1
fi

DEVICE=$1
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$SCRIPT_DIR/../work/diagnose"

echo "📦 Device: $DEVICE"
echo ""

# Create work directory
mkdir -p "$WORK_DIR"

echo "🔍 Checking SD card partitions..."
if [[ "$OSTYPE" == "darwin"* ]]; then
    diskutil list "$DEVICE"
else
    fdisk -l "$DEVICE"
fi

echo ""
echo "🔧 Mounting SD card for inspection..."

if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    mkdir -p "$WORK_DIR/boot"
    
    # Try to mount boot partition
    if mount -t msdos "${DEVICE}s1" "$WORK_DIR/boot" 2>/dev/null; then
        echo "✅ Boot partition mounted at $WORK_DIR/boot"
        BOOT_MOUNTED=true
    else
        echo "❌ Failed to mount boot partition"
        BOOT_MOUNTED=false
    fi
else
    # Linux
    mkdir -p "$WORK_DIR/boot" "$WORK_DIR/root"
    
    if mount "${DEVICE}p1" "$WORK_DIR/boot" 2>/dev/null; then
        echo "✅ Boot partition mounted"
        BOOT_MOUNTED=true
    else
        echo "❌ Failed to mount boot partition"
        BOOT_MOUNTED=false
    fi
    
    if mount "${DEVICE}p2" "$WORK_DIR/root" 2>/dev/null; then
        echo "✅ Root partition mounted"
        ROOT_MOUNTED=true
    else
        echo "❌ Failed to mount root partition"
        ROOT_MOUNTED=false
    fi
fi

if [ "$BOOT_MOUNTED" = "true" ]; then
    echo ""
    echo "📋 Boot partition analysis:"
    echo "=========================="
    
    BOOT_DIR="$WORK_DIR/boot"
    
    # Check critical boot files
    echo "Essential files:"
    for file in bootcode.bin start.elf kernel8.img cmdline.txt config.txt; do
        if [ -f "$BOOT_DIR/$file" ]; then
            echo "  ✅ $file ($(stat -f%z "$BOOT_DIR/$file" 2>/dev/null || stat -c%s "$BOOT_DIR/$file" 2>/dev/null) bytes)"
        else
            echo "  ❌ $file - MISSING!"
        fi
    done
    
    echo ""
    echo "Custom files:"
    for file in ssh firstrun.sh wpa_supplicant.conf authorized_keys inventory-install.sh; do
        if [ -f "$BOOT_DIR/$file" ]; then
            echo "  ✅ $file"
        else
            echo "  ❌ $file - missing"
        fi
    done
    
    # Check cmdline.txt content
    echo ""
    echo "📄 cmdline.txt content:"
    if [ -f "$BOOT_DIR/cmdline.txt" ]; then
        cat "$BOOT_DIR/cmdline.txt"
        echo ""
        
        # Check if our firstrun modifications are there
        if grep -q "firstrun.sh" "$BOOT_DIR/cmdline.txt"; then
            echo "  ✅ First-run script configured"
        else
            echo "  ⚠️ First-run script not found in cmdline.txt"
        fi
    else
        echo "  ❌ cmdline.txt missing!"
    fi
    
    # Check config.txt for any issues
    echo ""
    echo "📄 config.txt (last 10 lines):"
    if [ -f "$BOOT_DIR/config.txt" ]; then
        tail -10 "$BOOT_DIR/config.txt"
        echo ""
    fi
    
    # Check for our custom scripts
    echo ""
    echo "📋 Custom scripts:"
    if [ -f "$BOOT_DIR/firstrun.sh" ]; then
        echo "  📄 firstrun.sh ($(wc -l < "$BOOT_DIR/firstrun.sh") lines)"
        echo "     First few lines:"
        head -5 "$BOOT_DIR/firstrun.sh" | sed 's/^/       /'
    fi
    
    if [ -f "$BOOT_DIR/inventory-install.sh" ]; then
        echo "  📄 inventory-install.sh present"
    fi
    
    if [ -d "$BOOT_DIR/pi-deployment" ]; then
        echo "  📁 pi-deployment directory present"
        echo "     Contents: $(ls "$BOOT_DIR/pi-deployment" | wc -l) items"
    fi
    
    # Check Wi-Fi configuration
    echo ""
    echo "📶 Wi-Fi configuration:"
    if [ -f "$BOOT_DIR/wpa_supplicant.conf" ]; then
        echo "  ✅ wpa_supplicant.conf present"
        if grep -q "salty" "$BOOT_DIR/wpa_supplicant.conf"; then
            echo "  ✅ SSID 'salty' configured"
        fi
        if grep -q "psk=" "$BOOT_DIR/wpa_supplicant.conf"; then
            echo "  ✅ Password configured"
        fi
    else
        echo "  ❌ wpa_supplicant.conf missing"
    fi
fi

# Check for log files that might indicate what went wrong
if [ -d "$WORK_DIR/root" ] && [ "$ROOT_MOUNTED" = "true" ]; then
    echo ""
    echo "📋 System logs analysis:"
    echo "======================="
    
    ROOT_DIR="$WORK_DIR/root"
    
    # Check if system ever booted
    if [ -f "$ROOT_DIR/var/log/boot.log" ]; then
        echo "  📄 Boot log exists"
        echo "     Last few lines:"
        tail -5 "$ROOT_DIR/var/log/boot.log" | sed 's/^/       /'
    fi
    
    # Check journal logs
    if [ -d "$ROOT_DIR/var/log/journal" ]; then
        echo "  📁 Journal logs present"
    fi
    
    # Check if firstrun completed
    if [ ! -f "$ROOT_DIR/boot/firstrun.sh" ]; then
        echo "  ✅ First-run script completed (removed from boot)"
    else
        echo "  ⚠️ First-run script still in boot (may not have run)"
    fi
fi

echo ""
echo "🔧 Common Issues & Solutions:"
echo "============================"
echo "Red LED usually means:"
echo "  • Boot files corrupted or missing"
echo "  • SD card filesystem errors"
echo "  • Power supply insufficient"
echo "  • First-run script failed"
echo ""
echo "Try:"
echo "  1. Check power supply (5V 3A recommended)"
echo "  2. Use different SD card (Class 10, A1 or better)"
echo "  3. Rebuild image with simpler first-run setup"
echo "  4. Use ethernet instead of Wi-Fi for first boot"

# Cleanup
echo ""
echo "🧹 Unmounting..."
if [ "$BOOT_MOUNTED" = "true" ]; then
    umount "$WORK_DIR/boot" 2>/dev/null || diskutil unmount "$WORK_DIR/boot" 2>/dev/null
fi
if [ "$ROOT_MOUNTED" = "true" ]; then
    umount "$WORK_DIR/root" 2>/dev/null
fi

echo "✅ Diagnostic complete"