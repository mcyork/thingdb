#!/bin/bash
# deploy.sh - V2 Remote deployment script for Raspberry Pi
# This script deploys the V2 inventory system to a Raspberry Pi.

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

# --- Configuration ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PI_CLI="pi"
LOCAL_PACKAGE="$HOME/inventory-v2-deploy.tar.gz"
REMOTE_PACKAGE_NAME="inventory-v2-deploy.tar.gz"

# Check if pi CLI tool is available
if ! command -v "$PI_CLI" &> /dev/null;
    then
    print_error "pi CLI tool not found. Please install it first."
    exit 1
fi

print_status "Using Pi CLI tool: $PI_CLI"

# Get the default Pi name
DEFAULT_PI=$("$PI_CLI" list | grep "Yes" | awk '{print $1}')
if [ -z "$DEFAULT_PI" ]; then
    print_error "No default Pi configuration found. Please configure one."
    exit 1
fi
print_status "Using default Pi: $DEFAULT_PI"

# Check if Pi is online
if ! "$PI_CLI" status "$DEFAULT_PI" | grep -q "ONLINE"; then
    print_error "Pi '$DEFAULT_PI' is not online"
    exit 1
fi
print_status "✅ Pi '$DEFAULT_PI' is online and ready"

# Check if the deployment package exists locally
if [ ! -f "$LOCAL_PACKAGE" ]; then
    print_error "Local deployment package not found at $LOCAL_PACKAGE"
    print_status "Please run ./deploy/build.sh first to create the package"
    exit 1
fi
print_status "Found local deployment package: $LOCAL_PACKAGE"

# Transfer the deployment package to the Pi
print_status "Transferring V2 deployment package to Pi..."
if "$PI_CLI" send --pi "$DEFAULT_PI" "$LOCAL_PACKAGE" "/tmp/$REMOTE_PACKAGE_NAME"; then
    print_success "Package transferred successfully to Pi"
else
    print_error "Failed to transfer package to Pi"
    exit 1
fi

# Run deployment commands remotely
print_status "Starting remote deployment on $DEFAULT_PI..."
REMOTE_COMMAND="cd /tmp && tar -xzf $REMOTE_PACKAGE_NAME && sudo ./deploy.sh"

if "$PI_CLI" run-stream --pi "$DEFAULT_PI" "$REMOTE_COMMAND"; then
    print_success "Remote deployment completed successfully!"
else
    print_error "Remote deployment failed"
    exit 1
fi

echo ""
print_success "🎯 V2 DEPLOYMENT COMPLETE!"
echo "==============================="
echo "Access your inventory system at: https://$("$PI_CLI" run --pi "$DEFAULT_PI" 'hostname -I | awk "{print \$1}"')"
echo ""
