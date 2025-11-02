# Docker Containerization Strategy

## Overview

This document outlines the strategy for containerizing the Inventory Management System, currently deployed on Raspberry Pi, into Docker containers. The goal is to create a portable, scalable deployment that maintains all current functionality while leveraging Docker's benefits.

## Current System Analysis

### Architecture Components

Based on the deployment scripts analysis, the current system consists of:

1. **Flask Application** (`inventory-app`)
   - Python 3 with virtual environment
   - Gunicorn WSGI server (2 workers, port 8000)
   - ML models (sentence-transformers, PyTorch CPU)
   - Image processing (Pillow)

2. **PostgreSQL Database**
   - Local instance with `inventory_db`
   - User: `inventory` / Password: `inventory_pi_2024`
   - Vector extensions for semantic search

3. **Nginx Reverse Proxy**
   - SSL termination (self-signed certificates)
   - HTTP to HTTPS redirect
   - Static file serving (`/images/`)
   - Proxy to Flask app (port 8000)

4. **Cloudflare Tunnel** (`cloudflared`)
   - Remote access via Cloudflare edge
   - DNS management via Worker
   - Access policies

5. **File System Storage**
   - Images: `/var/lib/inventory/images/`
   - ML Cache: `/var/lib/inventory/ml_cache/`
   - SSL Certs: `/var/lib/inventory/ssl/`
   - Config: `/var/lib/inventory/config/`

## Docker Strategy Options

### Option 1: Multi-Container Approach (Recommended)

**Services:**
- `inventory-app`: Flask application
- `postgres`: Database
- `nginx`: Reverse proxy
- `cloudflared`: Tunnel (optional)

**Benefits:**
- Service isolation
- Independent scaling
- Standard Docker patterns
- Easy debugging

### Option 2: Single Container Approach

**Services:**
- `inventory`: All services in one container

**Benefits:**
- Simpler deployment
- Matches current Pi architecture
- Single container to manage

**Drawbacks:**
- Violates container best practices
- Harder to scale individual services
- Complex health checks

## Recommended Implementation: Multi-Container

### Container Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   nginx         │    │  inventory-app   │    │   postgres      │
│   (port 80/443) │───▶│   (port 8000)   │───▶│   (port 5432)   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   SSL Certs     │    │   ML Cache      │    │   Database       │
│   (volume)      │    │   (volume)      │    │   (volume)       │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

### Volume Strategy

#### Persistent Volumes
1. **Database Volume**
   - PostgreSQL data directory
   - Persistent across container restarts

2. **Images Volume**
   - User-uploaded images
   - Shared between app and nginx

3. **ML Cache Volume**
   - Sentence-transformers models
   - PyTorch cache
   - Shared between app instances

4. **SSL Certificates Volume**
   - Self-signed certificates
   - Shared between app and nginx

5. **Configuration Volume**
   - Environment variables
   - Application configs

#### Bind Mounts (Development)
- Source code for live development
- Configuration files for easy editing

### Network Strategy

#### Docker Network
- **Name**: `inventory-network`
- **Type**: Bridge network
- **Services**: All containers on same network
- **Ports**: Only nginx exposed to host

#### Port Mapping
- **Host 80/443** → **nginx 80/443**
- **Internal**: app:8000, postgres:5432
- **No external access** to database or app

### Environment Configuration

#### Environment Variables
```bash
# Database
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_USER=inventory
POSTGRES_PASSWORD=inventory_pi_2024
POSTGRES_DB=inventory_db

# Application
FLASK_ENV=production
SECRET_KEY=inventory_docker_secret_key_change_in_production
RELEASE_CANDIDATE=RC8

# Storage
IMAGE_STORAGE_METHOD=filesystem
IMAGE_DIR=/var/lib/inventory/images

# ML Cache
TRANSFORMERS_CACHE=/var/lib/inventory/ml_cache
HF_HOME=/var/lib/inventory/ml_cache

# Cloudflare (optional)
CF_WORKER_URL=https://register.nestdb.io
CF_DEVICE_CERT_PATH=/etc/inventory/device.crt
```

## Implementation Plan

### Phase 1: Core Application Container

