#!/bin/bash
# Build script for Inventory Management System Docker container

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
IMAGE_NAME="inventory-app"
IMAGE_TAG="latest"

print_status "Building Inventory Management System Docker container..."

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    print_error "Docker is not running. Please start Docker first."
    exit 1
fi

# Check if we're in the right directory
if [ ! -f "$PROJECT_ROOT/src/main.py" ]; then
    print_error "Source code not found. Please run this script from the docker/ directory."
    exit 1
fi

# Build the Docker image
print_status "Building Docker image: $IMAGE_NAME:$IMAGE_TAG"
cd "$PROJECT_ROOT"

if docker build -f docker/Dockerfile -t "$IMAGE_NAME:$IMAGE_TAG" .; then
    print_success "Docker image built successfully!"
else
    print_error "Docker build failed!"
    exit 1
fi

# Show image information
print_status "Docker image information:"
docker images "$IMAGE_NAME:$IMAGE_TAG"

print_success "Build complete! You can now run the container with:"
echo "  cd docker && docker-compose up -d"
echo ""
echo "Or run directly with:"
echo "  docker run -d -p 80:80 -p 443:443 --name inventory-app $IMAGE_NAME:$IMAGE_TAG"
