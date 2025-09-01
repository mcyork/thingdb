#!/bin/bash
# watch-and-push.sh - Watch for file changes and automatically push to Pi
# Requires fswatch (install with: brew install fswatch)

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
WATCH_DIR="src"

# Check if fswatch is available
if ! command -v fswatch &> /dev/null; then
    print_error "fswatch not found. Please install it with: brew install fswatch"
    exit 1
fi

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

# Check if watch directory exists
if [ ! -d "$WATCH_DIR" ]; then
    print_error "Watch directory not found: $WATCH_DIR"
    exit 1
fi

print_status "Starting file watcher for: $WATCH_DIR"
print_status "Press Ctrl+C to stop watching"

# Function to push a single file
push_file() {
    local file_path="$1"
    
    # Skip certain file types
    if [[ "$file_path" == *"__pycache__"* ]] || \
       [[ "$file_path" == *.pyc ]] || \
       [[ "$file_path" == *.log ]] || \
       [[ "$file_path" == .DS_Store ]]; then
        return
    fi
    
    print_status "File changed: $file_path"
    
    # Determine the relative path from src directory
    if [[ "$file_path" == src/* ]]; then
        RELATIVE_PATH="${file_path#src/}"
    else
        print_warning "Skipping file outside src directory: $file_path"
        return
    fi
    
    print_status "Pushing to: $PI_APP_DIR/$RELATIVE_PATH"
    
    # Stop the application service
    pi run-stream --pi "$PI_NAME" "sudo systemctl stop $SERVICE_NAME" || {
        print_warning "Service was not running or failed to stop"
    }
    
    # Push the file to the Pi
    pi send --pi "$PI_NAME" "$file_path" "/tmp/$(basename "$file_path")"
    
    # Deploy the file on the Pi
    pi run-stream --pi "$PI_NAME" "
        sudo mkdir -p $PI_APP_DIR/$(dirname \"$RELATIVE_PATH\")
        sudo cp /tmp/$(basename \"$file_path\") $PI_APP_DIR/$RELATIVE_PATH
        sudo chown inventory:inventory $PI_APP_DIR/$RELATIVE_PATH
        sudo chmod 644 $PI_APP_DIR/$RELATIVE_PATH
        rm /tmp/$(basename \"$file_path\")
    "
    
    # Start the application service
    pi run-stream --pi "$PI_NAME" "sudo systemctl start $SERVICE_NAME"
    
    print_success "File pushed: $file_path"
}

# Watch for file changes and push them
fswatch -o "$WATCH_DIR" | while read f; do
    # Get list of changed files
    changed_files=$(fswatch -1 "$WATCH_DIR" 2>/dev/null || echo "")
    
    if [ -n "$changed_files" ]; then
        echo "$changed_files" | while read -r file; do
            if [ -f "$file" ]; then
                push_file "$file"
            fi
        done
    fi
done
