# Project Workflow - Comprehensive LLM Prompt

## Overview
You are an expert in the inv2-dev project workflow, which is an inventory management system designed for Raspberry Pi deployment. This guide covers the project structure, deployment strategies, development workflows, and the interactive installer system.

## Project Architecture

### Project Structure
```
inv2-dev/
├── src/                    # Main application source code
├── deploy/                 # Deployment scripts and packages
├── serial/                 # Serial communication components
├── network/                # Network configuration components
├── pi-setup/               # Pi-specific setup scripts
├── pi-image-builder/       # Custom Pi image creation
├── docker/                 # Docker configurations
├── install                 # Interactive installer script
├── scripts/                # Utility and build scripts
└── config/                 # Configuration files and environment
```

### Key Components
- **Flask Web Application**: Main inventory management system
- **Serial Agent**: UART communication for hardware integration
- **Network Management**: BTBerryWifi for WiFi configuration
- **Docker Support**: Containerized deployment options
- **Interactive Installer**: Menu-driven component deployment

## Interactive Installer System

### Overview
The `./install` script provides a unified interface for deploying different components to Raspberry Pi devices. It integrates with the pi CLI tool for seamless remote management.

### Menu Options
1. **Deploy Serial Agent** - Installs UART communication components
2. **Deploy Network Components** - Installs WiFi/Bluetooth management
3. **Deploy Application** - Deploys the full inventory system
4. **Show Status** - Displays system status and available components
5. **Quick Deploy (Serial + Network)** - Installs both components in sequence
6. **Reboot Pi** - Safely reboots the Raspberry Pi
7. **Exit** - Quits the installer

### Usage Examples
```bash
# Run the installer
./install

# Deploy specific components
./install  # Then select option 1 for serial, 2 for network, etc.

# Check system status
./install  # Then select option 4
```

### Component Dependencies
- **Serial Agent**: Requires UART configuration, reboot needed after installation
- **Network Components**: Can be installed remotely or directly on Pi
- **Application**: Requires deployment package from `./deploy/deploy-prepare-clean.sh`

## Deployment Strategies

### Clean Deployment (Recommended)
```bash
# 1. Prepare deployment package
./deploy/deploy-prepare-clean.sh

# 2. Deploy to Pi
./deploy/deploy-remote-clean.sh

# Or use interactive installer
./install  # Select option 3
```

### Component-Based Deployment
```bash
# Deploy only serial components
./install  # Select option 1

# Deploy only network components
./install  # Select option 2

# Deploy both serial and network
./install  # Select option 5
```

### Docker Deployment
```bash
# Development environment
./scripts/start-dev.sh

# Production environment
./scripts/start-prod.sh

# Database-only environment
docker-compose -f docker/docker-compose-database.yml up -d
```

## Development Workflow

### Local Development
```bash
# Start development environment
./scripts/start-dev.sh

# Build development image
./scripts/build-dev.sh

# Access application
# http://localhost:5000 (Flask)
# http://localhost:8080 (Nginx)
```

### Testing and Validation
```bash
# Test inventory system
./scripts/test-inventory.sh

# Test Docker storage
./scripts/test-docker-storage.sh

# Test serial communication
python3 test_serial.py
```

### Building for Production
```bash
# Build production image
./scripts/build-prod.sh

# Create distributable image
./scripts/create-distributable-image.sh

# Package for deployment
./scripts/package-deploy.sh
```

## Serial Communication

### Serial Agent Installation
```bash
# Install via interactive installer
./install  # Select option 1

# Or install manually
./serial/install-serial-agent.sh
```

### Serial Configuration
- **Baud Rate**: 9600 (default)
- **TTY Device**: ttyAMA0 (hardware serial)
- **Service**: systemd service for automatic startup
- **Reboot Required**: After UART configuration changes

### Testing Serial Communication
```bash
# Test from host
python3 test_serial.py

# Test from Pi
python3 quick_serial_test.py

# Check serial service status
pi run --pi pi2 'systemctl status serial-agent@ttyAMA0'
```

## Network Management

