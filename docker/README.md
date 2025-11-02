# Inventory Management System - Docker Prototype

This directory contains a complete Docker prototype for the Inventory Management System, designed as a single container that runs all services (Flask app, PostgreSQL, Nginx) using supervisor.

## Architecture

### Single Container Approach
- **Flask Application**: Python 3.11 with Gunicorn
- **PostgreSQL**: Database server
- **Nginx**: Reverse proxy and SSL termination
- **Supervisor**: Process management for all services

### Services Managed by Supervisor
1. **PostgreSQL** (priority 100) - Database server
2. **Database Init** (priority 200) - One-time database setup
3. **Flask App** (priority 300) - Web application
4. **Nginx** (priority 400) - Web server

## Files

### Core Configuration
- `Dockerfile` - Main container definition
- `docker-compose.yml` - Docker Compose orchestration
- `supervisord.conf` - Process management configuration

### Service Configurations
- `nginx.conf` - Nginx web server configuration
- `postgresql.conf` - PostgreSQL database configuration
- `init-db.sh` - Database initialization script

### Build and Run Scripts
- `build.sh` - Build the Docker image
- `run.sh` - Run the container with volumes
- `README.md` - This documentation

## Quick Start

### 1. Build the Image
```bash
cd docker
./build.sh
```

### 2. Run with Docker Compose (Recommended)
```bash
cd docker
docker-compose up -d
```

### 3. Run with Script
```bash
cd docker
./run.sh
```

### 4. Access the Application
- **HTTP**: http://localhost (redirects to HTTPS)
- **HTTPS**: https://localhost

## Volume Management

### Persistent Volumes
- `postgres_data` - Database files
- `images_data` - User uploaded images
- `ml_cache_data` - ML model cache
- `ssl_data` - SSL certificates
- `config_data` - Configuration files

### Volume Locations
```bash
# View volumes
docker volume ls | grep inventory

# Inspect volume
docker volume inspect inventory_postgres_data

# Backup volume
docker run --rm -v inventory_postgres_data:/data -v $(pwd):/backup alpine tar czf /backup/postgres_backup.tar.gz -C /data .
```

## Environment Variables

### Database Configuration
```bash
POSTGRES_HOST=localhost
POSTGRES_PORT=5432
POSTGRES_USER=inventory
POSTGRES_PASSWORD=inventory_pi_2024
POSTGRES_DB=inventory_db
```

### Application Configuration
```bash
FLASK_ENV=production
SECRET_KEY=inventory_docker_secret_key_change_in_production
RELEASE_CANDIDATE=RC8
IMAGE_STORAGE_METHOD=filesystem
IMAGE_DIR=/var/lib/inventory/images
```

### ML Cache Configuration
```bash
TRANSFORMERS_CACHE=/var/lib/inventory/ml_cache
HF_HOME=/var/lib/inventory/ml_cache
```

## Development

### Local Development with Bind Mounts
```yaml
# docker-compose.dev.yml
version: '3.8'
services:
  inventory:
    build: .
    volumes:
      # Bind mount source code for development
      - ../src:/var/lib/inventory/app:ro
      # Keep persistent volumes
      - postgres_data:/var/lib/postgresql/data
      - images_data:/var/lib/inventory/images
      - ml_cache_data:/var/lib/inventory/ml_cache
    environment:
      FLASK_ENV: development
```

### Hot Reloading
```bash
# Run with development overrides
docker-compose -f docker-compose.yml -f docker-compose.dev.yml up
```

## Monitoring and Debugging

### View Logs
```bash
# All services
docker logs inventory-app

# Follow logs
docker logs -f inventory-app

# Supervisor logs
docker exec inventory-app tail -f /var/log/supervisor/supervisord.log
```

### Service Status
```bash
# Check supervisor status
docker exec inventory-app supervisorctl status

# Check individual services
docker exec inventory-app supervisorctl status postgresql
docker exec inventory-app supervisorctl status inventory-app
docker exec inventory-app supervisorctl status nginx
```

### Health Checks
```bash
# Container health
docker inspect inventory-app | grep -A 10 Health

# Application health
curl -f http://localhost/health
curl -f https://localhost/health
```

