#!/bin/bash

# Docker Storage Testing Environment Manager
# Manages both database and filesystem storage configurations simultaneously
# Ensures clean, isolated testing of latest source code changes

set -e

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
DATABASE_DIR="docker-storage-test/database"
FILESYSTEM_DIR="docker-storage-test/filesystem"
DATABASE_URL="https://localhost:8444"
FILESYSTEM_URL="https://localhost:8443"

# Helper functions
print_header() {
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}============================================${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_status() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Function to start both configurations
start_dockers() {
    print_header "Starting Docker Storage Testing Environment"
    
    # Create local image directory
    echo "📁 Creating local image directory..."
    mkdir -p /tmp/inventory-images
    chmod 755 /tmp/inventory-images
    
    # Start database storage configuration
    echo ""
    echo "🗄️  Starting Database Storage Configuration..."
    echo "   Ports: HTTP 8081, HTTPS 8444"
    echo "   Images stored as BLOB in PostgreSQL"
    
    (cd "$DATABASE_DIR" && docker-compose -f docker-compose-database.yml up -d)
    
    print_success "Database storage configuration started"
    echo "   Access at: $DATABASE_URL"
    
    # Start filesystem storage configuration
    echo ""
    echo "💾 Starting Filesystem Storage Configuration..."
    echo "   Ports: HTTP 8080, HTTPS 8443"
    echo "   Images stored on filesystem at /tmp/inventory-images"
    
    (cd "$FILESYSTEM_DIR" && docker-compose -f docker-compose-filesystem.yml up -d)
    
    print_success "Filesystem storage configuration started"
    echo "   Access at: $FILESYSTEM_URL"
    
    # Wait for services to start
    echo ""
    print_status "Waiting for services to fully start..."
    sleep 20
    
    # Show status
    show_status
}

# Function to stop both configurations
stop_dockers() {
    print_header "Stopping Docker Storage Testing Environment"
    
    echo "🛑 Stopping database storage configuration..."
    (cd "$DATABASE_DIR" && docker-compose -f docker-compose-database.yml down 2>/dev/null || true)
    
    echo "🛑 Stopping filesystem storage configuration..."
    (cd "$FILESYSTEM_DIR" && docker-compose -f docker-compose-filesystem.yml down 2>/dev/null || true)
    
    print_success "All configurations stopped"
    
    # Clean up any orphaned containers
    echo "🧹 Cleaning up orphaned containers..."
    docker container prune -f >/dev/null 2>&1 || true
    
    print_success "Cleanup completed"
}

# Function to show current status
show_status() {
    print_header "Docker Storage Testing Environment Status"
    
    echo "📊 Container Status:"
    echo "=================="
    
    if docker ps | grep -q "flask-database\|flask-filesystem"; then
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "(flask-database|flask-filesystem)" || true
    else
        print_warning "No storage containers are running"
    fi
    
    echo ""
    echo "🌐 Access URLs:"
    echo "==============="
    echo "Database Storage:  $DATABASE_URL (images in DB)"
    echo "Filesystem Storage: $FILESYSTEM_URL (images on disk)"
    
    echo ""
    echo "📁 Local Image Directory: /tmp/inventory-images"
    
    # Check if services are responding
    echo ""
    echo "🔍 Service Health Check:"
    echo "======================="
    
    # Test database storage
    if curl -s -k -f "$DATABASE_URL" >/dev/null 2>&1; then
        print_success "Database Storage: Responding"
    else
        print_error "Database Storage: Not responding"
    fi
    
    # Test filesystem storage
    if curl -s -k -f "$FILESYSTEM_URL" >/dev/null 2>&1; then
        print_success "Filesystem Storage: Responding"
    else
        print_error "Filesystem Storage: Not responding"
    fi
}

# Function to test both configurations
test_dockers() {
    print_header "Testing Docker Storage Configurations"
    
    # Check if services are running
    if ! docker ps | grep -q "flask-database\|flask-filesystem"; then
        print_error "No storage containers are running. Please start them first with: $0 start"
        exit 1
    fi
    
    # Wait for services to be ready
    print_status "Waiting for services to be ready..."
    sleep 10
    
    # Run the comprehensive test script
    echo ""
    print_status "Running comprehensive tests..."
    if [ -f "./scripts/test-inventory.sh" ]; then
        ./scripts/test-inventory.sh
    else
        print_warning "Test script not found. Running basic connectivity tests..."
        
        # Basic connectivity tests
        echo ""
        echo "🔍 Basic Connectivity Tests:"
        echo "============================"
        
        # Test database storage
        echo "Testing Database Storage ($DATABASE_URL)..."
        if curl -s -k -f "$DATABASE_URL" >/dev/null 2>&1; then
            print_success "Database Storage: Homepage accessible"
        else
            print_error "Database Storage: Homepage not accessible"
        fi
        
        # Test filesystem storage
        echo "Testing Filesystem Storage ($FILESYSTEM_URL)..."
        if curl -s -k -f "$FILESYSTEM_URL" >/dev/null 2>&1; then
            print_success "Filesystem Storage: Homepage accessible"
        else
            print_error "Filesystem Storage: Homepage not accessible"
        fi
    fi
}

# Function to rebuild images with latest source code
rebuild_dockers() {
    print_header "Rebuilding Docker Images with Latest Source Code"
    
    echo "🔨 Building database storage image..."
    docker build -f docker/Dockerfile.flask-prod -t flask-database:latest .
    
    echo "🔨 Building filesystem storage image..."
    docker build -f docker/Dockerfile.flask-prod -t flask-filesystem:latest .
    
    print_success "Images rebuilt successfully"
    
    echo ""
    print_warning "Note: You'll need to restart the containers to use the new images"
    echo "Use: $0 restart"
}

# Function to restart configurations
restart_dockers() {
    print_header "Restarting Docker Storage Testing Environment"
    
    stop_dockers
    sleep 5
    start_dockers
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  start     Start both database and filesystem storage configurations"
    echo "  stop      Stop both configurations and clean up"
    echo "  restart   Stop, wait, then start both configurations"
    echo "  status    Show current status of both configurations"
    echo "  test      Run comprehensive tests on both configurations"
    echo "  rebuild   Rebuild Docker images with latest source code"
    echo "  clean     Stop everything and remove all related containers/volumes"
    echo ""
    echo "Examples:"
    echo "  $0 start          # Start both configurations"
    echo "  $0 test           # Test both configurations"
    echo "  $0 stop           # Stop both configurations"
    echo "  $0 restart        # Restart both configurations"
    echo ""
    echo "This script ensures clean, isolated testing of both storage methods"
    echo "with the latest source code changes."
}

# Function to clean everything
clean_all() {
    print_header "Cleaning All Docker Storage Testing Resources"
    
    print_warning "This will remove ALL containers, volumes, and networks related to storage testing"
    echo "Are you sure? (y/N)"
    read -r response
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo "🧹 Cleaning up..."
        
        # Stop and remove containers
        stop_dockers
        
        # Remove volumes
        docker volume rm docker_flask-database-uploads docker_postgres-database-data docker_flask-filesystem-uploads docker_postgres-filesystem-data docker_flask-images 2>/dev/null || true
        
        # Remove networks
        docker network rm docker_flask-database-network docker_flask-filesystem-network 2>/dev/null || true
        
        # Remove images
        docker rmi flask-database:latest flask-filesystem:latest 2>/dev/null || true
        
        print_success "All storage testing resources cleaned up"
    else
        echo "Cleanup cancelled"
    fi
}

# Main script logic
case "${1:-help}" in
    "start")
        start_dockers
        ;;
    "stop")
        stop_dockers
        ;;
    "restart")
        restart_dockers
        ;;
    "status")
        show_status
        ;;
    "test")
        test_dockers
        ;;
    "rebuild")
        rebuild_dockers
        ;;
    "clean")
        clean_all
        ;;
    "help"|*)
        show_usage
        exit 1
        ;;
esac

echo ""
print_success "Operation completed successfully!"
echo ""
echo "🎯 Next Steps:"
echo "==============="
echo "• Check status: $0 status"
echo "• Run tests: $0 test"
echo "• Stop everything: $0 stop"
echo "• Get help: $0 help"
