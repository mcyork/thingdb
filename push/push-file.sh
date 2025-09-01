#!/bin/bash
# push-file.sh - Push individual files to Pi for rapid iteration
# Usage: ./push-file.sh <file_path>

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
SERVICE_NAME="inventory-app"

# Check if file argument is provided
if [ $# -eq 0 ]; then
    print_error "Usage: $0 <file_path>"
    print_error "Example: $0 src/main.py"
    exit 1
fi

FILE_PATH="$1"

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

# Check if local file exists
if [ ! -f "$FILE_PATH" ]; then
    print_error "Local file not found: $FILE_PATH"
    exit 1
fi

print_status "Found local file: $FILE_PATH"

# Determine the relative path from src directory
if [[ "$FILE_PATH" == src/* ]]; then
    RELATIVE_PATH="${FILE_PATH#src/}"
else
    print_error "File must be in the src directory: $FILE_PATH"
    exit 1
fi

print_status "Will deploy to: $PI_APP_DIR/$RELATIVE_PATH"

# Stop the application service
print_status "Stopping $SERVICE_NAME service..."
pi run-stream --pi "$PI_NAME" "sudo systemctl stop $SERVICE_NAME" || {
    print_warning "Service was not running or failed to stop"
}

# Push the file to the Pi
print_status "Pushing file to Pi..."
pi send --pi "$PI_NAME" "$FILE_PATH" "/tmp/$(basename "$FILE_PATH")"

# Deploy the file on the Pi
print_status "Deploying file on Pi..."
pi run-stream --pi "$PI_NAME" "sudo mkdir -p $PI_APP_DIR/$(dirname $RELATIVE_PATH)"
pi run-stream --pi "$PI_NAME" "sudo cp /tmp/$(basename $FILE_PATH) $PI_APP_DIR/$RELATIVE_PATH"
pi run-stream --pi "$PI_NAME" "sudo chown inventory:inventory $PI_APP_DIR/$RELATIVE_PATH"
pi run-stream --pi "$PI_NAME" "sudo chmod 644 $PI_APP_DIR/$RELATIVE_PATH"
pi run-stream --pi "$PI_NAME" "rm /tmp/$(basename $FILE_PATH)"

# Start the application service
print_status "Starting $SERVICE_NAME service..."
pi run-stream --pi "$PI_NAME" "sudo systemctl start $SERVICE_NAME"

# Wait a moment for the service to start
sleep 2

# Check service status
print_status "Checking service status..."
pi run-stream --pi "$PI_NAME" "sudo systemctl status $SERVICE_NAME --no-pager"

print_success "File push complete!"
print_status "File $FILE_PATH has been deployed to $PI_APP_DIR/$RELATIVE_PATH"
print_status "Application should now be running with your changes."
