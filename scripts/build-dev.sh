#!/bin/bash

# Build script for Development Flask Inventory System
set -e

echo "🔧 Building Development Flask Inventory System..."
echo ""

# Change to the inv2-dev directory
cd "$(dirname "$0")/.."

echo "📋 Build Configuration:"
echo "   Image Name: flask-dev-app:latest"
echo "   Type: Development (with live reload)"
echo "   Database: Internal PostgreSQL"
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
docker-compose -f docker/docker-compose-dev.yml down 2>/dev/null || true

echo ""
echo "🐳 Building Development Docker images..."

# Build Flask app for development
echo "   📦 Building Flask development container..."
docker build -f docker/Dockerfile.flask-dev -t flask-dev-app:latest .

# Build Nginx proxy
echo "   🌐 Building Nginx proxy..."
docker build -f docker/Dockerfile.nginx -t flask-dev-nginx:latest docker/

echo ""
echo "✅ Development images built successfully!"
echo ""
echo "📊 Image Information:"
docker images | grep flask-dev | head -2

echo ""
echo "🚀 To start the development system:"
echo "   ./scripts/start-dev.sh"

echo ""
echo "💡 Development Features:"
echo "   - Live code reload (changes in src/ are reflected immediately)"
echo "   - Debug mode enabled"
echo "   - PostgreSQL data persisted in config/data/"
echo "   - Uploads persisted in Docker volume"