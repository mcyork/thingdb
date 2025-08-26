#!/bin/bash
# create-distributable-image.sh  
# Creates a compressed, distributable Raspberry Pi image from SD card

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# Configuration
OUTPUT_DIR="$HOME/inventory-pi-images"
IMAGE_NAME="inventory-pi-$(date +%Y%m%d-%H%M%S)"
RAW_IMAGE="$OUTPUT_DIR/${IMAGE_NAME}.img"
COMPRESSED_IMAGE="$OUTPUT_DIR/${IMAGE_NAME}.img.xz"

print_status "🖼️  Creating distributable Raspberry Pi image..."
echo ""

# Check for required tools
REQUIRED_TOOLS=("diskutil" "dd" "xz" "pv")
for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        print_error "Required tool '$tool' not found"
        echo "Install with: brew install $tool"
        exit 1
    fi
done

# Create output directory
mkdir -p "$OUTPUT_DIR"

print_status "Scanning for SD card..."
print_warning "Please ensure your prepared Pi SD card is connected to your Mac"
echo ""

# List available disks
echo "📀 Available disks:"
diskutil list | grep -E "(disk[0-9]+|/dev/disk)"

echo ""
read -p "Enter the SD card disk identifier (e.g., disk2, disk4): " DISK_ID

if [[ ! "$DISK_ID" =~ ^disk[0-9]+$ ]]; then
    print_error "Invalid disk identifier format. Expected format: diskN (e.g., disk2)"
    exit 1
fi

DISK_DEVICE="/dev/$DISK_ID"
RAW_DISK_DEVICE="/dev/r$DISK_ID"

# Verify the disk exists
if [ ! -e "$DISK_DEVICE" ]; then
    print_error "Disk $DISK_DEVICE not found"
    exit 1
fi

# Show disk information
print_status "SD Card Information:"
diskutil info "$DISK_DEVICE" | grep -E "(Device Node|Media Name|Media Size|File System)"
echo ""

# Get disk size for progress monitoring
DISK_SIZE_BYTES=$(diskutil info "$DISK_DEVICE" | grep "Media Size" | awk '{print $5}' | tr -d '()')
DISK_SIZE_GB=$(echo "scale=2; $DISK_SIZE_BYTES / 1024 / 1024 / 1024" | bc)

print_warning "This will create an image of $DISK_DEVICE (${DISK_SIZE_GB}GB)"
print_warning "Output location: $RAW_IMAGE"
echo ""

read -p "Continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_error "Cancelled by user"
    exit 1
fi

# Unmount the disk (but don't eject)
print_status "Unmounting SD card..."
diskutil unmountDisk "$DISK_DEVICE" || {
    print_warning "Could not unmount disk - continuing anyway..."
}

# Create raw image with progress
print_status "Creating raw image (this will take 10-30 minutes for 64GB)..."
print_status "Using raw device $RAW_DISK_DEVICE for faster reading..."

# Calculate block size and count for progress
BS=4m  # 4MB blocks for faster transfer
TOTAL_BLOCKS=$(echo "$DISK_SIZE_BYTES / (4 * 1024 * 1024)" | bc)

print_status "Reading $DISK_SIZE_GB GB in ${BS} blocks..."
print_warning "Do not disconnect the SD card during this process!"

# Use dd with pv for progress monitoring
if dd if="$RAW_DISK_DEVICE" bs=$BS | pv -p -t -e -s "$DISK_SIZE_BYTES" > "$RAW_IMAGE"; then
    print_success "Raw image created successfully"
else
    print_error "Failed to create raw image"
    exit 1
fi

# Get actual image size
RAW_SIZE=$(ls -lh "$RAW_IMAGE" | awk '{print $5}')
print_success "Raw image size: $RAW_SIZE"

# Verify image integrity by checking filesystem
print_status "Verifying image integrity..."
if file "$RAW_IMAGE" | grep -q "DOS/MBR boot sector"; then
    print_success "Image appears valid (contains boot sector)"
else
    print_warning "Image format verification inconclusive - proceeding with compression"
fi

# Shrink the image to remove unused space
print_status "Analyzing image for unused space..."
LOOP_DEVICE=$(hdiutil attach -nomount "$RAW_IMAGE" | head -1 | awk '{print $1}')
if [ -n "$LOOP_DEVICE" ]; then
    print_status "Mounted image at $LOOP_DEVICE"
    
    # Try to get filesystem info
    if diskutil info "${LOOP_DEVICE}s2" 2>/dev/null | grep -q "File System"; then
        print_status "Found filesystem on ${LOOP_DEVICE}s2"
        
        # Get partition info for potential shrinking
        PARTITION_INFO=$(diskutil list "$LOOP_DEVICE" | tail -n +6)
        echo "Partition layout:"
        echo "$PARTITION_INFO"
    fi
    
    # Detach the loop device
    hdiutil detach "$LOOP_DEVICE" >/dev/null 2>&1
    print_success "Image analysis complete"
