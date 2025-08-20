#!/bin/bash

# Docker Storage Test Script
# Tests both database and filesystem image storage configurations

set -e

echo "🐳 Starting Docker Storage Test Environment"
echo "=============================================="

# Create local image directory for filesystem storage
echo "📁 Creating local image directory..."
mkdir -p /tmp/inventory-images
chmod 755 /tmp/inventory-images

# Function to start database storage configuration
start_database_storage() {
    echo ""
    echo "🗄️  Starting Database Storage Configuration..."
    echo "   Ports: HTTP 8081, HTTPS 8444"
    echo "   Images stored as BLOB in PostgreSQL"
    
    (cd docker && docker-compose -f docker-compose-database.yml up -d)
    
    echo "✅ Database storage configuration started"
    echo "   Access at: http://localhost:8081"
}

# Function to start filesystem storage configuration
start_filesystem_storage() {
    echo ""
    echo "💾 Starting Filesystem Storage Configuration..."
    echo "   Ports: HTTP 8080, HTTPS 8443"
    echo "   Images stored on filesystem at /tmp/inventory-images"
    
    (cd docker && docker-compose -f docker-compose-filesystem.yml up -d)
    
    echo "✅ Filesystem storage configuration started"
    echo "   Access at: http://localhost:8080"
}

# Function to show status
show_status() {
    echo ""
    echo "📊 Docker Status:"
    echo "=================="
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    
    echo ""
    echo "🌐 Access URLs:"
    echo "==============="
    echo "Database Storage:  http://localhost:8081 (images in DB)"
    echo "Filesystem Storage: http://localhost:8080 (images on disk)"
    echo ""
    echo "📁 Local Image Directory: /tmp/inventory-images"
}

# Function to stop all configurations
stop_all() {
    echo ""
    echo "🛑 Stopping all Docker configurations..."
    
    (cd docker && docker-compose -f docker-compose-database.yml down 2>/dev/null || true)
    (cd docker && docker-compose -f docker-compose-filesystem.yml down 2>/dev/null || true)
    
    echo "✅ All configurations stopped"
}

# Main script logic
case "${1:-start}" in
    "start")
        start_database_storage
        start_filesystem_storage
        show_status
        ;;
    "database")
        start_database_storage
        show_status
        ;;
    "filesystem")
        start_filesystem_storage
        show_status
        ;;
    "stop")
        stop_all
        ;;
    "status")
        show_status
        ;;
    *)
        echo "Usage: $0 [start|database|filesystem|stop|status]"
        echo ""
        echo "Commands:"
        echo "  start      - Start both configurations (default)"
        echo "  database   - Start only database storage"
        echo "  filesystem - Start only filesystem storage"
        echo "  stop       - Stop all configurations"
        echo "  status     - Show current status"
        exit 1
        ;;
esac

echo ""
echo "🎯 Next Steps:"
echo "==============="
echo "1. Wait for services to fully start (check with: $0 status)"
echo "2. Test database storage at: http://localhost:8081"
echo "3. Test filesystem storage at: http://localhost:8080"
echo "4. Compare performance and functionality"
echo "5. Stop all with: $0 stop"
