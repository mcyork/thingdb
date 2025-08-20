#!/bin/bash

echo "🧹 Cleaning up duplicate source code files..."
echo "=============================================="

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "📁 Project root: $PROJECT_ROOT"
echo "🎯 Single source of truth: $PROJECT_ROOT/src/"

# Function to remove duplicate source files
remove_duplicate_src() {
    local target_dir="$1"
    local description="$2"
    
    echo ""
    echo "🧹 Cleaning $description..."
    echo "   Location: $target_dir"
    
    if [ ! -d "$target_dir" ]; then
        echo "   ⚠️  Directory doesn't exist, skipping..."
        return
    fi
    
    # Remove Python source files (but keep deployment-specific files)
    local removed_count=0
    
    # Remove main Python files
    for file in config.py database.py main.py models.py; do
        if [ -f "$target_dir/$file" ]; then
            rm "$target_dir/$file"
            echo "   🗑️  Removed: $file"
            ((removed_count++))
        fi
    done
    
    # Remove routes directory (source code)
    if [ -d "$target_dir/routes" ]; then
        rm -rf "$target_dir/routes"
        echo "   🗑️  Removed: routes/"
        ((removed_count++))
    fi
    
    # Remove services directory (source code)
    if [ -d "$target_dir/services" ]; then
        rm -rf "$target_dir/services"
        echo "   🗑️  Removed: services/"
        ((removed_count++))
    fi
    
    # Remove utils directory (source code)
    if [ -d "$target_dir/utils" ]; then
        rm -rf "$target_dir/utils"
        echo "   🗑️  Removed: utils/"
        ((removed_count++))
    fi
    
    # Remove templates directory (source code)
    if [ -d "$target_dir/templates" ]; then
        rm -rf "$target_dir/templates"
        echo "   🗑️  Removed: templates/"
        ((removed_count++))
    fi
    
    # Remove static directory (source code)
    if [ -d "$target_dir/static" ]; then
        rm -rf "$target_dir/static"
        echo "   🗑️  Removed: static/"
        ((removed_count++))
    fi
    
    # Remove uploads directory (source code)
    if [ -d "$target_dir/uploads" ]; then
        rm -rf "$target_dir/uploads"
        echo "   🗑️  Removed: uploads/"
        ((removed_count++))
    fi
    
    # Remove logs directory (source code)
    if [ -d "$target_dir/logs" ]; then
        rm -rf "$target_dir/logs"
        echo "   🗑️  Removed: logs/"
        ((removed_count++))
    fi
    
    # Remove __pycache__ directories
    find "$target_dir" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
    
    # Remove .pyc files
    find "$target_dir" -name "*.pyc" -delete 2>/dev/null || true
    
    echo "   ✅ Cleaned up $removed_count source code items"
    echo "   💡 Source code will be copied fresh from $PROJECT_ROOT/src/ during deployment"
}

# Clean up duplicate source code in pi-deployment
remove_duplicate_src "$PROJECT_ROOT/pi-deployment" "pi-deployment directory"

# Clean up duplicate source code in pi-image-builder
remove_duplicate_src "$PROJECT_ROOT/pi-image-builder/CustomPiOS/src/inventoryos/modules/inventory/filesystem/home/pi/pi-deployment" "pi-image-builder pi-deployment directory"

echo ""
echo "✅ Cleanup complete!"
echo ""
echo "📋 What was cleaned up:"
echo "   - Duplicate Python source files (config.py, database.py, main.py, models.py)"
echo "   - Duplicate directories (routes/, services/, utils/, templates/, static/, uploads/, logs/)"
echo "   - Python cache files (__pycache__/, *.pyc)"
echo ""
echo "🎯 What remains (and should remain):"
echo "   - Deployment scripts (*.sh)"
echo "   - Configuration files (environment-pi.env, pi-config.py)"
echo "   - Installation files (install/*)"
echo "   - Data directories (data/)"
echo ""
echo "💡 Next steps:"
echo "   1. When you run pi-prep.sh, it will copy FRESH source code from src/"
echo "   2. All deployments will use the latest code from your single source of truth"
echo "   3. No more maintaining source code in multiple places!"
echo ""
echo "🚀 To test: Run ./pi-deployment/scripts/pi-prep.sh to create a fresh deployment package"
