# Home Inventory System - Raspberry Pi Deployment

Turn your Raspberry Pi into a dedicated home inventory management appliance!

## 🥧 What You Get

- **Complete inventory system** running natively on Raspberry Pi
- **Pre-populated database** with sample items and images
- **Automatic startup** - boots ready to use
- **Network discovery** - access via `https://inventory.local`
- **Optimized performance** - images served directly by nginx
- **Self-signed SSL** - secure HTTPS out of the box

## 📋 Requirements

- **Raspberry Pi 4 or 5** with 4GB+ RAM recommended
- **Fresh Raspberry Pi OS** installation (Lite or Desktop)
- **Internet connection** for package downloads during setup
- **SD card** with at least 8GB free space

## 🚀 Quick Start

### 1. Prepare the deployment package (on your development machine)

```bash
cd pi-deployment/scripts
./pi-prep.sh
```

This will:
- Export your current database
- Extract all images from database to files
- Create the deployment package

### 2. Copy to your Raspberry Pi

```bash
# Copy the entire pi-deployment folder to your Pi
scp -r pi-deployment/ pi@raspberrypi.local:~/
```

### 3. Install on the Pi

```bash
# SSH to your Pi
ssh pi@raspberrypi.local

# For a fresh installation
sudo ~/pi-deployment/install/install-pi.sh

# For a clean reinstall (removes previous installation)
sudo ~/pi-deployment/install/cleanup-pi.sh
sudo ~/pi-deployment/install/install-pi.sh
```

### 4. Access your inventory system

- **Primary URL**: https://raspberrypi.local
- **IP Address**: https://[your-pi-ip-address]
- **Status Page**: http://raspberrypi.local:8080

## 🔧 What Gets Installed

### System Components
- **PostgreSQL** - Database server with your data
- **Python 3 + Flask** - Web application
- **Nginx** - Web server and SSL termination
- **Gunicorn** - WSGI server for Flask
- **systemd services** - Auto-start on boot

### Directory Structure
```
/var/lib/inventory/
├── app/                    # Flask application
│   ├── src/               # Source code
│   └── venv/              # Python virtual environment
├── images/                # Image files (served by nginx)
├── ssl/                   # SSL certificates
├── config/                # Configuration files
├── logs/                  # Application logs
└── backups/               # Database backups (future)
```

## ⚙️ Configuration

### Environment Variables
Located in `/var/lib/inventory/config/environment.env`:

- `DEPLOYMENT_TYPE=raspberry_pi`
- `SERVE_IMAGES_FROM_FILES=true`
- `IMAGE_FILE_PATH=/var/lib/inventory/images`
- Database connection settings
- SSL certificate paths

### Services
- **inventory-app.service** - Flask application
- **nginx.service** - Web server
- **postgresql.service** - Database

Check status: `sudo systemctl status inventory-app`

## 🔍 Troubleshooting

### Quick Status Check
```bash
# Run comprehensive status check
sudo ~/pi-deployment/install/check-status.sh
```

### Check Services Manually
```bash
sudo systemctl status inventory-app
sudo systemctl status nginx
sudo systemctl status postgresql
```

### View Logs
```bash
# Application logs
sudo journalctl -u inventory-app -f

# Nginx logs
sudo tail -f /var/log/nginx/error.log

# Application file logs
sudo tail -f /var/lib/inventory/logs/error.log
```

### Restart Services
```bash
sudo systemctl restart inventory-app
sudo systemctl restart nginx
```

### Access Database
```bash
sudo -u inventory psql -d inventory_db
```

## 🌐 Networking

### Network Discovery
- **mDNS enabled** - accessible via `inventory.local`
- **Avahi daemon** provides network discovery
- **HTTPS redirect** - HTTP automatically redirects to HTTPS

### Firewall (if enabled)
```bash
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 22/tcp  # SSH
```

## 🔒 Security

- **Self-signed SSL certificate** generated automatically
- **HTTPS only** - HTTP redirects to HTTPS
- **Rate limiting** configured in nginx
- **Secure systemd settings** for the application service

## 📈 Performance Optimizations

### Raspberry Pi Specific
- **PostgreSQL tuned** for Pi hardware
- **Nginx optimized** for ARM processor
- **Image serving** - direct file serving instead of database
- **Memory limits** configured for 4GB RAM
- **Worker processes** optimized for Pi CPU

### Image Handling
- **Original images** → `/var/lib/inventory/images/image_N.jpg`
- **Thumbnails** → `/var/lib/inventory/images/thumbnail_N.jpg`
- **Previews** → `/var/lib/inventory/images/original_N.jpg`
- **Nginx serving** - bypasses Flask for better performance

## 🔄 Updates (Future)

The system is designed to support updates, but this feature is not yet implemented. Future updates will:
- Download new versions from central server
- Verify integrity checksums
- Apply updates with rollback capability
- Preserve user data and configurations

## 📝 Development Notes

This Pi deployment maintains compatibility with the main development environment:
- Same database schema
- Same API endpoints  
- Same web interface
- Conditional code paths for image serving

### Included Fixes
The installation scripts automatically handle:
- **Database ownership** - Tables and sequences owned by inventory user
- **Image storage** - Files saved to filesystem, not database
- **Rate limiting** - Nginx zones configured properly
- **Dependencies** - All Python packages including psutil
- **Permissions** - Proper file and directory ownership
- **Environment detection** - Pi-specific settings applied

You can continue development on your main machine and deploy updates to the Pi as needed.

## 🛠️ Customization

Since this is open source and runs natively on the Pi, you can:
- Modify the Flask application code
- Customize nginx configuration
- Add new systemd services
- Integrate with other Pi hardware (GPIO, cameras, etc.)
- Add custom backup scripts

All source code is accessible in `/var/lib/inventory/app/src/`