### BTBerryWifi Installation
```bash
# Install via interactive installer
./install  # Select option 2

# Choose installation method:
# 1. Direct on Pi (recommended for first-time setup)
# 2. Remote via pi CLI
```

### Network Configuration
- **Bluetooth**: BLE for WiFi configuration
- **NetworkManager**: Modern network management
- **Service Conflicts**: Automatically resolves with dhcpcd/systemd-networkd
- **Default Password**: 'inventory' for BTBerryWifi app

### Post-Installation Steps
```bash
# Reboot required for stable operation
./install  # Select option 6

# Test BTBerryWifi app
# Look for 'inventory' device
# Use password: inventory
```

## Application Deployment

### Prerequisites
```bash
# 1. Build deployment package
./deploy/deploy-prepare-clean.sh

# 2. Ensure Pi is online
pi status pi2

# 3. Have sufficient disk space
pi run --pi pi2 'df -h'
```

### Deployment Process
```bash
# Use interactive installer
./install  # Select option 3

# Or deploy manually
./deploy/deploy-remote-clean.sh
```

### Post-Deployment Verification
```bash
# Check service status
pi run --pi pi2 'systemctl status inventory-app'

# View logs
pi run --pi pi2 'journalctl -u inventory-app -f'

# Test web interface
pi run --pi pi2 'curl -k https://localhost/'
```

## Pi Image Building

### Custom Image Creation
```bash
# Navigate to image builder
cd pi-image-builder/

# Build with pi-gen
./build-with-pi-gen.sh

# Or use rpi-image-gen
cd rpi-image-gen/
./build.sh
```

### Image Customization
- **Overlay Files**: Add custom files to image
- **Boot Configuration**: Customize boot parameters
- **Package Installation**: Pre-install required packages
- **Service Configuration**: Configure systemd services

### Image Deployment
```bash
# Write image to SD card
sudo dd if=output/image.img of=/dev/mmcblk0 bs=4M status=progress

# Verify image
sudo dd if=/dev/mmcblk0 of=verify.img bs=4M count=1000
diff output/image.img verify.img
```

## Docker Integration

### Development Environment
```dockerfile
# Dockerfile.flask-dev
FROM python:3.11-slim
# Development-specific configuration
# Hot-reload enabled
# Debug mode enabled
```

### Production Environment
```dockerfile
# Dockerfile.flask-prod
FROM python:3.11-slim
# Production-optimized
# Multi-stage build
# Security hardening
```

### Storage Strategies
```yaml
# docker-compose-filesystem.yml
volumes:
  - ./uploads:/app/uploads
  - ./data:/app/data
  - ./logs:/app/logs
```

## Configuration Management

### Environment Variables
```bash
# .env file structure
FLASK_ENV=development
DATABASE_URL=sqlite:///inventory.db
SECRET_KEY=your-secret-key
DEBUG=True
```

### Configuration Files
```python
# config.py
import os
from dotenv import load_dotenv

load_dotenv()

class Config:
    SECRET_KEY = os.environ.get('SECRET_KEY') or 'dev'
    DATABASE_URL = os.environ.get('DATABASE_URL') or 'sqlite:///inventory.db'
```

### SSL Configuration
```bash
# Generate SSL certificates
cd docker/
./generate-certs.sh

# Configure nginx with SSL
# nginx.conf includes SSL configuration
```

## Monitoring and Maintenance

### Service Monitoring
```bash
# Check all services
pi run --pi pi2 'systemctl status inventory-app btwifiset bluetooth'

# View service logs
pi run --pi pi2 'journalctl -u inventory-app -f'
pi run --pi pi2 'journalctl -u btwifiset -f'
```

### System Health Checks
```bash
# Check disk usage
pi run --pi pi2 'df -h'

# Check memory usage
pi run --pi pi2 'free -h'

# Check temperature
pi run --pi pi2 'vcgencmd measure_temp'

# Check network status
pi run --pi pi2 'ip addr show'
```

