#!/bin/bash
# push-source.sh - Quick source code push for rapid development iteration
# This script pushes the src directory to the Pi and restarts the application

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
PI_NAME="pi1"  # Default Pi
PI_APP_DIR="/var/lib/inventory/app"
LOCAL_SRC_DIR="src"
SERVICE_NAME="inventory-app"

# Check if pi CLI tool is available
if ! command -v pi &> /dev/null; then
    print_error "pi CLI tool not found. Please install it first."
    exit 1
fi

# Check if Pi is online
print_status "Checking Pi status..."
if ! pi status "$PI_NAME" | grep -q "ONLINE"; then
    print_error "Pi '$PI_NAME' is not online"
    exit 1
fi

print_success "Pi '$PI_NAME' is online"

# Check if local src directory exists
if [ ! -d "$LOCAL_SRC_DIR" ]; then
    print_error "Local source directory not found: $LOCAL_SRC_DIR"
    exit 1
fi

print_status "Found local source directory: $LOCAL_SRC_DIR"

# Create temporary archive of source files
TEMP_ARCHIVE="/tmp/inventory-source-$(date +%s).tar.gz"
print_status "Creating source archive..."

# Exclude unnecessary files from the archive
tar -czf "$TEMP_ARCHIVE" \
    --exclude='__pycache__' \
    --exclude='*.pyc' \
    --exclude='.DS_Store' \
    --exclude='*.log' \
    --exclude='venv' \
    --exclude='uploads' \
    --exclude='logs' \
    -C "$LOCAL_SRC_DIR" .

print_success "Created source archive: $TEMP_ARCHIVE"

# Stop the application service
print_status "Stopping $SERVICE_NAME service..."
pi run-stream --pi "$PI_NAME" "sudo systemctl stop $SERVICE_NAME" || {
    print_warning "Service was not running or failed to stop"
}

# Push the archive to the Pi
print_status "Pushing source code to Pi..."
pi send --pi "$PI_NAME" "$TEMP_ARCHIVE" "/tmp/inventory-source.tar.gz"

# Extract and deploy on the Pi
print_status "Deploying source code on Pi..."
pi run-stream --pi "$PI_NAME" "
    cd $PI_APP_DIR
    sudo rm -rf backup-$(date +%Y%m%d_%H%M%S) 2>/dev/null || true
    sudo cp -r . backup-$(date +%Y%m%d_%H%M%S) 2>/dev/null || true
    sudo tar -xzf /tmp/inventory-source.tar.gz
    sudo chown -R inventory:inventory .
    sudo chmod -R 755 .
    rm /tmp/inventory-source.tar.gz
"

# Start the application service
print_status "Starting $SERVICE_NAME service..."
pi run-stream --pi "$PI_NAME" "sudo systemctl start $SERVICE_NAME"

# Wait a moment for the service to start
sleep 2

# Check service status
print_status "Checking service status..."
pi run-stream --pi "$PI_NAME" "sudo systemctl status $SERVICE_NAME --no-pager"

# Clean up local archive
rm -f "$TEMP_ARCHIVE"

print_success "Source code push complete!"
print_status "Application should now be running with your latest changes."
print_status "Check the service status above for any errors."
