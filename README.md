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
# 1. Set target Pi
cd /Users/ianmccutcheon/projects/pi-shell
./pi set-default pi1  # or pi2, pi3, etc.

# 2. Deploy
cd /Users/ianmccutcheon/projects/inv2-dev
./deploy-prepare.sh
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
- **Local**: `https://localhost` (from Pi)
- **Network**: Accessible from any device on your network

### 🚨 Troubleshooting

- **SSH Key Issues**: Use `ssh-keygen -R [PI_IP]` to clear old keys
- **Deployment Failures**: Check Pi logs with `./pi run-stream "sudo journalctl -u inventory-app --no-pager"`
- **SSL Issues**: Script automatically detects and fixes Nginx problems
- **Database Issues**: Script ensures clean, empty database on fresh deployment

## 🛠️ Development Workflow

1. **Code Changes**: Edit files in `src/` - changes reflect immediately in dev mode
2. **Add Dependencies**: Update `requirements/*.txt` files and rebuild
3. **Database Changes**: Handled automatically by the application
4. **Production Build**: Run `./scripts/build-prod.sh` to create production images

## 🧪 Dual-Storage Testing Environment

For testing both database and filesystem image storage methods simultaneously:

### Quick Start
```bash
# Start both storage configurations
./scripts/manage-docker-storage.sh start

# Test both configurations
./scripts/manage-docker-storage.sh test

# Stop everything cleanly
./scripts/manage-docker-storage.sh stop
```

### Complete Workflow
```bash
# 1. Start both configurations (database + filesystem)
./scripts/manage-docker-storage.sh start

# 2. Test both configurations
./scripts/manage-docker-storage.sh test

# 3. Stop everything
./scripts/manage-docker-storage.sh stop

# 4. Check status anytime
./scripts/manage-docker-storage.sh status

# 5. Restart with latest code changes
./scripts/manage-docker-storage.sh restart

# 6. Clean everything (containers, volumes, networks)
./scripts/manage-docker-storage.sh clean
```

### What This Tests
- **Database Storage**: Images stored as BLOB in PostgreSQL (port 8444)
- **Filesystem Storage**: Images stored on local filesystem (port 8443)
- **Environment Variables**: Both use isolated configurations
- **Source Code**: Always tests latest changes from `src/` directory
- **Container Isolation**: No conflicts between storage methods

### Access URLs
- **Database Storage**: https://localhost:8444
- **Filesystem Storage**: https://localhost:8443
- **Local Image Directory**: `/tmp/inventory-images`

### Why This Setup
This environment ensures code changes work consistently across both storage methods before deploying to Raspberry Pi or production environments.

## 📋 Management Commands

### Available Scripts
```bash
scripts/
├── build-dev.sh              # Build development Docker images
├── build-prod.sh             # Build production Docker images
├── start-dev.sh              # Start development environment
├── start-prod.sh             # Start production environment
├── manage-docker-storage.sh  # Manage dual-storage testing environment
└── test-inventory.sh         # Test any Flask inventory system
```

### Documentation
- **README.md** - Main project overview and setup
- **DOCKER-STORAGE-QUICK-REF.md** - Quick reference for Docker testing
- **PI-DEPLOYMENT-STRATEGY.md** - Raspberry Pi deployment roadmap and strategy
- **PYBRIDGE-README.md** - PyBridge tool documentation and Pi management

### Development
```bash
# View logs
docker-compose -f docker/docker-compose-dev.yml logs -f

# Access container shell
docker-compose -f docker/docker-compose-dev.yml exec flask-app /bin/bash

# Stop containers
docker-compose -f docker/docker-compose-dev.yml down
```

### Production
```bash
# View logs
docker-compose -f docker/docker-compose-prod.yml logs -f

# Access container shell
docker-compose -f docker/docker-compose-prod.yml exec flask-app /bin/bash

# Stop containers
docker-compose -f docker/docker-compose-prod.yml down
```

## 🔒 Security

- SSL certificates are auto-generated for localhost
- Production mode disables debug features
- Sensitive configuration stored in `.env` files (gitignored)
- Database passwords are configurable

## 📊 System Requirements

- **Docker**: Version 20.10+
- **Docker Compose**: Version 1.29+
- **RAM**: 4GB minimum, 8GB recommended
- **Disk**: 10GB for images and data
- **CPU**: 2+ cores recommended

## ✅ Verification

To verify the setup is complete and self-contained:

1. No files are referenced outside the `inv2-dev` folder
2. All Docker builds complete successfully
3. Application starts and connects to database
4. SSL certificates are generated automatically
5. Data persists between restarts

## 🆘 Troubleshooting

- **Port conflicts**: Check if ports 80/443 are in use
- **Build failures**: Ensure Docker has enough disk space
- **Database errors**: Check `config/data/` permissions
- **SSL issues**: Delete `config/ssl-certs/` and restart

## 📝 Notes

- This project consolidates previously scattered dev/prod configurations
- All external dependencies have been internalized
- The structure supports both active development and production deployment
- Migration to new hardware requires only Docker installation