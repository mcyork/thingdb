#!/bin/bash
# deploy-remote-clean.sh - Remote deployment script for Raspberry Pi (clean version)
# This script deploys the inventory system to a Raspberry Pi without network provisioning

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

# Check if pi CLI tool is available
if ! command -v pi &> /dev/null; then
    print_error "pi CLI tool not found. Please install it first."
    exit 1
fi

# Check if default Pi configuration exists
if ! pi list | grep -q "DEFAULT"; then
    print_error "No default Pi configuration found. Please configure a default Pi first."
    echo "Available Pis:"
    pi list
    exit 1
fi

# Get the default Pi name
DEFAULT_PI=$(pi list | grep "Yes" | awk '{print $1}')
print_status "Using default Pi: $DEFAULT_PI"

# Check if Pi is online
if ! pi status "$DEFAULT_PI" | grep -q "ONLINE"; then
    print_error "Pi '$DEFAULT_PI' is not online"
    echo "Current status:"
    pi status "$DEFAULT_PI"
    exit 1
fi

print_status "✅ Pi '$DEFAULT_PI' is online and ready"

# Check if the deployment package exists locally
LOCAL_PACKAGE="$HOME/inventory-deploy-build/inventory-deploy.tar.gz"
if [ ! -f "$LOCAL_PACKAGE" ]; then
    print_error "Local deployment package not found at $LOCAL_PACKAGE"
    print_status "Please run ./deploy-prepare-clean.sh first to create the package"
    exit 1
fi

print_status "Found local deployment package: $LOCAL_PACKAGE"

# Transfer the deployment package to the Pi
print_status "Transferring deployment package to Pi..."
print_warning "This may take a few minutes depending on package size and network speed"

# Use pi CLI to transfer the file
print_status "Using pi CLI to transfer file..."
if pi send --pi "$DEFAULT_PI" "$LOCAL_PACKAGE" "/tmp/inventory-deploy.tar.gz"; then
    print_success "Package transferred successfully to Pi"
else
    print_error "Failed to transfer package to Pi"
    print_status "You can try manual transfer:"
    echo "  scp $LOCAL_PACKAGE $DEFAULT_PI:/tmp/"
    exit 1
fi

# Verify the file exists on the Pi
print_status "Verifying package on Pi..."
if pi run-stream --pi "$DEFAULT_PI" "ls -la /tmp/inventory-deploy.tar.gz"; then
    print_success "Package verified on Pi"
else
    print_error "Package not found on Pi after transfer"
    exit 1
fi

print_status "Starting remote deployment on $DEFAULT_PI..."
print_warning "This will extract and run the deployment script on the Pi"

# Run deployment commands remotely using pi CLI
print_status "Running deployment commands remotely..."

# Base command
REMOTE_COMMAND="cd /tmp && tar -xzf inventory-deploy.tar.gz && sudo ./deploy.sh"

# Run the main deployment
print_status "Running main deployment..."
if pi run-stream --pi "$DEFAULT_PI" "$REMOTE_COMMAND"; then
    print_success "Remote deployment completed successfully!"
    print_status "Your application should now be running on $DEFAULT_PI"
else
    print_error "Remote deployment failed"
    print_status "You can try running the commands manually:"
    echo "  pi run --pi $DEFAULT_PI"
    echo "  cd /tmp && tar -xzf inventory-deploy.tar.gz && sudo ./deploy.sh"
    exit 1
fi

echo ""
print_success "🎯 DEPLOYMENT COMPLETE!"
echo "==============================="
echo ""
echo "📱 Next Steps:"
echo "• Access your inventory system at: https://$(pi run --pi "$DEFAULT_PI" 'hostname -I | awk \"{print \\$1}\"')"
echo "• Or use: https://raspberrypi.local (if mDNS is enabled)"
echo ""
echo "🔧 Verification Commands:"
echo "• Check service status: pi run --pi $DEFAULT_PI 'systemctl status inventory-app'"
echo "• View logs: pi run --pi $DEFAULT_PI 'journalctl -u inventory-app -f'"
echo "• Test web interface: pi run --pi $DEFAULT_PI 'curl -k https://localhost/'"
echo ""
print_status "🚀 Your inventory system is now deployed and running!"