#### Dockerfile for `inventory-app`
```dockerfile
FROM python:3.11-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    libpq-dev \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Create application user
RUN useradd -r -s /bin/false inventory

# Set working directory
WORKDIR /var/lib/inventory/app

# Copy requirements
COPY requirements/ requirements/

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements/base-requirements.txt
RUN pip install --no-cache-dir -r requirements/ml-requirements.txt

# Copy application code
COPY src/ .

# Create necessary directories
RUN mkdir -p /var/lib/inventory/images \
    /var/lib/inventory/ml_cache \
    /var/lib/inventory/ssl \
    /var/lib/inventory/config

# Set permissions
RUN chown -R inventory:inventory /var/lib/inventory

# Switch to inventory user
USER inventory

# Expose port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# Start command
CMD ["gunicorn", "--preload", "--workers", "2", "--bind", "0.0.0.0:8000", "main:app"]
```

### Phase 2: Database Container

#### PostgreSQL Configuration
```yaml
# docker-compose.yml excerpt
postgres:
  image: postgres:15-alpine
  environment:
    POSTGRES_DB: inventory_db
    POSTGRES_USER: inventory
    POSTGRES_PASSWORD: inventory_pi_2024
  volumes:
    - postgres_data:/var/lib/postgresql/data
    - ./docker/postgres/init.sql:/docker-entrypoint-initdb.d/init.sql
  networks:
    - inventory-network
```

### Phase 3: Nginx Container

#### Nginx Configuration
```dockerfile
FROM nginx:alpine

# Copy nginx configuration
COPY docker/nginx/nginx.conf /etc/nginx/nginx.conf
COPY docker/nginx/default.conf /etc/nginx/conf.d/default.conf

# Copy SSL certificates (if available)
COPY docker/ssl/ /etc/nginx/ssl/

# Expose ports
EXPOSE 80 443

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost/health || exit 1
```

### Phase 4: Docker Compose Integration

#### Complete docker-compose.yml
```yaml
version: '3.8'

services:
  postgres:
    image: postgres:15-alpine
    environment:
      POSTGRES_DB: inventory_db
      POSTGRES_USER: inventory
      POSTGRES_PASSWORD: inventory_pi_2024
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./docker/postgres/init.sql:/docker-entrypoint-initdb.d/init.sql
    networks:
      - inventory-network
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U inventory -d inventory_db"]
      interval: 30s
      timeout: 10s
      retries: 3

  inventory-app:
    build: .
    environment:
      POSTGRES_HOST: postgres
      POSTGRES_PORT: 5432
      POSTGRES_USER: inventory
      POSTGRES_PASSWORD: inventory_pi_2024
      POSTGRES_DB: inventory_db
      FLASK_ENV: production
      SECRET_KEY: inventory_docker_secret_key_change_in_production
      RELEASE_CANDIDATE: RC8
      IMAGE_STORAGE_METHOD: filesystem
      IMAGE_DIR: /var/lib/inventory/images
      TRANSFORMERS_CACHE: /var/lib/inventory/ml_cache
      HF_HOME: /var/lib/inventory/ml_cache
    volumes:
      - images_data:/var/lib/inventory/images
      - ml_cache_data:/var/lib/inventory/ml_cache
      - ssl_data:/var/lib/inventory/ssl
      - config_data:/var/lib/inventory/config
    depends_on:
      postgres:
        condition: service_healthy
    networks:
      - inventory-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  nginx:
    build: ./docker/nginx
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - images_data:/var/www/images
      - ssl_data:/etc/nginx/ssl
    depends_on:
      inventory-app:
        condition: service_healthy
    networks:
      - inventory-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  cloudflared:
    image: cloudflare/cloudflared:latest
    command: tunnel --config /etc/cloudflared/config.yml run
    volumes:
      - ./docker/cloudflared/config.yml:/etc/cloudflared/config.yml:ro
    depends_on:
      - nginx
    networks:
      - inventory-network
    profiles:
      - tunnel

volumes:
  postgres_data:
  images_data:
  ml_cache_data:
  ssl_data:
  config_data:

networks:
  inventory-network:
    driver: bridge
```

## Migration Strategy

### Data Migration from Pi

