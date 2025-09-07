#!/bin/bash
# Build Update Package Script (Elliptic Curve Version)
# Creates signed update packages for inventory system using EC keys.

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
PACKAGES_DIR="$SCRIPT_DIR/packages"
CONFIG_FILE="$PROJECT_ROOT/src/config.py"

# --- Version Auto-Increment ---
print_status "Reading and incrementing patch version..."
if [ ! -f "$CONFIG_FILE" ]; then
    print_error "Config file not found at $CONFIG_FILE"
    exit 1
fi

CURRENT_VERSION_LINE=$(grep -E "^APP_VERSION\s*=\s*\"[0-9]+\.[0-9]+\.[0-9]+\"" "$CONFIG_FILE")
CURRENT_VERSION=$(echo "$CURRENT_VERSION_LINE" | grep -o -E "[0-9]+\.[0-9]+\.[0-9]+")
MAJOR=$(echo "$CURRENT_VERSION" | cut -d. -f1)
MINOR=$(echo "$CURRENT_VERSION" | cut -d. -f2)
PATCH=$(echo "$CURRENT_VERSION" | cut -d. -f3)
NEW_PATCH=$((PATCH + 1))
NEW_VERSION="$MAJOR.$MINOR.$NEW_PATCH"
sed -i.bak "s/APP_VERSION = \"$CURRENT_VERSION\"/APP_VERSION = \"$NEW_VERSION\"/" "$CONFIG_FILE"
rm "${CONFIG_FILE}.bak"
print_success "Version updated from $CURRENT_VERSION to $NEW_VERSION"
VERSION=$NEW_VERSION
# --- End Version Auto-Increment ---

print_status "Building EC update package for version: $VERSION"
mkdir -p "$PACKAGES_DIR"

# --- EC Signing Configuration ---
KEY_FILE="$PROJECT_ROOT/signing-cert-key/nestdb-leaf.key"

if [ ! -f "$KEY_FILE" ]; then
    print_error "EC signing key not found at: $KEY_FILE"
    exit 1
fi

# Create package name
PACKAGE_NAME="inventory-ec-v${VERSION}"
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
  "dependencies": {},
  "files_included": [
    "src/"
  ],
  "upgrade_steps": [
    {"step": "backup", "description": "Backup current source code"},
    {"step": "extract", "description": "Extract new package"},
    {"step": "restart_service", "description": "Restart inventory-app service"},
    {"step": "validate", "description": "Run health checks"}
  ]
}
EOF
print_success "Manifest created: $MANIFEST_FILE"

# Sign the package
print_status "Signing package with EC key (EdDSA)..."
openssl pkeyutl -sign -inkey "$KEY_FILE" -rawin -in "$PACKAGE_FILE" -out "$SIGNATURE_FILE"
print_success "Package signed: $SIGNATURE_FILE"

# Create final package bundle
BUNDLE_FILE="$PACKAGES_DIR/${PACKAGE_NAME}-bundle.tar.gz"
print_status "Creating final bundle..."
cd "$PACKAGES_DIR"
tar -czf "$BUNDLE_FILE" "${PACKAGE_NAME}.tar.gz" "${PACKAGE_NAME}.tar.gz.sig" "${PACKAGE_NAME}-manifest.json"
print_success "EC update bundle created: $BUNDLE_FILE"

echo ""
print_status "Upload $BUNDLE_FILE to your Pi via the admin interface"
