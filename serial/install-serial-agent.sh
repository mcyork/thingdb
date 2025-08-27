#!/bin/bash
# install-serial-agent.sh
# Remote installer for the Pi Serial Agent using pi CLI tool
# This script pushes the serial agent to a Pi and installs it remotely

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

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARBALL="$SCRIPT_DIR/pi-serial-agent.tar.gz"

# Check if tarball exists
if [ ! -f "$TARBALL" ]; then
    print_error "Serial agent tarball not found: $TARBALL"
    exit 1
fi

print_status "Found serial agent package: $TARBALL"

# Transfer the tarball to the Pi
print_status "Transferring serial agent to Pi..."
if "$PI_CLI" send --pi "$DEFAULT_PI" "$TARBALL" /tmp/pi-serial-agent.tar.gz; then
    print_success "Serial agent package transferred to Pi"
else
    print_error "Failed to transfer serial agent package"
    exit 1
fi

# Install the serial agent remotely
print_status "Installing serial agent on Pi..."
print_warning "This requires sudo access on the Pi"

# Run the installation commands remotely
INSTALL_COMMANDS="cd /tmp && rm -rf pi-serial-agent && mkdir -p pi-serial-agent && tar -xzf pi-serial-agent.tar.gz -C pi-serial-agent && cd pi-serial-agent && TTY=ttyAMA0 bash ./install.sh"

if "$PI_CLI" run-stream --pi "$DEFAULT_PI" "sudo bash -c '$INSTALL_COMMANDS'"; then
    print_success "Serial agent installation completed!"
else
    print_error "Serial agent installation failed"
    exit 1
fi

print_status "Serial agent installation complete!"
print_status "What was installed:"
echo "   • UART enabled at 9600 baud"
echo "   • Serial agent service configured"
echo "   • Hardware serial port (/dev/ttyAMA0) activated"
echo ""
print_warning "⚠️  IMPORTANT: Reboot required for UART configuration to take effect"
echo "   After reboot, the serial agent will be available on /dev/ttyAMA0"
echo ""
print_status "🔧 To test after reboot:"
echo "   • Use serial bridge tool from pi-serial project"
echo "   • Or connect with terminal software at 9600 baud"
echo "   • The agent will respond to commands over serial"
echo ""
print_status "🚀 Ready to reboot? Run:"
echo "   $PI_CLI run --pi $DEFAULT_PI 'sudo reboot'"
