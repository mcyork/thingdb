#!/bin/bash
# Remote deployment script using pi CLI tool
# This script runs deployment commands on the Pi without manual SSH

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
PI_CLI="/Users/ianmccutcheon/projects/pi-shell/pi"
if [ ! -f "$PI_CLI" ]; then
    print_error "pi CLI tool not found at $PI_CLI"
    print_error "Please ensure pi-shell is installed and accessible"
    exit 1
fi

# Get the default Pi from pi CLI
print_status "Getting default Pi from pi CLI..."
DEFAULT_PI=$("$PI_CLI" list | grep "Yes" | awk '{print $1}')
if [ -z "$DEFAULT_PI" ]; then
    print_error "No default Pi found. Please set a default Pi first:"
    echo "  $PI_CLI set-default pi1  # or pi2, pi3, etc."
    exit 1
fi

print_status "Default Pi is: $DEFAULT_PI"

# Get Pi details from pi CLI
print_status "Getting Pi connection details..."
PI_INFO=$("$PI_CLI" list | grep "^$DEFAULT_PI")
PI_HOST=$(echo "$PI_INFO" | awk '{print $2}')
PI_USER=$(echo "$PI_INFO" | awk '{print $3}')

if [ -z "$PI_HOST" ] || [ -z "$PI_USER" ]; then
    print_error "Could not find host or user for $DEFAULT_PI"
    print_error "Please check your pi-shell configuration"
    exit 1
fi

print_status "Target: $PI_USER@$PI_HOST"

# Check if the deployment package exists locally
LOCAL_PACKAGE="$HOME/inventory-deploy-build/inventory-deploy.tar.gz"
if [ ! -f "$LOCAL_PACKAGE" ]; then
    print_error "Local deployment package not found at $LOCAL_PACKAGE"
    print_status "Please run ./deploy-prepare.sh first to create the package"
    exit 1
fi

print_status "Found local deployment package: $LOCAL_PACKAGE"

# Transfer the deployment package to the Pi
print_status "Transferring deployment package to Pi..."
print_warning "This may take a few minutes depending on package size and network speed"

# Use SCP to transfer the file (will use SSH keys, no password prompt)
print_status "Using SCP to transfer file..."
if scp "$LOCAL_PACKAGE" "$PI_USER@$PI_HOST:/tmp/inventory-deploy.tar.gz"; then
    print_success "Package transferred successfully to Pi"
else
    print_error "Failed to transfer package to Pi"
    print_status "You can try manual transfer:"
    echo "  scp $LOCAL_PACKAGE $PI_USER@$PI_HOST:/tmp/"
    exit 1
fi

# Verify the file exists on the Pi using the same Pi we transferred to
print_status "Verifying package on Pi..."
if "$PI_CLI" run-stream --pi "$DEFAULT_PI" "ls -la /tmp/inventory-deploy.tar.gz"; then
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

# Check for a --provision flag
if [[ "$1" == "--provision" ]]; then
    print_warning "Adding provisioning step to remote deployment..."
    REMOTE_COMMAND+=" && sudo bash pi-setup/install.sh"
fi

if "$PI_CLI" run-stream --pi "$DEFAULT_PI" "$REMOTE_COMMAND"; then
    print_success "Remote deployment completed successfully!"
    print_status "Your application should now be running on $PI_HOST"
else
    print_error "Remote deployment failed"
    print_status "You can try running the commands manually:"
    echo "  ssh $PI_USER@$PI_HOST"
    echo "  cd /tmp && tar -xzf inventory-deploy.tar.gz && sudo ./deploy.sh"
    exit 1
fi