1. **Database Migration**
   ```bash
   # Export from Pi
   pg_dump -h pi_ip -U inventory inventory_db > inventory_backup.sql
   
   # Import to Docker
   docker-compose exec postgres psql -U inventory -d inventory_db < inventory_backup.sql
   ```

2. **Images Migration**
   ```bash
   # Copy images from Pi
   scp -r pi:/var/lib/inventory/images/* ./docker/volumes/images/
   ```

3. **ML Cache Migration**
   ```bash
   # Copy ML cache from Pi
   scp -r pi:/var/lib/inventory/ml_cache/* ./docker/volumes/ml_cache/
   ```

### Configuration Migration

1. **Environment Variables**
   - Convert Pi environment.env to Docker environment variables
   - Update hostnames (localhost → postgres)

2. **SSL Certificates**
   - Copy self-signed certificates from Pi
   - Or generate new ones for Docker deployment

## Development vs Production

### Development Setup
- Bind mounts for source code
- Hot reloading enabled
- Debug mode enabled
- Local database

### Production Setup
- Multi-stage builds
- Optimized images
- Health checks
- Resource limits
- Security hardening

## Cloudflare Tunnel Integration

### Docker-Specific Considerations
- Tunnel configuration needs to point to nginx container
- DNS management via Worker remains the same
- Access policies work identically

### Configuration
```yaml
# docker/cloudflared/config.yml
tunnel: <tunnel-id>
credentials-file: /etc/cloudflared/credentials.json
ingress:
  - hostname: pi-<serial>.nestdb.io
    service: https://nginx:443
```

## Benefits of Docker Approach

### Operational Benefits
- **Consistency**: Same environment across dev/staging/prod
- **Portability**: Run anywhere Docker runs
- **Scalability**: Easy horizontal scaling
- **Isolation**: Service boundaries clearly defined

### Development Benefits
- **Local Development**: Run full stack locally
- **Testing**: Isolated test environments
- **CI/CD**: Standardized build/deploy pipeline
- **Debugging**: Easy service inspection

### Maintenance Benefits
- **Updates**: Rolling updates with zero downtime
- **Backups**: Volume-based backup strategies
- **Monitoring**: Standard Docker monitoring tools
- **Logging**: Centralized logging with Docker

## Challenges and Solutions

### Challenge 1: ML Model Size
**Problem**: Large ML models (PyTorch, sentence-transformers)
**Solution**: Multi-stage builds, model caching, volume persistence

### Challenge 2: Database Initialization
**Problem**: Database schema and data setup
**Solution**: Init scripts, migration tools, data volumes

### Challenge 3: SSL Certificate Management
**Problem**: Self-signed certificates in containers
**Solution**: Volume mounts, certificate generation scripts

### Challenge 4: Cloudflare Tunnel Integration
**Problem**: Tunnel configuration for containerized services
**Solution**: Service discovery, network configuration

## Next Steps

1. **Create Dockerfile** for inventory-app
2. **Set up docker-compose.yml** with all services
3. **Create nginx configuration** for Docker
4. **Set up volume management** for persistent data
5. **Test migration** from Pi to Docker
6. **Implement health checks** and monitoring
7. **Create deployment scripts** for Docker
8. **Document operational procedures**

## File Structure

```
docker/
├── DOCKER_STRATEGY.md          # This document
├── docker-compose.yml          # Main orchestration file
├── docker-compose.dev.yml      # Development overrides
├── docker-compose.prod.yml     # Production overrides
├── Dockerfile                  # Main application container
├── nginx/
│   ├── Dockerfile             # Nginx container
│   ├── nginx.conf             # Main nginx config
│   └── default.conf           # Site configuration
├── postgres/
│   └── init.sql               # Database initialization
├── cloudflared/
│   └── config.yml             # Tunnel configuration
├── ssl/
│   ├── cert.pem               # SSL certificate
│   └── key.pem                # SSL private key
└── volumes/
    ├── images/                # Image storage
    ├── ml_cache/              # ML model cache
    ├── postgres/              # Database data
    └── config/                # Configuration files
```

This strategy provides a comprehensive roadmap for containerizing the Inventory Management System while maintaining all current functionality and enabling future scalability.
