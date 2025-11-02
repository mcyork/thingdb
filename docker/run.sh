#!/bin/bash
# Run script for Inventory Management System Docker container

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
IMAGE_NAME="inventory-app"
IMAGE_TAG="latest"
CONTAINER_NAME="inventory-app"

print_status "Starting Inventory Management System..."

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    print_error "Docker is not running. Please start Docker first."
    exit 1
fi

# Check if image exists
if ! docker images "$IMAGE_NAME:$IMAGE_TAG" | grep -q "$IMAGE_NAME"; then
    print_error "Docker image $IMAGE_NAME:$IMAGE_TAG not found."
    print_status "Please run ./build.sh first to build the image."
    exit 1
fi

# Stop and remove existing container if it exists
if docker ps -a | grep -q "$CONTAINER_NAME"; then
    print_status "Stopping existing container..."
    docker stop "$CONTAINER_NAME" > /dev/null 2>&1 || true
    print_status "Removing existing container..."
    docker rm "$CONTAINER_NAME" > /dev/null 2>&1 || true
fi

# Create volumes if they don't exist
print_status "Creating Docker volumes..."
docker volume create inventory_postgres_data > /dev/null 2>&1 || true
docker volume create inventory_images_data > /dev/null 2>&1 || true
docker volume create inventory_ml_cache_data > /dev/null 2>&1 || true
docker volume create inventory_ssl_data > /dev/null 2>&1 || true
docker volume create inventory_config_data > /dev/null 2>&1 || true

# Run the container
print_status "Starting container: $CONTAINER_NAME"
docker run -d \
    --name "$CONTAINER_NAME" \
    -p 80:80 \
    -p 443:443 \
    -v inventory_postgres_data:/var/lib/postgresql/data \
    -v inventory_images_data:/var/lib/inventory/images \
    -v inventory_ml_cache_data:/var/lib/inventory/ml_cache \
    -v inventory_ssl_data:/var/lib/inventory/ssl \
    -v inventory_config_data:/var/lib/inventory/config \
    --restart unless-stopped \
    "$IMAGE_NAME:$IMAGE_TAG"

# Wait for container to start
print_status "Waiting for container to start..."
sleep 10

# Check if container is running
if docker ps | grep -q "$CONTAINER_NAME"; then
    print_success "Container started successfully!"
    
    # Show container status
    print_status "Container status:"
    docker ps | grep "$CONTAINER_NAME"
    
    # Show logs
    print_status "Recent logs:"
    docker logs --tail 20 "$CONTAINER_NAME"
    
    print_success "Inventory Management System is running!"
    print_status "Access the application at:"
    echo "  HTTP:  http://localhost"
    echo "  HTTPS: https://localhost"
    echo ""
    print_status "To view logs: docker logs -f $CONTAINER_NAME"
    print_status "To stop: docker stop $CONTAINER_NAME"
    print_status "To remove: docker rm $CONTAINER_NAME"
else
    print_error "Container failed to start!"
    print_status "Container logs:"
    docker logs "$CONTAINER_NAME"
    exit 1
fi
