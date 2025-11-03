#!/bin/bash
# ThingDB System Dependencies Installer
# This script installs all required system packages for ThingDB

set -e  # Exit on error

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║         ThingDB System Dependencies Installer                  ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Detect OS
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if [ -f /etc/debian_version ]; then
            OS="debian"
        elif [ -f /etc/redhat-release ]; then
            OS="redhat"
        else
            OS="linux"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
    else
        OS="unknown"
    fi
}

# Check if running as root
check_root() {
    if [ "$EUID" -eq 0 ]; then
        echo -e "${YELLOW}Warning: Running as root. This is not recommended.${NC}"
        echo "Please run as a regular user with sudo privileges."
        echo ""
    fi
}

# Install Debian/Ubuntu/Raspberry Pi OS dependencies
install_debian() {
    echo "📦 Installing dependencies for Debian/Ubuntu/Raspberry Pi OS..."
    echo ""
    
    sudo apt update
    
    echo ""
    echo "Installing PostgreSQL and development tools..."
    sudo apt install -y \
        postgresql \
        postgresql-contrib \
        libpq-dev \
        python3-dev \
        python3-pip \
        python3-venv \
        build-essential \
        git
    
    echo ""
    echo -e "${GREEN}✓${NC} System dependencies installed successfully!"
}

# Install macOS dependencies
install_macos() {
    echo "📦 Installing dependencies for macOS..."
    echo ""
    
    # Check if Homebrew is installed
    if ! command -v brew &> /dev/null; then
        echo -e "${RED}✗${NC} Homebrew is not installed."
        echo "Please install Homebrew first:"
        echo "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        exit 1
    fi
    
    echo "Installing PostgreSQL and development tools..."
    brew install postgresql libpq python@3.11
    brew services start postgresql
    
    echo ""
    echo -e "${GREEN}✓${NC} System dependencies installed successfully!"
}

# Setup PostgreSQL database and user
setup_postgresql() {
    echo ""
    echo "🔧 Setting up PostgreSQL database..."
    echo ""
    
    # Check if PostgreSQL is running
    if ! sudo systemctl is-active --quiet postgresql 2>/dev/null && ! brew services list | grep -q "postgresql.*started" 2>/dev/null; then
        echo "Starting PostgreSQL service..."
        if [ "$OS" = "debian" ]; then
            sudo systemctl start postgresql
            sudo systemctl enable postgresql
        elif [ "$OS" = "macos" ]; then
            brew services start postgresql
        fi
    fi
    
    # Create database and user
    echo "Creating ThingDB database and user..."
    echo ""
    
    if [ "$OS" = "macos" ]; then
        # macOS uses current user
        createdb thingdb 2>/dev/null || echo "Database 'thingdb' may already exist"
    else
        # Linux uses postgres user
        sudo -u postgres psql -c "CREATE DATABASE thingdb;" 2>/dev/null || echo "Database 'thingdb' may already exist"
        sudo -u postgres psql -c "CREATE USER thingdb WITH PASSWORD 'thingdb_default_pass';" 2>/dev/null || echo "User 'thingdb' may already exist"
        sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE thingdb TO thingdb;" 2>/dev/null || true
        sudo -u postgres psql -c "ALTER DATABASE thingdb OWNER TO thingdb;" 2>/dev/null || true
        # PostgreSQL 15+ requires explicit schema permissions
        sudo -u postgres psql -d thingdb -c "GRANT ALL ON SCHEMA public TO thingdb;" 2>/dev/null || true
        sudo -u postgres psql -d thingdb -c "GRANT CREATE ON SCHEMA public TO thingdb;" 2>/dev/null || true
    fi
    
    echo ""
    echo -e "${GREEN}✓${NC} PostgreSQL database configured!"
    echo ""
    echo -e "${YELLOW}⚠${NC}  Default database credentials:"
    echo "    Database: thingdb"
    echo "    User: thingdb"
    echo "    Password: thingdb_default_pass"
    echo ""
    echo "    ${RED}CHANGE THIS PASSWORD IN PRODUCTION!${NC}"
}