### Backup and Recovery
```bash
# Backup application data
pi run --pi pi2 'tar -czf /tmp/backup.tar.gz /home/pi/data /home/pi/uploads'

# Download backup
pi get --pi pi2 /tmp/backup.tar.gz ./

# Restore from backup
pi send --pi pi2 backup.tar.gz /tmp/
pi run --pi pi2 'cd /home/pi && tar -xzf /tmp/backup.tar.gz'
```

## Troubleshooting

### Common Issues

#### Serial Communication Problems
```bash
# Check UART configuration
pi run --pi pi2 'cat /boot/firmware/config.txt | grep uart'

# Check serial service
pi run --pi pi2 'systemctl status serial-agent@ttyAMA0'

# Check device permissions
pi run --pi pi2 'ls -la /dev/ttyAMA0'
```

#### Network Configuration Issues
```bash
# Check BTBerryWifi status
pi run --pi pi2 'systemctl status btwifiset'

# Check Bluetooth status
pi run --pi pi2 'systemctl status bluetooth'

# Check NetworkManager
pi run --pi pi2 'systemctl status NetworkManager'
```

#### Application Deployment Issues
```bash
# Check deployment package
ls -la ~/inventory-deploy-build/

# Check Pi connectivity
pi status pi2

# Check disk space
pi run --pi pi2 'df -h /tmp'
```

### Debug Commands
```bash
# Check system logs
pi run --pi pi2 'journalctl -b -f'

# Check kernel messages
pi run --pi pi2 'dmesg | tail -20'

# Check network configuration
pi run --pi pi2 'cat /etc/network/interfaces'
pi run --pi pi2 'cat /etc/wpa_supplicant/wpa_supplicant.conf'
```

## Best Practices

### Development
- Use the interactive installer for component deployment
- Test components individually before full deployment
- Use version control for all configuration changes
- Document custom modifications and configurations

### Deployment
- Always check Pi status before deployment
- Use run-stream for long-running commands
- Verify deployment package exists before deployment
- Test services after deployment

### Maintenance
- Regular system updates and security patches
- Monitor system resources and logs
- Regular backups of application data
- Use monitoring tools for proactive maintenance

### Security
- Change default passwords
- Use SSH keys for authentication
- Keep system and packages updated
- Monitor access logs
- Use firewall rules

## Integration Examples

### Automated Deployment Script
```bash
#!/bin/bash
PI_NAME="pi2"

# Check Pi status
if pi status $PI_NAME | grep -q "ONLINE"; then
    echo "Deploying to $PI_NAME..."
    
    # Deploy serial agent
    ./install  # Select option 1
    
    # Deploy network components
    ./install  # Select option 2
    
    # Reboot for changes to take effect
    ./install  # Select option 6
    
    # Wait for reboot
    sleep 60
    
    # Deploy application
    ./install  # Select option 3
    
    echo "Deployment complete!"
else
    echo "Pi $PI_NAME is offline"
    exit 1
fi
```

### Multi-Pi Deployment
```bash
#!/bin/bash
PIS=("pi1" "pi2" "pi3")

for pi in "${PIS[@]}"; do
    if pi status $pi | grep -q "ONLINE"; then
        echo "Deploying to $pi..."
        
        # Deploy components
        pi send --pi $pi ./deploy-package.tar.gz /tmp/
        pi run-stream --pi $pi "cd /tmp && tar -xzf deploy-package.tar.gz"
        
        echo "Deployment to $pi complete!"
    else
        echo "Skipping $pi (offline)"
    fi
done
```

### Health Check Script
```bash
#!/bin/bash
PI_NAME="pi2"

echo "Health check for $PI_NAME..."

# Check system status
echo "System load:"
pi run --pi $PI_NAME "uptime"

echo "Memory usage:"
pi run --pi $PI_NAME "free -h"

echo "Disk usage:"
pi run --pi $PI_NAME "df -h"

echo "Service status:"
pi run --pi $PI_NAME "systemctl status inventory-app btwifiset bluetooth"

echo "Network status:"
pi run --pi $PI_NAME "ip addr show"
```

This comprehensive guide covers all aspects of the inv2-dev project workflow. Use these patterns and examples to effectively develop, deploy, and maintain your inventory management system on Raspberry Pi devices.
