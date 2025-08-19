# Raspberry Pi 5 Deployment Guide
## Flask Inventory Management System

This guide covers the complete deployment of the Flask Inventory Management System to a 64-bit Raspberry Pi 5 running Raspberry Pi OS (Bookworm).

## Prerequisites

- **Hardware**: Raspberry Pi 5 (4GB or 8GB RAM recommended)
- **OS**: Raspberry Pi OS 64-bit (Bookworm) - Desktop or Lite
- **Network**: Ethernet or WiFi connection
- **Storage**: 16GB+ SD card (32GB recommended for production)

## System Requirements

The deployment script automatically installs and configures:
- **Python 3.11+** with virtual environment
- **PostgreSQL 15** database server
- **Nginx** web server with SSL
- **PyTorch 2.8.0** (CPU version for ARM64)
- **Sentence-Transformers** for semantic search
- **Flask 2.3.3** application framework
- **Gunicorn** WSGI server

## Deployment Process

### 1. Build Deployment Package

On your development machine:
```bash
./deploy-prepare.sh
```

This creates `inventory-deploy.tar.gz` containing:
- Application source code
- Python requirements
- Database export
- Automated deployment script
- Configuration templates

### 2. Transfer to Raspberry Pi

```bash
rsync -avz inventory-deploy.tar.gz pi@[PI_IP]:/tmp/
```

### 3. Deploy on Raspberry Pi

```bash
cd /tmp
tar -xzf inventory-deploy.tar.gz
sudo ./deploy.sh
```

## What Gets Installed

### System Dependencies
- **PostgreSQL 15**: Database server with vector extensions
- **Nginx 1.22**: Reverse proxy with SSL termination
- **Python 3.11**: Development packages and pip
- **Git**: Source code management

### Python Environment
- **Virtual Environment**: `/var/lib/inventory/app/venv/`
- **Flask Application**: Production-ready WSGI setup
- **ML Libraries**: PyTorch, sentence-transformers, transformers
- **Database**: psycopg2-binary for PostgreSQL connectivity

### Application Structure
```
/var/lib/inventory/
├── app/                    # Flask application
│   ├── src/               # Source code
│   ├── venv/              # Python virtual environment
│   └── requirements/      # Python dependencies
├── config/                # Environment configuration
├── images/                # Stored images
├── ml_cache/              # ML model cache
└── ssl/                   # SSL certificates
```

## Configuration Details

### Environment Variables
```bash
DEPLOYMENT_TYPE=raspberry_pi
POSTGRES_HOST=localhost
POSTGRES_PORT=5432
POSTGRES_USER=inventory
POSTGRES_DB=inventory_db
TRANSFORMERS_CACHE=/var/lib/inventory/ml_cache
HF_HOME=/var/lib/inventory/ml_cache
```

### Database Setup
- **User**: `inventory` with full database privileges
- **Database**: `inventory_db` with vector and pg_trgm extensions
- **Ownership**: All tables and sequences owned by inventory user
- **Data**: Imported from provided database export

