# Flask Inventory System - Consolidated Development Environment

This is a fully self-contained development and production environment for the Flask Inventory Management System. All dependencies are included, and the project can be easily moved to any machine with Docker installed.

## 🎯 Project Goals

- **Self-contained**: No external dependencies outside this folder
- **Portable**: Can be moved to any machine with Docker
- **Dual-mode**: Supports both development and production deployments
- **Clean structure**: Organized separation of concerns

## 🚀 Quick Start

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

## 📦 Deployment to New Hardware

### Method 1: Package and Deploy
```bash
# Create deployment package
./scripts/package-deploy.sh

# Copy the generated .tar.gz file to new machine
# Extract and run deploy.sh on target machine
```

### Method 2: Direct Copy
1. Copy entire `inv2-dev` folder to new machine
2. Install Docker and Docker Compose
3. Run `./scripts/build-prod.sh`
4. Run `./scripts/start-prod.sh`

## 🛠️ Development Workflow

1. **Code Changes**: Edit files in `src/` - changes reflect immediately in dev mode
2. **Add Dependencies**: Update `requirements/*.txt` files and rebuild
3. **Database Changes**: Handled automatically by the application
4. **Production Build**: Run `./scripts/build-prod.sh` to create production images

## 📋 Management Commands

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