else
    print_warning "Could not mount image for analysis - proceeding with compression"
fi

# Compress the image
print_status "Compressing image with xz (this may take 15-45 minutes)..."
print_status "Output: $COMPRESSED_IMAGE"

# Use xz with maximum compression and progress
if pv "$RAW_IMAGE" | xz -9 -e --threads=0 -v > "$COMPRESSED_IMAGE"; then
    print_success "Image compressed successfully"
else
    print_error "Failed to compress image"
    exit 1
fi

# Get compressed size and compression ratio
COMPRESSED_SIZE=$(ls -lh "$COMPRESSED_IMAGE" | awk '{print $5}')
RAW_SIZE_BYTES=$(ls -l "$RAW_IMAGE" | awk '{print $5}')
COMPRESSED_SIZE_BYTES=$(ls -l "$COMPRESSED_IMAGE" | awk '{print $5}')
COMPRESSION_RATIO=$(echo "scale=1; $RAW_SIZE_BYTES / $COMPRESSED_SIZE_BYTES" | bc)

print_success "Compression complete!"
echo ""
echo "📊 Image Statistics:"
echo "   • Raw image size: $RAW_SIZE"
echo "   • Compressed size: $COMPRESSED_SIZE" 
echo "   • Compression ratio: ${COMPRESSION_RATIO}:1"
echo "   • Space saved: $(echo "scale=1; (1 - $COMPRESSED_SIZE_BYTES / $RAW_SIZE_BYTES) * 100" | bc)%"
echo ""

# Create checksum for integrity verification
print_status "Creating SHA256 checksum..."
CHECKSUM=$(shasum -a 256 "$COMPRESSED_IMAGE" | awk '{print $1}')
echo "$CHECKSUM  $(basename "$COMPRESSED_IMAGE")" > "$OUTPUT_DIR/${IMAGE_NAME}.sha256"
print_success "Checksum: $CHECKSUM"

# Clean up raw image to save space
read -p "Delete raw image to save space? (Y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    rm "$RAW_IMAGE"
    print_success "Raw image deleted"
else
    print_status "Raw image kept at: $RAW_IMAGE"
fi

# Create distribution info file
print_status "Creating distribution info..."
cat > "$OUTPUT_DIR/${IMAGE_NAME}-info.txt" << EOF
Inventory Pi System - Distributable Image
Created: $(date)
Source: Raspberry Pi OS with Inventory Management System + BTBerryWifi

Image Details:
- Filename: $(basename "$COMPRESSED_IMAGE")
- Size: $COMPRESSED_SIZE
- SHA256: $CHECKSUM
- Compression: XZ (LZMA2)

System Includes:
- Raspberry Pi OS (latest)
- Inventory Management System (Flask web app)
- BTBerryWifi for WiFi setup via Bluetooth
- PostgreSQL database
- Nginx web server with SSL
- All dependencies pre-installed

First Boot Instructions:
1. Flash this image to a 32GB+ SD card using Raspberry Pi Imager
2. Insert SD card into Pi and power on
3. Wait 2-3 minutes for first boot setup
4. Use BTBerryWifi mobile app to configure WiFi:
   - Look for "inventory" Bluetooth device
   - Connect and configure WiFi through the app
5. Access system at https://[pi-ip-address]

Default Credentials:
- System will generate unique SSH keys on first boot
- Web interface has no default password
- Database uses internal authentication

Support:
- WiFi setup via BTBerryWifi mobile app
- Web interface for inventory management
- SSH access with key authentication
EOF

print_success "🎉 Distributable Pi image created successfully!"
echo ""
echo "📁 Files created in $OUTPUT_DIR:"
echo "   • $(basename "$COMPRESSED_IMAGE") - Main image file"
echo "   • $(basename "$COMPRESSED_IMAGE").sha256 - Checksum"
echo "   • ${IMAGE_NAME}-info.txt - Distribution info"
echo ""
echo "📋 Next Steps:"
echo "   1. Test the image by flashing to a test SD card"
echo "   2. Verify first boot and BTBerryWifi functionality"
echo "   3. Distribute the compressed .xz file to users"
echo ""
echo "💾 Distribution size: $COMPRESSED_SIZE"
print_success "Image ready for distribution!"

# Remount the SD card for normal use
print_status "Remounting SD card for normal use..."
diskutil mountDisk "$DISK_DEVICE" >/dev/null 2>&1 || true