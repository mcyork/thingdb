# Flask Inventory System - Consolidated Development Environment

This is a fully self-contained development and production environment for the Flask Inventory Management System. All dependencies are included, and the project can be easily moved to any machine with Docker installed.

## 🎯 Project Goals

- **Self-contained**: No external dependencies outside this folder
- **Portable**: Can be moved to any machine with Docker
- **Dual-mode**: Supports both development and production deployments
- **Clean structure**: Organized separation of concerns

## 🚀 Quick Start

### 🎯 **Deploy to Pi (Most Common)**
```bash
# 1. Change to the inventory directory
asd inv

# 2. Set target Pi (from inventory directory) (pi1, pi2, pi3, etc.)
pi set-default pi1  # or pi2, pi3, etc.

# 2. Fix SSH keys if needed (for fresh Pi installations)
./scripts/fix-ssh-keys.sh

# 3. Create deployment package
./deploy-prepare.sh

# 4. Deploy automatically (transfers package and runs deployment)
./scripts/deploy-remote.sh
```

**Alternative Manual Deployment:**
If you prefer to run deployment commands manually:
```bash
# Transfer package to Pi
scp ~/inventory-deploy-build/inventory-deploy.tar.gz pi@[PI_IP_ADDRESS]:/tmp/

# SSH to Pi
ssh pi@[PI_IP_ADDRESS]

# Extract and deploy
cd /tmp && tar -xzf inventory-deploy.tar.gz && sudo ./deploy.sh
```

### Development Mode
```bash
# Build development images
./scripts/build-dev.sh

# Start development environment
./scripts/start-dev.sh

# Access at https://localhost
```

### Production Mode
```bash
# Build production images
./scripts/build-prod.sh

# Start production environment
./scripts/start-prod.sh

# Access at https://localhost
```

### Dual-Storage Testing (Recommended for Development)
```bash
# Start both database and filesystem storage configurations
./scripts/manage-docker-storage.sh start

# Test both configurations
./scripts/manage-docker-storage.sh test

# Access at https://localhost:8444 (database) and https://localhost:8443 (filesystem)
```

## 📁 Directory Structure

```
inv2-dev/
├── src/                      # Flask application source code
├── docker/                   # Docker configuration files
├── config/                   # Runtime configuration
├── scripts/                  # Build and management scripts
├── requirements/             # Python dependencies
└── startup/                  # Container startup scripts
```

## 🔧 Configuration

### Database Options

1. **Internal PostgreSQL** (Default)
   - No configuration needed
   - Data stored in `config/data/`
   - Perfect for development and single-server deployments

2. **External PostgreSQL**
   - Copy `config/app-config/app.env.example` to `config/app-config/app.env`
   - Configure external database credentials
   - Ideal for production with managed databases

## 🐳 Docker Images

The system builds two main images:

- **Flask Application**: Python app with all dependencies
- **Nginx Proxy**: SSL termination and reverse proxy

## 📦 Deployment to Raspberry Pi

### Prerequisites
- **Pi Shell/PyBridge** installed and configured
- **Target Pi** accessible via SSH
- **Fresh Pi installation** (or Pi you want to redeploy to)

### 🚀 Complete Deployment Workflow

#### Step 1: Set Target Pi
```bash
# Go to pi-shell directory
cd /Users/ianmccutcheon/projects/pi-shell

# Set the Pi you want to deploy to as default
./pi set-default pi1    # or pi2, pi3, etc.

# Verify connection
./pi status
```

#### Step 2: Fix SSH Keys (if fresh Pi)
```bash
# If this is a fresh Pi installation, clear old SSH keys
ssh-keygen -R [PI_IP_ADDRESS]

# Test SSH connection (accept new key when prompted)
ssh -o StrictHostKeyChecking=no pi@[PI_IP_ADDRESS] "echo 'SSH working'"
```

#### Step 3: Deploy
```bash
# Go to inventory project directory
cd /Users/ianmccutcheon/projects/inv2-dev

# Run deployment (automatically handles SSH keys, SSL issues, etc.)
./deploy-prepare.sh
```

### 🎯 What the Deployment Script Does

1. **Tests Docker environment** to ensure code is working
2. **Creates deployment package** with all necessary files
3. **Transfers package to Pi** using PyBridge
4. **Installs system dependencies** (Python, PostgreSQL, Nginx)
5. **Sets up Python environment** with all required packages
6. **Configures PostgreSQL** with clean, empty database
7. **Sets up Nginx** with SSL certificates
8. **Deploys Flask application** as systemd service
9. **Automatically detects and fixes** common issues:
   - Nginx SSL startup problems
   - Port binding issues
   - Service startup failures
10. **Verifies deployment** with comprehensive testing
11. **Tests network accessibility** to ensure your phone can connect

### 🔧 Manual Deployment (if needed)

If automatic deployment fails, the script provides manual instructions:
```bash
# Transfer package manually
scp /Users/ianmccutcheon/inventory-deploy-build/inventory-deploy.tar.gz pi@[PI_IP]:/tmp/

# SSH to Pi and deploy
ssh pi@[PI_IP]
cd /tmp && tar -xzf inventory-deploy.tar.gz && sudo ./deploy.sh
```

### 📱 Access Your System

After successful deployment:
- **HTTPS**: `https://[PI_IP_ADDRESS]`