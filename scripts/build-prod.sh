#!/bin/bash

# Build script for Production Flask Inventory System
set -e

echo "🔧 Building Production Flask Inventory System..."
echo ""

# Change to the inv2-dev directory
cd "$(dirname "$0")/.."

echo "📋 Build Configuration:"
echo "   Image Name: flask-source:latest"
echo "   Type: Production (source included)"
echo "   Database: Configurable (internal/external)"
echo ""

# Check if source directory exists
if [ ! -d "src" ]; then
    echo "❌ Error: Source directory not found at src/"
    echo "   Please ensure you're running this from inv2-dev directory"
    exit 1
fi

# Check if requirements exist
if [ ! -f "requirements/base-requirements.txt" ] || [ ! -f "requirements/ml-requirements.txt" ]; then
    echo "❌ Error: Requirements files not found"
    echo "   Please ensure requirements/ directory contains:"
    echo "   - base-requirements.txt"
    echo "   - ml-requirements.txt"
    exit 1
fi

echo "🛑 Stopping existing containers..."
docker-compose -f docker/docker-compose-prod.yml down 2>/dev/null || true

echo ""
echo "🐳 Building Production Docker images..."

# Build Flask app with source included
echo "   📦 Building Flask application with embedded source..."
docker build -f docker/Dockerfile.flask-prod -t flask-source:latest .

# Build Nginx proxy
echo "   🌐 Building Nginx proxy..."
docker build -f docker/Dockerfile.nginx -t flask-source-nginx:latest docker/

echo ""
echo "✅ Production images built successfully!"
echo ""
echo "📊 Image Information:"
docker images | grep flask-source | head -2

echo ""
echo "🚀 To start the production system:"
echo "   ./scripts/start-prod.sh"

echo ""
echo "🔧 Configuration Options:"
echo "   1. Internal PostgreSQL (default):"
echo "      - Data stored in ./config/data/"
echo "      - No additional configuration needed"
echo ""
echo "   2. External PostgreSQL:"
echo "      - Copy config/app-config/app.env.example to config/app-config/app.env"
echo "      - Set EXTERNAL_POSTGRES_* variables"
echo "      - Start with: ./scripts/start-prod.sh"