#!/bin/bash
# restore-pi-image.sh
# Restores a Pi disk image to an SD card

set -e

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

# Check if image file was provided
if [ $# -eq 0 ]; then
    print_error "Usage: $0 <image-file> [target-disk]"
    print_status "Example: $0 ~/pi-images/inventory-pi-20241201-143022.img"
    print_status "Available disks:"
    diskutil list
    exit 1
fi

IMAGE_FILE="$1"
TARGET_DISK="$2"

# Check if image file exists
if [ ! -f "$IMAGE_FILE" ]; then
    print_error "Image file not found: $IMAGE_FILE"
    exit 1
fi

# If no target disk specified, show available disks
if [ -z "$TARGET_DISK" ]; then
    print_status "Available disks:"
    diskutil list
    echo ""
    read -p "Enter target disk (e.g., /dev/disk2): " TARGET_DISK
fi

# Safety check
if [ "$TARGET_DISK" = "/dev/disk0" ] || [ "$TARGET_DISK" = "/dev/disk1" ]; then
    print_error "ERROR: Target disk is a system disk! This would be dangerous."
    exit 1
fi

print_status "Restoring Pi disk image..."
print_status "Source: $IMAGE_FILE"
print_status "Target: $TARGET_DISK"

# Check if target disk exists
if [ ! -b "$TARGET_DISK" ]; then
    print_error "Target disk not found: $TARGET_DISK"
    exit 1
fi

# Get image size
IMAGE_SIZE=$(ls -lh "$IMAGE_FILE" | awk '{print $5}')
print_status "Image size: $IMAGE_SIZE"

# Get target disk size
TARGET_SIZE=$(diskutil info "$TARGET_DISK" | grep "Disk Size" | awk '{print $3}')
print_status "Target disk size: $TARGET_SIZE"

# Final confirmation
print_warning "⚠️  WARNING: This will completely erase $TARGET_DISK"
print_warning "All data on the target disk will be lost!"
echo ""
read -p "Are you sure you want to continue? (type 'yes' to confirm): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    print_status "Operation cancelled."
    exit 0
fi

# Unmount target disk
print_status "Unmounting target disk..."
diskutil unmountDisk "$TARGET_DISK" 2>/dev/null || true

# Restore the image
print_status "Restoring image to SD card (this will take several minutes)..."
print_warning "DO NOT remove the SD card during this process!"

dd if="$IMAGE_FILE" of="$TARGET_DISK" bs=1m status=progress

# Sync to ensure data is written
print_status "Syncing data to disk..."
sync

# Remount the disk
print_status "Remounting SD card..."
diskutil mountDisk "$TARGET_DISK" 2>/dev/null || true

print_success "🎉 Pi disk image restored successfully!"
print_status "The SD card is now ready to boot in your Raspberry Pi"