### Database Access
```bash
# Connect to database
docker exec -it inventory-app psql -U inventory -d inventory_db

# Run SQL commands
docker exec inventory-app psql -U inventory -d inventory_db -c "SELECT version();"
```

## Migration from Pi

### 1. Export Database from Pi
```bash
# On Pi
pg_dump -h localhost -U inventory inventory_db > inventory_backup.sql
```

### 2. Import to Docker
```bash
# Copy backup to Docker container
docker cp inventory_backup.sql inventory-app:/tmp/

# Import database
docker exec inventory-app psql -U inventory -d inventory_db < /tmp/inventory_backup.sql
```

### 3. Copy Images
```bash
# Copy images from Pi
scp -r pi:/var/lib/inventory/images/* ./docker/volumes/images/

# Or use rsync
rsync -av pi:/var/lib/inventory/images/ ./docker/volumes/images/
```

### 4. Copy ML Cache
```bash
# Copy ML cache from Pi
scp -r pi:/var/lib/inventory/ml_cache/* ./docker/volumes/ml_cache/
```

## Troubleshooting

### Common Issues

#### Container Won't Start
```bash
# Check logs
docker logs inventory-app

# Check supervisor status
docker exec inventory-app supervisorctl status
```

#### Database Connection Issues
```bash
# Check PostgreSQL status
docker exec inventory-app supervisorctl status postgresql

# Check database logs
docker exec inventory-app tail -f /var/log/supervisor/postgresql.out.log
```

#### Nginx Issues
```bash
# Check Nginx status
docker exec inventory-app supervisorctl status nginx

# Test Nginx configuration
docker exec inventory-app nginx -t
```

#### Application Issues
```bash
# Check Flask app status
docker exec inventory-app supervisorctl status inventory-app

# Check application logs
docker exec inventory-app tail -f /var/log/supervisor/inventory-app.out.log
```

### Performance Tuning

#### Memory Limits
```yaml
# docker-compose.yml
services:
  inventory:
    deploy:
      resources:
        limits:
          memory: 2G
        reservations:
          memory: 1G
```

#### CPU Limits
```yaml
# docker-compose.yml
services:
  inventory:
    deploy:
      resources:
        limits:
          cpus: '1.0'
        reservations:
          cpus: '0.5'
```

## Security Considerations

### SSL Certificates
- Self-signed certificates are generated automatically
- For production, replace with proper certificates
- Mount certificate volume to persist certificates

### Database Security
- Change default passwords in production
- Use environment variables for sensitive data
- Consider using Docker secrets for production

### Network Security
- Only ports 80 and 443 are exposed
- Internal services communicate via localhost
- No external database access

## Production Deployment

### Environment Variables
```bash
# Production environment file
POSTGRES_PASSWORD=your_secure_password
SECRET_KEY=your_secure_secret_key
FLASK_ENV=production
```

### SSL Certificates
```bash
# Generate production certificates
openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -days 365 -nodes

# Mount to container
docker run -v $(pwd)/ssl:/var/lib/inventory/ssl inventory-app
```

### Backup Strategy
```bash
# Database backup
docker exec inventory-app pg_dump -U inventory inventory_db > backup.sql

# Volume backup
docker run --rm -v inventory_postgres_data:/data -v $(pwd):/backup alpine tar czf /backup/postgres_backup.tar.gz -C /data .
```

## Benefits of Single Container Approach

### Advantages
- ✅ **Simplicity**: One container to manage
- ✅ **Resource Efficiency**: Shared OS and libraries
- ✅ **Easier Deployment**: Single unit to deploy
- ✅ **Matches Current Architecture**: Similar to Pi systemd approach
- ✅ **Faster Startup**: No inter-container dependencies

### Trade-offs
- ❌ **Scaling**: Can't scale services independently
- ❌ **Isolation**: Services share resources
- ❌ **Debugging**: All services mixed together

## Next Steps

1. **Test the prototype** with your current data
2. **Migrate from Pi** using the migration guide
3. **Customize configuration** for your environment
4. **Set up monitoring** and logging
5. **Implement backup strategy** for production
6. **Consider multi-container** if scaling becomes important

This prototype provides a solid foundation for containerizing your Inventory Management System while maintaining the simplicity of your current architecture.
