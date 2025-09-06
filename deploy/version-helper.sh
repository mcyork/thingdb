#!/bin/bash
# version-helper.sh
# Helper script to increment version numbers in src/config.py

set -e

# This script is not meant to be called directly.
# It is used by increment-major.sh, increment-minor.sh, and increment-patch.sh

INCREMENT_TYPE=$1
CONFIG_FILE="$(dirname "$0")/../src/config.py"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Config file not found at $CONFIG_FILE"
    exit 1
fi

# Read current version from config.py
CURRENT_VERSION_LINE=$(grep -E "^APP_VERSION\s*=\s*\"[0-9]+\.[0-9]+\.[0-9]+\"" "$CONFIG_FILE")
if [ -z "$CURRENT_VERSION_LINE" ]; then
    echo "ERROR: APP_VERSION not found or in unexpected format in $CONFIG_FILE"
    exit 1
fi

CURRENT_VERSION=$(echo "$CURRENT_VERSION_LINE" | grep -o -E "[0-9]+\.[0-9]+\.[0-9]+")
MAJOR=$(echo "$CURRENT_VERSION" | cut -d. -f1)
MINOR=$(echo "$CURRENT_VERSION" | cut -d. -f2)
PATCH=$(echo "$CURRENT_VERSION" | cut -d. -f3)

case "$INCREMENT_TYPE" in
    major)
        NEW_MAJOR=$((MAJOR + 1))
        NEW_VERSION="$NEW_MAJOR.0.0"
        ;;
    minor)
        NEW_MINOR=$((MINOR + 1))
        NEW_VERSION="$MAJOR.$NEW_MINOR.0"
        ;;
    patch)
        NEW_PATCH=$((PATCH + 1))
        NEW_VERSION="$MAJOR.$MINOR.$NEW_PATCH"
        ;;
    *)
        echo "ERROR: Invalid increment type '$INCREMENT_TYPE'. Use 'major', 'minor', or 'patch'."
        exit 1
        ;;
esac

# Update the config.py file
sed -i.bak "s/APP_VERSION = \"$CURRENT_VERSION\"/APP_VERSION = \"$NEW_VERSION\"/" "$CONFIG_FILE"
rm "${CONFIG_FILE}.bak"

echo "Version updated from $CURRENT_VERSION to $NEW_VERSION"
