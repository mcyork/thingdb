#!/bin/bash

# Package the entire project for deployment to another machine
set -e

echo "📦 Packaging Flask Inventory System for Deployment..."

# Change to the inv2-dev directory
cd "$(dirname "$0")/.."

# Create timestamp for package name
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
PACKAGE_NAME="flask-inventory-deploy-${TIMESTAMP}"

echo "📋 Package Configuration:"
echo "   Name: ${PACKAGE_NAME}.tar.gz"
echo "   Contents: Complete self-contained project"
echo ""

# Build production images first
echo "🐳 Building production images..."
./scripts/build-prod.sh

if [ $? -ne 0 ]; then
    echo "❌ Failed to build production images"
    exit 1
fi

# Create temporary packaging directory
echo "📁 Creating package structure..."
mkdir -p /tmp/${PACKAGE_NAME}

# Copy all necessary files
echo "📋 Copying project files..."
cp -r src /tmp/${PACKAGE_NAME}/
cp -r docker /tmp/${PACKAGE_NAME}/
cp -r scripts /tmp/${PACKAGE_NAME}/
cp -r requirements /tmp/${PACKAGE_NAME}/
cp -r startup /tmp/${PACKAGE_NAME}/
cp -r config/app-config /tmp/${PACKAGE_NAME}/config-app-config
cp PROJECT_STRUCTURE.md /tmp/${PACKAGE_NAME}/

# Export Docker images
echo "🐳 Exporting Docker images..."
docker save flask-source:latest flask-source-nginx:latest | gzip > /tmp/${PACKAGE_NAME}/docker-images.tar.gz

# Create deployment script
cat > /tmp/${PACKAGE_NAME}/deploy.sh << 'EOF'
#!/bin/bash

echo "🚀 Deploying Flask Inventory System..."

# Check Docker installation
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed. Please install Docker first."
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    echo "❌ Docker Compose is not installed. Please install Docker Compose first."
    exit 1
fi

# Load Docker images
echo "📦 Loading Docker images..."
docker load < docker-images.tar.gz

# Create config directories
mkdir -p config/app-config config/ssl-certs config/data

# Copy app config template
cp -r config-app-config/* config/app-config/ 2>/dev/null || true

# Make scripts executable
chmod +x scripts/*.sh startup/*.sh

echo ""
echo "✅ Deployment complete!"
echo ""
echo "📋 Next steps:"
echo "   1. Configure external database (optional):"
echo "      cp config/app-config/app.env.example config/app-config/app.env"
echo "      # Edit app.env with your database settings"
echo ""
echo "   2. Start the production system:"
echo "      ./scripts/start-prod.sh"
echo ""
echo "   3. Access the application:"
echo "      https://your-server-ip"
EOF

chmod +x /tmp/${PACKAGE_NAME}/deploy.sh

# Create README
cat > /tmp/${PACKAGE_NAME}/README.md << 'EOF'
# Flask Inventory System - Deployment Package

This is a complete, self-contained deployment package for the Flask Inventory System.

## Requirements

- Docker
- Docker Compose
- 4GB+ RAM recommended
- 10GB+ disk space

## Quick Deployment

1. Extract this package to your desired location
2. Run: `./deploy.sh`
3. Start the system: `./scripts/start-prod.sh`
4. Access at: https://localhost

## Configuration

### Using Internal Database (Default)
No configuration needed. The system will use an internal PostgreSQL database.

### Using External Database
1. Copy the configuration template:
   ```bash
   cp config/app-config/app.env.example config/app-config/app.env
   ```
2. Edit `config/app-config/app.env` with your database credentials
3. Start the system normally

## Directory Structure

- `src/` - Application source code
- `docker/` - Docker configuration files
- `scripts/` - Management scripts
- `requirements/` - Python dependencies
- `startup/` - Container startup scripts
- `config/` - Runtime configuration (created on deployment)

## Management Commands

- Start production: `./scripts/start-prod.sh`
- Stop production: `docker-compose -f docker/docker-compose-prod.yml down`
- View logs: `docker-compose -f docker/docker-compose-prod.yml logs -f`
- Access shell: `docker-compose -f docker/docker-compose-prod.yml exec flask-app /bin/bash`

## Support

For issues or questions, refer to the PROJECT_STRUCTURE.md file included in this package.
EOF

# Create the package
echo "📦 Creating deployment package..."
cd /tmp
tar -czf ${PACKAGE_NAME}.tar.gz ${PACKAGE_NAME}

# Move to current directory
mv ${PACKAGE_NAME}.tar.gz $(cd - >/dev/null && pwd)/

# Cleanup
rm -rf /tmp/${PACKAGE_NAME}

echo ""
echo "✅ Package created successfully!"
echo ""
echo "📦 Package: ${PACKAGE_NAME}.tar.gz"
echo "📏 Size: $(du -h ${PACKAGE_NAME}.tar.gz | cut -f1)"
echo ""
echo "🚀 Deployment instructions:"
echo "   1. Copy ${PACKAGE_NAME}.tar.gz to target machine"
echo "   2. Extract: tar -xzf ${PACKAGE_NAME}.tar.gz"
echo "   3. Enter directory: cd ${PACKAGE_NAME}"
echo "   4. Run deployment: ./deploy.sh"
echo "   5. Start system: ./scripts/start-prod.sh"