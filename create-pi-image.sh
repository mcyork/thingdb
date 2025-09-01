#!/bin/bash
# create-pi-image.sh
# Creates a complete disk image of the Raspberry Pi SD card

set -e

# Configuration
SD_CARD="/dev/disk2"
OUTPUT_DIR="$HOME/pi-images"
IMAGE_NAME="inventory-pi-$(date +%Y%m%d-%H%M%S).img"
COMPRESSED_NAME="inventory-pi-$(date +%Y%m%d-%H%M%S).img.gz"
FULL_PATH="$OUTPUT_DIR/$IMAGE_NAME"
COMPRESSED_PATH="$OUTPUT_DIR/$COMPRESSED_NAME"

# Check if user wants compression
COMPRESS=false
if [ "$1" = "--compress" ]; then
    COMPRESS=true
    FULL_PATH="$COMPRESSED_PATH"
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Safety check - make sure we're not about to overwrite the system disk
if [ "$SD_CARD" = "/dev/disk0" ] || [ "$SD_CARD" = "/dev/disk1" ]; then
    print_error "ERROR: SD_CARD is set to a system disk! This would be dangerous."
    print_error "Please check the SD_CARD variable and try again."
    exit 1
fi

print_status "Creating Raspberry Pi disk image..."
print_status "Source: $SD_CARD"
print_status "Output: $FULL_PATH"

# Check if SD card exists
if [ ! -b "$SD_CARD" ]; then
    print_error "SD card not found at $SD_CARD"
    print_status "Available disks:"
    diskutil list
    exit 1
fi

# Get SD card size
SD_SIZE=$(diskutil info "$SD_CARD" | grep "Disk Size" | awk '{print $3}')
print_status "SD card size: $SD_SIZE"

# Create output directory
print_status "Creating output directory..."
mkdir -p "$OUTPUT_DIR"

# Check available disk space
AVAILABLE_SPACE=$(df -h "$OUTPUT_DIR" | tail -1 | awk '{print $4}')
print_status "Available space: $AVAILABLE_SPACE"

# Unmount the SD card to ensure clean read
print_status "Unmounting SD card for clean read..."
diskutil unmountDisk "$SD_CARD" 2>/dev/null || true

# Create the disk image
print_status "Creating disk image (this will take several minutes)..."
print_warning "DO NOT remove the SD card during this process!"

# Use dd with larger block size and progress monitoring for better performance
print_status "Starting dd copy with optimized settings..."
print_status "Using 4MB block size for better performance with fast card readers"

if [ "$COMPRESS" = true ]; then
    print_status "Creating compressed image (will be much smaller)..."
    dd if="$SD_CARD" bs=4m status=progress | gzip > "$FULL_PATH"
else
    dd if="$SD_CARD" of="$FULL_PATH" bs=4m status=progress
fi

# Verify the image was created
if [ -f "$FULL_PATH" ]; then
    IMAGE_SIZE=$(ls -lh "$FULL_PATH" | awk '{print $5}')
    print_success "Disk image created successfully!"
    print_status "Image file: $FULL_PATH"
    print_status "Image size: $IMAGE_SIZE"
else
    print_error "Failed to create disk image"
    exit 1
fi

# Remount the SD card
print_status "Remounting SD card..."
diskutil mountDisk "$SD_CARD" 2>/dev/null || true

# Create a checksum for verification
print_status "Creating checksum for verification..."
cd "$OUTPUT_DIR"
sha256sum "$IMAGE_NAME" > "$IMAGE_NAME.sha256"
print_success "Checksum created: $IMAGE_NAME.sha256"

# Show final information
echo ""
print_success "🎉 Pi disk image creation complete!"
echo ""
echo "📁 Image Details:"
echo "   • File: $FULL_PATH"
echo "   • Size: $IMAGE_SIZE"
echo "   • Checksum: $FULL_PATH.sha256"
echo ""
echo "🔄 To restore this image to another SD card:"
echo "   1. Insert target SD card"
if [ "$COMPRESS" = true ]; then
    echo "   2. Run: gunzip -c $FULL_PATH | sudo dd of=/dev/diskX bs=4m status=progress"
    echo "      (Replace /dev/diskX with your target SD card)"
else
    echo "   2. Run: ./restore-pi-image.sh $FULL_PATH"
fi
echo ""
echo "⚠️  Important Notes:"
echo "   • This image contains the entire 64GB card"
echo "   • It can be restored to any 64GB+ SD card"
echo "   • The restored card will be bootable and identical"
echo "   • Keep this image safe as a backup!"
