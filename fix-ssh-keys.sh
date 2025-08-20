#!/bin/bash
# Fix SSH key fingerprints for fresh Pi installations
# This script clears old SSH keys and establishes fresh connections

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

# Check if we're in the pi-shell directory
if [ ! -f "config.yml" ] || [ ! -f "pi_bridge" ]; then
    print_error "This script must be run from the pi-shell directory"
    exit 1
fi

# Get the default Pi from config
DEFAULT_PI=$(grep "^default:" config.yml | awk '{print $2}')
if [ -z "$DEFAULT_PI" ]; then
    print_error "No default Pi found in config.yml"
    exit 1
fi

print_status "Default Pi is: $DEFAULT_PI"

# Get Pi details from config
PI_HOST=$(grep "^${DEFAULT_PI}:" -A 2 config.yml | grep "host:" | awk '{print $2}')
PI_USER=$(grep "^${DEFAULT_PI}:" -A 2 config.yml | grep "user:" | awk '{print $2}')

if [ -z "$PI_HOST" ] || [ -z "$PI_USER" ]; then
    print_error "Could not find host or user for $DEFAULT_PI in config.yml"
    exit 1
fi

print_status "Target: $PI_USER@$PI_HOST"

# Clear old SSH key fingerprint
print_status "Clearing old SSH key fingerprint for $PI_HOST..."
ssh-keygen -R "$PI_HOST" 2>/dev/null || true
print_success "Old SSH key cleared"

# Test connection (this will prompt for new key acceptance)
print_status "Testing SSH connection to establish new key fingerprint..."
print_warning "You may be prompted to accept the new SSH key fingerprint"
print_warning "Type 'yes' when prompted to continue"

# Try to establish connection and accept new key
if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$PI_USER@$PI_HOST" "echo 'SSH connection successful'" 2>/dev/null; then
    print_success "SSH connection established and new key fingerprint accepted!"
else
    print_error "Failed to establish SSH connection"
    print_status "You may need to manually accept the SSH key:"
    echo "  ssh $PI_USER@$PI_HOST"
    echo "  Type 'yes' when prompted about the key fingerprint"
    exit 1
fi

print_success "SSH key fingerprint issue resolved for $DEFAULT_PI"
print_status "You can now run deployment scripts without SSH key issues"
