#!/bin/bash

echo "💾 SD Card Writer for Inventory Pi Image"
echo "========================================"

if [ $# -ne 1 ]; then
    echo "Usage: $0 /dev/diskX"
    echo ""
    echo "Find your SD card device:"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "  macOS: diskutil list"
    else
        echo "  Linux: lsblk or fdisk -l"
    fi
    exit 1
fi

DEVICE=$1
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILDER_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$BUILDER_DIR/output"

# Find the latest image
IMAGE=$(ls -t "$OUTPUT_DIR"/inventory-pi-*.img 2>/dev/null | head -1)

if [ -z "$IMAGE" ]; then
    echo "❌ No image found in $OUTPUT_DIR"
    echo "   Run ./build-image.sh first"
    exit 1
fi

echo "📦 Image: $(basename "$IMAGE")"
echo "💾 Target: $DEVICE"
echo ""
echo "⚠️  WARNING: This will ERASE everything on $DEVICE"
echo ""

# Show device info
if [[ "$OSTYPE" == "darwin"* ]]; then
    diskutil list "$DEVICE"
else
    fdisk -l "$DEVICE" 2>/dev/null || lsblk "$DEVICE"
fi

echo ""
read -p "Continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Cancelled"
    exit 0
fi

echo ""
echo "🔓 Unmounting device..."
if [[ "$OSTYPE" == "darwin"* ]]; then
    diskutil unmountDisk "$DEVICE"
else
    umount "$DEVICE"* 2>/dev/null
fi

echo "✍️ Writing image to SD card..."
echo "   This will take 10-20 minutes..."

if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS - use raw device for faster writing
    RAW_DEVICE=$(echo "$DEVICE" | sed 's/disk/rdisk/')
    sudo dd if="$IMAGE" of="$RAW_DEVICE" bs=4m status=progress
else
    # Linux
    sudo dd if="$IMAGE" of="$DEVICE" bs=4M status=progress conv=fsync
fi

echo ""
echo "🔏 Ejecting SD card..."
if [[ "$OSTYPE" == "darwin"* ]]; then
    diskutil eject "$DEVICE"
else
    sync
    eject "$DEVICE" 2>/dev/null || echo "  Remove SD card when ready"
fi

echo ""
echo "✅ SD card written successfully!"
echo ""
echo "📝 Next steps:"
echo "  1. Insert SD card into your Raspberry Pi"
echo "  2. Connect power (and ethernet if not using Wi-Fi)"
echo "  3. Wait ~5 minutes for first boot setup"
echo "  4. SSH in: ssh pi@inventory.local"
echo "  5. Access web UI: https://inventory.local"