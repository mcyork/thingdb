#!/bin/bash

# Package Flask Inventory System for Synology NAS with high ports
# Creates a ZIP file with Docker images, database, and runtime files
set -e

echo "📦 Creating NAS deployment package (ZIP format)..."
echo ""

# Change to the inv2-dev directory
cd "$(dirname "$0")/.."

# Configuration
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
PACKAGE_NAME="flask-inventory-nas-${TIMESTAMP}"
TEMP_DIR="/tmp/${PACKAGE_NAME}"

echo "📋 Package Configuration:"
echo "   Name: ${PACKAGE_NAME}.zip"
echo "   Format: ZIP (for Synology NAS)"
echo "   Ports: 9080 (HTTP), 9443 (HTTPS), 9404 (stats)"
echo ""

# Build production images first
echo "🐳 Building production images..."
./scripts/build-prod.sh

if [ $? -ne 0 ]; then
    echo "❌ Failed to build production images"
    exit 1
fi

# Create temporary directory
echo "📁 Creating package structure..."
rm -rf "${TEMP_DIR}"
mkdir -p "${TEMP_DIR}"

# Save Docker images as tar files
echo "💾 Saving Docker images..."
docker save flask-source:latest -o "${TEMP_DIR}/flask-source-image.tar"
docker save flask-source-nginx:latest -o "${TEMP_DIR}/flask-source-nginx-image.tar"

# Copy configuration (including any existing data)
echo "📋 Copying configuration and data..."
mkdir -p "${TEMP_DIR}/config"
cp -r config/app-config "${TEMP_DIR}/config/" 2>/dev/null || mkdir -p "${TEMP_DIR}/config/app-config"

# Copy SSL certificates if they exist
if [ -d "config/ssl-certs" ] && [ "$(ls -A config/ssl-certs 2>/dev/null)" ]; then
    cp -r config/ssl-certs "${TEMP_DIR}/config/"
    echo "✅ SSL certificates copied"
else
    mkdir -p "${TEMP_DIR}/config/ssl-certs"
    echo "⚠️  No SSL certificates found - will be generated on first run"
fi

# Copy database if it exists
if [ -d "config/data" ] && [ "$(ls -A config/data 2>/dev/null)" ]; then
    echo "🗄️  Copying database files..."
    cp -r config/data "${TEMP_DIR}/config/"
    echo "✅ Database files copied"
else
    mkdir -p "${TEMP_DIR}/config/data"
    echo "⚠️  No database found - will be initialized on first run"
fi

# Create docker-compose for NAS with high ports
cat > "${TEMP_DIR}/docker-compose.yml" << 'EOF'
version: '3.8'

services:
  nginx:
    image: flask-source-nginx:latest
    ports:
      - "9080:80"      # HTTP (redirects to HTTPS) - high port for NAS
      - "9443:443"     # HTTPS - high port for NAS  
      - "9404:8404"    # Nginx stats - high port for NAS
    volumes:
      - ./config/ssl-certs:/ssl-certs  # SSL certificates
    depends_on:
      - flask-app
    restart: unless-stopped
    networks:
      - flask-network

  flask-app:
    image: flask-source:latest
    volumes:
      - ./config:/config                    # All configuration
      - ./config/ssl-certs:/ssl-certs      # SSL certificates
      - flask-uploads:/app/uploads         # Persistent image uploads
    environment:
      - FLASK_ENV=production
      - FLASK_DEBUG=0
      - SSL_ENABLED=true
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-flask_prod_pass}
    restart: unless-stopped
    expose:
      - "5000"
    networks:
      - flask-network

volumes:
  flask-uploads:
    driver: local

networks:
  flask-network:
    driver: bridge
EOF

# Create start script for NAS
cat > "${TEMP_DIR}/start.sh" << 'EOF'
#!/bin/bash
echo "🚀 Starting Flask Inventory System on NAS..."

# Change to script directory
cd "$(dirname "$0")"

# Check if Docker images need to be loaded
if ! docker image inspect flask-source:latest >/dev/null 2>&1; then
    if [ -f "flask-source-image.tar" ]; then
        echo "📦 Loading Flask application image..."
        docker load < flask-source-image.tar
    else
        echo "❌ flask-source-image.tar not found"
        exit 1
    fi
fi

if ! docker image inspect flask-source-nginx:latest >/dev/null 2>&1; then
    if [ -f "flask-source-nginx-image.tar" ]; then
        echo "📦 Loading Nginx image..."
        docker load < flask-source-nginx-image.tar
    else
        echo "❌ flask-source-nginx-image.tar not found"
        exit 1
    fi
fi

