# 🐳 Docker Storage Testing Guide

This guide explains how to test both database and filesystem image storage configurations locally using Docker.

## 🎯 **Overview**

We've created two separate Docker configurations to test different image storage approaches:

1. **🗄️ Database Storage** - Images stored as BLOB data in PostgreSQL
2. **💾 Filesystem Storage** - Images stored on the filesystem with optimized sharing

## 🚀 **Quick Start**

### Start Both Configurations
```bash
./scripts/start-docker-storage-test.sh
```

### Start Only Database Storage
```bash
./scripts/start-docker-storage-test.sh database
```

### Start Only Filesystem Storage
```bash
./scripts/start-docker-storage-test.sh filesystem
```

### Check Status
```bash
./scripts/start-docker-storage-test.sh status
```

### Stop All
```bash
./scripts/start-docker-storage-test.sh stop
```

## 🌐 **Access URLs**

| Configuration | HTTP Port | HTTPS Port | Description |
|---------------|-----------|------------|-------------|
| **Database Storage** | http://localhost:8081 | https://localhost:8444 | Images stored in PostgreSQL |
| **Filesystem Storage** | http://localhost:8080 | https://localhost:8443 | Images stored on filesystem |

## 📁 **File Structure**

```
docker/
├── docker-compose-database.yml      # Database storage configuration
├── docker-compose-filesystem.yml    # Filesystem storage configuration
└── Dockerfile.flask-prod           # Production Flask image

config/app-config/
├── app-database.env                # Database storage environment
└── app-filesystem.env              # Filesystem storage environment

scripts/
└── start-docker-storage-test.sh    # Test orchestration script
```

## 🔧 **Configuration Details**

### Database Storage Configuration
- **Ports**: 8081 (HTTP), 8444 (HTTPS)
- **Database**: `inventory_database` with user `inventory`
- **Image Storage**: BLOB data in PostgreSQL
- **Volume**: `flask-uploads:/app/uploads`

### Filesystem Storage Configuration
- **Ports**: 8080 (HTTP), 8443 (HTTPS)
- **Database**: `inventory_filesystem` with user `inventory`
- **Image Storage**: Files on local filesystem
- **Volume**: `flask-images:/var/lib/inventory/images` (bind-mounted to `/tmp/inventory-images`)

## 🧪 **Testing Workflow**

### 1. Start Both Configurations
```bash
./scripts/start-docker-storage-test.sh
```

### 2. Wait for Services to Start
```bash
./scripts/start-docker-storage-test.sh status
```

### 3. Test Database Storage
- Open http://localhost:8081
- Upload images and verify they're stored in the database
- Check database size and performance

### 4. Test Filesystem Storage
- Open http://localhost:8080
- Upload images and verify they're stored on the filesystem
- Check `/tmp/inventory-images` directory
- Compare performance with database storage

### 5. Performance Comparison
- **Database Storage**: Better for small images, ACID compliance, backup simplicity
- **Filesystem Storage**: Better for large images, faster access, easier sharing

## 🔍 **Troubleshooting**

### Check Docker Status
```bash
docker ps
docker logs <container-name>
```

### Check Container Logs
```bash
# Database storage logs
docker logs flask-database-app

# Filesystem storage logs
docker logs flask-filesystem-app
```

### Reset Everything
```bash
./scripts/start-docker-storage-test.sh stop
docker system prune -f
./scripts/start-docker-storage-test.sh
```

## 📊 **Expected Results**

### Database Storage
- Images stored as BLOB in PostgreSQL
- Database size increases with image uploads
- Slower image retrieval for large files
- Better for backup and consistency

### Filesystem Storage
- Images stored as files in `/tmp/inventory-images`
- Faster image access and serving
- Easier to share images between containers
- Better for large image collections

## 🎯 **Next Steps After Testing**

1. **Identify the best approach** for your use case
2. **Optimize the chosen configuration** based on test results
3. **Apply learnings to Pi deployment** with fresh OS
4. **Create production-ready configuration** for target environment

## 🔗 **Related Files**

- `src/config.py` - Main application configuration
- `src/main.py` - Flask app entry point with environment loading
- `src/database.py` - Database schema and image handling
- `src/routes/image_routes.py` - Image upload/download routes

## 💡 **Tips**

- **Start with database storage** to verify basic functionality
- **Test with various image sizes** to understand performance characteristics
- **Monitor disk usage** for filesystem storage
- **Check database growth** for database storage
- **Use different browsers** to test both configurations simultaneously
