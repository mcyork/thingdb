#!/bin/bash
# build.sh
# Creates a V2 deployment package for Raspberry Pi using externalized configs.

set -e

echo "🚀 Creating V2 Raspberry Pi deployment package..."

# --- Configuration ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_SOURCE_DIR="$SCRIPT_DIR/config"
BUILD_DIR="$HOME/inventory-deploy-build-v2"
PACKAGE_NAME="inventory-v2-deploy.tar.gz"

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m'

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# --- Build Process ---

print_status "Creating clean build directory: $BUILD_DIR"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

print_status "Copying application source code..."
cp -r "$PROJECT_ROOT/src"/* "$BUILD_DIR/"
cp -r "$PROJECT_ROOT/requirements" "$BUILD_DIR/"

print_status "Copying certificate chains for package verification..."
mkdir -p "$BUILD_DIR/signing-certs-and-root"
cp "$PROJECT_ROOT/signing-certs-and-root/ec-certificate-chain.crt" "$BUILD_DIR/signing-certs-and-root/"
cp "$PROJECT_ROOT/signing-certs-and-root/certificate-chain.crt" "$BUILD_DIR/signing-certs-and-root/"
print_success "Source code and certificate chains copied."

print_status "Copying externalized configuration files..."
cp -r "$CONFIG_SOURCE_DIR" "$BUILD_DIR/config"
# Rename the on-pi script to the name the old system expects
mv "$BUILD_DIR/config/on-pi-deploy.sh" "$BUILD_DIR/deploy.sh"
chmod +x "$BUILD_DIR/deploy.sh"
print_success "Configuration files copied."

print_status "Creating deployment package: $PACKAGE_NAME"
cd "$BUILD_DIR"
tar -czf "$PACKAGE_NAME" *.py routes services utils static templates requirements config deploy.sh signing-certs-and-root
mv "$PACKAGE_NAME" "$BUILD_DIR/../" # Move package to deploy dir parent
cd "$PROJECT_ROOT"

print_status "Cleaning up build directory..."
rm -rf "$BUILD_DIR"

print_success "V2 deployment package created successfully!"
echo "📦 Package Location: $HOME/$PACKAGE_NAME"
echo "🚀 To deploy, run: ./deploy/deploy.sh"
