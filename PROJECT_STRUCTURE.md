# inv2-dev Project Structure

This consolidated folder contains all files needed to build, deploy, and manage the Flask Inventory application.

## Directory Structure

```
inv2-dev/
├── src/                      # Flask application source code
│   ├── main.py              # Main application entry point
│   ├── config.py            # Configuration management
│   ├── database.py          # Database connection logic
│   ├── models.py            # Data models
│   ├── routes/              # Application routes
│   ├── services/            # Business logic services
│   ├── templates/           # HTML templates
│   └── utils/               # Utility functions
│
├── docker/                   # Docker configuration files
│   ├── Dockerfile.flask-dev  # Development Flask container
│   ├── Dockerfile.flask-prod # Production Flask container
│   ├── Dockerfile.nginx      # Nginx proxy container
│   ├── docker-compose-dev.yml
│   └── docker-compose-prod.yml
│
├── config/                   # Runtime configuration
│   ├── app-config/          # Application settings
│   ├── ssl-certs/           # SSL certificates
│   └── data/                # PostgreSQL data (gitignored)
│
├── scripts/                  # Build and management scripts
│   ├── build-dev.sh         # Build development environment
│   ├── build-prod.sh        # Build production images
│   ├── start-dev.sh         # Start development
│   ├── start-prod.sh        # Start production
│   └── package-deploy.sh    # Package for deployment
│
├── requirements/             # Python dependencies
│   ├── base-requirements.txt
│   └── ml-requirements.txt
│
├── startup/                  # Container startup scripts
│   ├── startup-dev.sh
│   └── startup-prod.sh
│
├── pi-deployment/           # Raspberry Pi deployment package
│   ├── data/                # Database export and images
│   ├── install/             # Pi installation scripts
│   └── config/              # Pi-specific configuration
│
├── deploy-prepare.sh        # Creates Pi deployment package
├── DEPLOYMENT_GUIDE.md      # Step-by-step Pi deployment guide
├── DEPLOYMENT_STRATEGIES.md # Deployment approaches and solutions
└── DEPLOYMENT_SUMMARY.md    # Complete deployment system overview
```

## No External Dependencies

This folder is completely self-contained. All dependencies are either:
1. Included in this folder structure
2. Downloaded via pip during Docker build
3. Part of base Docker images

## Building and Running

### Development Mode
```bash
./scripts/build-dev.sh
./scripts/start-dev.sh
```

### Production Mode
```bash
./scripts/build-prod.sh
./scripts/start-prod.sh
```

### Deployment Package
```bash
./scripts/package-deploy.sh
```

## Raspberry Pi Deployment

### Create Deployment Package
```bash
./deploy-prepare.sh
```

This creates a complete deployment package with:
- Application source code
- Python requirements
- Database export
- Image files
- Automated installation script

### Deploy to Pi
```bash
# Transfer package to Pi
scp /tmp/inventory-deploy.tar.gz pi@[pi-ip]:/tmp/

# Extract and deploy on Pi
ssh pi@[pi-ip]
cd /tmp && tar -xzf inventory-deploy.tar.gz && sudo ./deploy.sh
```

## Migration to New Hardware

### Docker Deployment
1. Copy this entire `inv2-dev` folder to the new machine
2. Install Docker and Docker Compose
3. Run the build scripts
4. Start the application

### Raspberry Pi Deployment
1. Run `./deploy-prepare.sh` to create deployment package
2. Transfer package to Pi
3. Run automated deployment script

No other files or dependencies are required.