### Web Server Configuration
- **Nginx**: Reverse proxy on ports 80/443
- **SSL**: Self-signed certificates (replace with Let's Encrypt for production)
- **Gunicorn**: 2 workers binding to 127.0.0.1:8000
- **Static Files**: Images served directly by Nginx

### ML Model Configuration
- **Cache Directory**: `/var/lib/inventory/ml_cache/`
- **Model**: `all-MiniLM-L6-v2` (384-dimensional embeddings)
- **Automatic Download**: Model downloaded during deployment
- **Embedding Generation**: All items processed during deployment

## Service Management

### Systemd Services
```bash
# Check status
sudo systemctl status inventory-app
sudo systemctl status nginx
sudo systemctl status postgresql

# View logs
sudo journalctl -u inventory-app -f
sudo journalctl -u nginx -f
```

### Manual Control
```bash
# Restart services
sudo systemctl restart inventory-app
sudo systemctl reload nginx

# Stop services
sudo systemctl stop inventory-app
sudo systemctl stop nginx
```

## Access Points

### Web Interface
- **HTTPS**: https://[PI_IP_ADDRESS]
- **Local**: https://raspberrypi.local (if mDNS enabled)

### Database Access
```bash
# Connect as inventory user
sudo -u inventory psql -d inventory_db

# Connect as postgres
sudo -u postgres psql -d inventory_db
```

### File Locations
- **Application**: `/var/lib/inventory/app/`
- **Configuration**: `/var/lib/inventory/config/`
- **Logs**: `/var/log/` (systemd journal)
- **ML Cache**: `/var/lib/inventory/ml_cache/`

## Security Considerations

### User Permissions
- **inventory user**: Runs Flask application, owns application files
- **postgres user**: Database administration only
- **root**: System configuration and service management

### Network Security
- **Local Binding**: Flask app binds to 127.0.0.1 only
- **Nginx Proxy**: External access through Nginx with SSL
- **Firewall**: Configure ufw to allow SSH and HTTPS only

### SSL Certificates
- **Self-signed**: Generated during deployment
- **Production**: Replace with Let's Encrypt certificates
- **Auto-renewal**: Configure certbot for production use

## Performance Optimization

### Database Tuning
- **PostgreSQL**: Optimized for Raspberry Pi memory constraints
- **Vector Extensions**: Efficient semantic search indexing
- **Connection Pooling**: Managed by Flask application

### ML Model Optimization
- **CPU-only PyTorch**: Optimized for ARM64 architecture
- **Model Caching**: Persistent storage in dedicated directory
- **Embedding Generation**: Batch processing during deployment

### Web Server Tuning
- **Nginx**: Static file serving and SSL termination
- **Gunicorn**: 2 workers for Raspberry Pi 5 performance
- **Image Optimization**: Thumbnail generation and caching

## Troubleshooting

### Common Issues
1. **Port Conflicts**: Ensure ports 80, 443, and 8000 are available
2. **Memory Issues**: Monitor with `htop` during ML operations
3. **Disk Space**: Check with `df -h` before deployment
4. **Network**: Verify connectivity with `ping` and `curl`

### Log Analysis
```bash
# Application logs
sudo journalctl -u inventory-app --no-pager -n 50

# Nginx logs
sudo journalctl -u nginx --no-pager -n 50

# System logs
sudo journalctl --no-pager -n 100
```

### Health Checks
```bash
# Service status
sudo systemctl is-active inventory-app nginx postgresql

# Database connectivity
sudo -u inventory psql -d inventory_db -c "SELECT 1;"

# Web interface
curl -k https://localhost/
```

## Production Considerations

### Monitoring
- **System Resources**: CPU, memory, disk usage
- **Application Metrics**: Response times, error rates
- **Database Performance**: Query execution times, connection counts

### Backup Strategy
- **Database**: Regular PostgreSQL dumps
- **Application**: Source code version control
- **Configuration**: Environment-specific configs
- **Images**: Separate storage with redundancy

### Scaling
- **Load Balancing**: Multiple Pi instances behind Nginx
- **Database**: Separate PostgreSQL server for multiple instances
- **Caching**: Redis for session and query caching

## Maintenance

### Updates
- **System**: Regular `apt update && apt upgrade`
- **Application**: Pull latest code and redeploy
- **Dependencies**: Update Python packages as needed
- **Security**: Monitor for security updates

### Cleanup
- **Log Rotation**: Configure logrotate for system logs
- **Temp Files**: Regular cleanup of temporary directories
- **ML Cache**: Monitor cache directory size
- **Database**: Regular vacuum and analyze operations

---

**Last Updated**: August 2025  
**Tested On**: Raspberry Pi 5 (8GB) with Raspberry Pi OS 64-bit Bookworm  
**Deployment Time**: ~15-20 minutes for full system setup
