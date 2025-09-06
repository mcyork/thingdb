#!/bin/bash
# Build Update Package Script
# Creates signed update packages for inventory system

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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CERT_DIR="$SCRIPT_DIR/signing-certs-and-root"
PACKAGES_DIR="$SCRIPT_DIR/packages"

# Check if we're in the right directory
if [ ! -f "$PROJECT_ROOT/src/main.py" ]; then
    print_error "This script must be run from the project root directory"
    exit 1
fi

# Get the script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$PROJECT_ROOT/src/config.py"

# --- Version Auto-Increment ---
print_status "Reading and incrementing patch version..."
if [ ! -f "$CONFIG_FILE" ]; then
    print_error "Config file not found at $CONFIG_FILE"
    exit 1
fi

# Read current version from config.py
CURRENT_VERSION_LINE=$(grep -E "^APP_VERSION\s*=\s*\"[0-9]+\.[0-9]+\.[0-9]+\"" "$CONFIG_FILE")
if [ -z "$CURRENT_VERSION_LINE" ]; then
    print_error "APP_VERSION not found or in unexpected format in $CONFIG_FILE"
    exit 1
fi

CURRENT_VERSION=$(echo "$CURRENT_VERSION_LINE" | grep -o -E "[0-9]+\.[0-9]+\.[0-9]+")
MAJOR=$(echo "$CURRENT_VERSION" | cut -d. -f1)
MINOR=$(echo "$CURRENT_VERSION" | cut -d. -f2)
PATCH=$(echo "$CURRENT_VERSION" | cut -d. -f3)

# Increment the patch version
NEW_PATCH=$((PATCH + 1))
NEW_VERSION="$MAJOR.$MINOR.$NEW_PATCH"

# Update the config.py file
sed -i.bak "s/APP_VERSION = \"$CURRENT_VERSION\"/APP_VERSION = \"$NEW_VERSION\"/" "$CONFIG_FILE"
rm "${CONFIG_FILE}.bak"

print_success "Version updated from $CURRENT_VERSION to $NEW_VERSION"
VERSION=$NEW_VERSION
# --- End Version Auto-Increment ---

print_status "Building update package for version: $VERSION"

# Create packages directory
mkdir -p "$PACKAGES_DIR"

# Check for signing certificates
CERT_FILE="$PROJECT_ROOT/signing-certs-and-root/eSoup+Signing+CA+INT.crt"
KEY_FILE="$PROJECT_ROOT/signing-cert-key/eSoup+Signing+CA+INT.key"


if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
    print_error "Signing certificates not found"
    print_status "Please ensure certificates are in the correct locations:"
    print_status "  Certificate: $CERT_FILE"
    print_status "  Private Key: $KEY_FILE"
    exit 1
fi

# Create package name
PACKAGE_NAME="inventory-v${VERSION}"
PACKAGE_FILE="$PACKAGES_DIR/${PACKAGE_NAME}.tar.gz"
SIGNATURE_FILE="$PACKAGES_DIR/${PACKAGE_NAME}.tar.gz.sig"
MANIFEST_FILE="$PACKAGES_DIR/${PACKAGE_NAME}-manifest.json"

# Create source package
print_status "Creating source package..."
cd "$PROJECT_ROOT"
tar -czf "$PACKAGE_FILE" src/

# Calculate package hash
PACKAGE_HASH=$(sha256sum "$PACKAGE_FILE" | cut -d' ' -f1)
PACKAGE_SIZE=$(stat -f%z "$PACKAGE_FILE" 2>/dev/null || stat -c%s "$PACKAGE_FILE")

print_success "Package created: $PACKAGE_FILE ($PACKAGE_SIZE bytes)"

# Create manifest
print_status "Creating package manifest..."
cat > "$MANIFEST_FILE" << EOF
{
  "package_name": "$PACKAGE_NAME",
  "version": "$VERSION",
  "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "package_size": $PACKAGE_SIZE,
  "package_hash": "$PACKAGE_HASH",
  "rollback_safe": true,
  "restarts_expected": 2,
  "dependencies": {
    "python_packages": [
      "reportlab==4.0.4",
      "qrcode[pil]==7.4.2"
    ]
  },
  "files_included": [
    "src/routes/",
    "src/templates/",
    "src/services/",
    "src/utils/",
    "src/main.py",
    "src/config.py",
    "src/database.py",
    "src/models.py"
  ],
  "upgrade_steps": [
    {
      "step": "backup",
      "description": "Backup current source code"
    },
    {
      "step": "extract", 
      "description": "Extract new package"
    },
    {
      "step": "install_deps",
      "description": "Install new Python dependencies"
    },
    {
      "step": "restart_service",
      "description": "Restart inventory-app service"
    },
    {
      "step": "validate",
      "description": "Run health checks"
    },
    {
      "step": "cleanup",
      "description": "Remove backup if successful"
    }
  ]
}
EOF

print_success "Manifest created: $MANIFEST_FILE"

# Sign the package
print_status "Signing package with intermediate CA..."
print_status "Using key file: $KEY_FILE"
print_status "Signing package: $PACKAGE_FILE"
print_status "Output signature: $SIGNATURE_FILE"

# Test if key file exists and is readable
if [ ! -r "$KEY_FILE" ]; then
    print_error "Private key file is not readable: $KEY_FILE"
    print_status "Please check file permissions and path"
    exit 1
fi

openssl dgst -sha256 -sign "$KEY_FILE" -out "$SIGNATURE_FILE" "$PACKAGE_FILE"

print_success "Package signed: $SIGNATURE_FILE"

# Create final package bundle
BUNDLE_FILE="$PACKAGES_DIR/${PACKAGE_NAME}-bundle.tar.gz"
print_status "Creating final bundle..."
cd "$PACKAGES_DIR"
tar -czf "$BUNDLE_FILE" "${PACKAGE_NAME}.tar.gz" "${PACKAGE_NAME}.tar.gz.sig" "${PACKAGE_NAME}-manifest.json"

print_success "Update bundle created: $BUNDLE_FILE"

# Display package info
echo ""
print_status "Package Information:"
echo "  Version: $VERSION"
echo "  Package: $PACKAGE_FILE"
echo "  Size: $PACKAGE_SIZE bytes"
echo "  Hash: $PACKAGE_HASH"
echo "  Bundle: $BUNDLE_FILE"
echo "  Rollback Safe: true"
echo "  Expected Restarts: 2"

print_success "Update package build complete!"
print_status "Upload $BUNDLE_FILE to your Pi via the admin interface"