# Generate SSL certificates if they don't exist
if [ ! -f "config/ssl-certs/cert.pem" ]; then
    echo "🔐 Generating SSL certificates..."
    mkdir -p config/ssl-certs
    openssl req -x509 -newkey rsa:2048 -keyout config/ssl-certs/private.key \
        -out config/ssl-certs/cert.crt -days 365 -nodes \
        -subj "/C=US/ST=Local/L=NAS/O=FlaskInventory/CN=nas.local" 2>/dev/null
    cat config/ssl-certs/cert.crt config/ssl-certs/private.key > config/ssl-certs/cert.pem
    echo "✅ SSL certificates generated"
fi

# Stop any existing containers
docker-compose down 2>/dev/null || true

# Start services
docker-compose up -d

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Flask Inventory System started successfully!"
    echo ""
    echo "🌐 Access points:"
    echo "   HTTP:  http://$(hostname -I | awk '{print $1}' 2>/dev/null || echo 'nas-ip'):9080"
    echo "   HTTPS: https://$(hostname -I | awk '{print $1}' 2>/dev/null || echo 'nas-ip'):9443"
    echo "   Stats: http://$(hostname -I | awk '{print $1}' 2>/dev/null || echo 'nas-ip'):9404"
    echo ""
    echo "📋 Commands:"
    echo "   View logs: docker-compose logs -f"
    echo "   Stop: docker-compose down"
    echo ""
    echo "💡 After loading images, you can delete the .tar files to save space:"
    echo "   rm flask-source-image.tar flask-source-nginx-image.tar"
else
    echo "❌ Failed to start services"
    echo "Check logs: docker-compose logs"
fi
EOF

chmod +x "${TEMP_DIR}/start.sh"

# Create deployment instructions
cat > "${TEMP_DIR}/DEPLOY.txt" << 'EOF'
Flask Inventory System - NAS Deployment Package
================================================

QUICK START:
1. Extract: unzip flask-inventory-nas-*.zip
2. Run: ./start.sh
3. Access: https://nas-ip:9443

PORTS USED:
- 9080: HTTP (redirects to HTTPS)
- 9443: HTTPS
- 9404: Statistics

EXTRACTION METHODS:
- Best: 7z x flask-inventory-nas-*.zip
- Alternative: unzip flask-inventory-nas-*.zip
- Python: python3 -m zipfile -e flask-inventory-nas-*.zip .

PACKAGE CONTENTS:
- flask-source-image.tar: Flask application Docker image
- flask-source-nginx-image.tar: Nginx proxy Docker image
- docker-compose.yml: Container orchestration (with high ports)
- start.sh: Startup script
- config/: Configuration and data
  - ssl-certs/: SSL certificates
  - data/: PostgreSQL database
  - app-config/: Application settings

SPACE SAVING:
After running start.sh, the Docker images are loaded.
You can delete the .tar files to save ~600MB:
  rm *.tar

DATABASE:
- Internal PostgreSQL is used by default
- Data persists in config/data/
- To use external database, edit config/app-config/app.env

UPDATES:
To update the application:
1. Stop: docker-compose down
2. Load new images: docker load < new-image.tar
3. Start: ./start.sh

TROUBLESHOOTING:
- Port conflicts: Check if 9080/9443/9404 are in use
- Permission issues: Ensure script is executable (chmod +x start.sh)
- Docker issues: Verify Docker is installed and running
EOF

# Create version file
cat > "${TEMP_DIR}/VERSION.txt" << EOF
Flask Inventory System - Production Build
Package created: $(date)
Version: Based on inv2-dev consolidated structure
Deployment: Synology NAS optimized (high ports)

Features:
- Self-contained with embedded source code
- Internal PostgreSQL database
- SSL/HTTPS support
- High ports for NAS compatibility (9080/9443/9404)
- Production-ready with Gunicorn workers
EOF

# Create the ZIP package
echo "📦 Creating ZIP package..."
cd /tmp
zip -r "${PACKAGE_NAME}.zip" "${PACKAGE_NAME}"

# Move to inv2-dev directory
mv "${PACKAGE_NAME}.zip" "$(cd - >/dev/null && pwd)/"

# Cleanup
rm -rf "${TEMP_DIR}"

echo ""
echo "✅ NAS package created successfully!"
echo ""
echo "📦 Package: ${PACKAGE_NAME}.zip"
echo "📏 Size: $(du -h ${PACKAGE_NAME}.zip | cut -f1)"
echo ""
echo "🚀 Deployment instructions:"
echo "   1. Copy ${PACKAGE_NAME}.zip to Synology NAS"
echo "   2. Extract: unzip ${PACKAGE_NAME}.zip"
echo "   3. Enter directory: cd ${PACKAGE_NAME}"
echo "   4. Run: ./start.sh"
echo "   5. Access at: https://nas-ip:9443"
echo ""
echo "📋 Package uses high ports to avoid conflicts:"
echo "   - HTTP:  9080"
echo "   - HTTPS: 9443"
echo "   - Stats: 9404"