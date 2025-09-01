#!/bin/bash
# status.sh - Check application status on Pi

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

echo ""
print_status "=== Application Status ==="
pi run-stream --pi "$PI_NAME" "sudo systemctl status $SERVICE_NAME --no-pager"

echo ""
print_status "=== Recent Logs ==="
pi run-stream --pi "$PI_NAME" "sudo journalctl -u $SERVICE_NAME --no-pager -n 20"

echo ""
print_status "=== Application Directory ==="
pi run --pi "$PI_NAME" "ls -la $PI_APP_DIR"

echo ""
print_status "=== Process Status ==="
pi run --pi "$PI_NAME" "ps aux | grep gunicorn | grep -v grep"