# Setup systemd service
setup_systemd_service() {
    if [ "$OS" != "debian" ]; then
        echo ""
        echo "⚠️  Systemd service setup only supported on Linux"
        return
    fi
    
    echo ""
    echo "🔧 Setting up systemd service..."
    
    # Check if thingdb.service exists
    if [ ! -f thingdb.service ]; then
        echo -e "${YELLOW}!${NC} thingdb.service file not found in current directory"
        echo "   Skipping systemd service setup"
        return
    fi
    
    # Copy service file to systemd directory
    sudo cp thingdb.service /etc/systemd/system/
    
    # Reload systemd to recognize the new service
    sudo systemctl daemon-reload
    
    echo -e "${GREEN}✓${NC} Systemd service installed!"
    echo ""
    echo "After installing ThingDB with pip, enable and start the service with:"
    echo "  sudo systemctl enable thingdb"
    echo "  sudo systemctl start thingdb"
}

# Create .env file if it doesn't exist
create_env_file() {
    if [ ! -f .env ]; then
        echo ""
        echo "📝 Creating .env configuration file..."
        
        cat > .env << 'EOF'
# ThingDB Environment Configuration
# IMPORTANT: Change these values for production!

# Database Configuration
POSTGRES_HOST=localhost
POSTGRES_PORT=5432
POSTGRES_DB=thingdb
POSTGRES_USER=thingdb
POSTGRES_PASSWORD=thingdb_default_pass

# Flask Configuration
FLASK_DEBUG=0
SECRET_KEY=CHANGE_ME_TO_RANDOM_STRING

# Image Storage
IMAGE_STORAGE_METHOD=filesystem
IMAGE_DIR=/var/lib/thingdb/images

# Application
APP_VERSION=1.4.17
EOF
        
        echo -e "${GREEN}✓${NC} Created .env file"
        echo -e "${YELLOW}⚠${NC}  Please edit .env and set a secure SECRET_KEY and POSTGRES_PASSWORD!"
    else
        echo ""
        echo -e "${GREEN}✓${NC} .env file already exists"
    fi
}

# Main installation
main() {
    detect_os
    check_root
    
    echo "Detected OS: $OS"
    echo ""
    
    case $OS in
        debian)
            install_debian
            setup_postgresql
            ;;
        macos)
            install_macos
            setup_postgresql
            ;;
        *)
            echo -e "${RED}✗${NC} Unsupported operating system: $OS"
            echo "Please install dependencies manually:"
            echo "  - PostgreSQL 12+"
            echo "  - Python 3.9+"
            echo "  - libpq-dev"
            echo "  - python3-dev"
            exit 1
            ;;
    esac
    
    create_env_file
    
    # Create ThingDB data directories
    echo ""
    echo "🤖 Setting up ThingDB data directories..."
    sudo mkdir -p /var/lib/thingdb/cache/models
    sudo mkdir -p /var/lib/thingdb/backups
    sudo mkdir -p /var/lib/thingdb/images
    sudo chown -R $USER:$USER /var/lib/thingdb
    echo -e "${GREEN}✓${NC} ThingDB directories created"
    
    # Configure sudo permissions for power management
    echo ""
    echo "🔐 Setting up sudo permissions for system control..."
    sudo tee /etc/sudoers.d/010_thingdb_power > /dev/null << 'SUDOERSEOF'
# Allow pi user to run power management commands without password
pi ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart thingdb, /usr/bin/systemctl stop thingdb, /usr/bin/systemctl start thingdb, /usr/bin/shutdown, /usr/bin/reboot, /usr/bin/sync
SUDOERSEOF
    sudo chmod 440 /etc/sudoers.d/010_thingdb_power
    echo -e "${GREEN}✓${NC} Sudo permissions configured"
    
    setup_systemd_service
    
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║                 ✅ Installation Complete!                      ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Next steps:"
    echo ""
    echo "1. Install ThingDB Python package:"
    echo "   python3 -m venv venv"
    echo "   source venv/bin/activate"
    echo "   pip install -e ."
    echo ""
    echo "2. Initialize database:"
    echo "   thingdb init"
    echo ""
    echo "3. Enable and start the service:"
    echo "   sudo systemctl enable thingdb"
    echo "   sudo systemctl start thingdb"
    echo ""
    echo "4. Check status:"
    echo "   sudo systemctl status thingdb"
    echo ""
    echo "5. Open browser:"
    echo "   http://$(hostname -I | awk '{print $1}'):5000"
    echo ""
    echo "Service Management:"
    echo "   sudo systemctl start thingdb    - Start service"
    echo "   sudo systemctl stop thingdb     - Stop service"
    echo "   sudo systemctl restart thingdb  - Restart service"
    echo "   sudo systemctl status thingdb   - Check status"
    echo "   sudo journalctl -u thingdb -f   - View logs"
    echo ""
}

main "$@"

