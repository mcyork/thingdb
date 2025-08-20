# Source Code Architecture - Single Source of Truth

## 🎯 **Overview**

This project now follows a **Single Source of Truth** architecture where all source code lives in one place: `/src/`. All deployment targets (Pi, Docker, NAS) copy from this single location, ensuring consistency and eliminating code duplication.

## 📁 **Directory Structure**

```
inv2-dev/
├── src/                           # 🎯 SINGLE SOURCE OF TRUTH
│   ├── config.py                  # Main configuration (includes IMAGE_STORAGE_METHOD)
│   ├── database.py                # Database logic with conditional image storage
│   ├── main.py                    # Flask application entry point
│   ├── models.py                  # Database models
│   ├── routes/                    # API routes
│   ├── services/                  # Business logic services
│   ├── templates/                 # HTML templates
│   ├── static/                    # Static assets
│   ├── utils/                     # Utility functions
│   └── uploads/                   # Upload handling
│
├── pi-deployment/                 # 🥧 Pi deployment package (NO source code)
│   ├── install/                   # Installation scripts
│   ├── scripts/                   # Deployment scripts
│   ├── config/                    # Pi-specific configuration
│   │   ├── environment-pi.env     # Environment variables
│   │   ├── pi-config.py           # Pi-specific logic
│   │   ├── nginx-pi.conf          # Nginx configuration
│   │   └── inventory.service      # Systemd service
│   └── data/                      # Data files (database, images)
│
├── pi-image-builder/              # 🏗️ Pi image building tools
│   └── CustomPiOS/                # Custom Pi OS configuration
│       └── src/inventoryos/
│           └── modules/inventory/
│               └── filesystem/home/pi/pi-deployment/  # NO source code
│
├── docker/                        # 🐳 Docker configuration
├── scripts/                       # 🛠️ Build and deployment scripts
└── requirements/                  # 📦 Python dependencies
```

## 🔄 **How Deployments Work**

### **1. Pi Deployment**
```bash
# 1. Clean up any stale source code
./scripts/cleanup-duplicate-src.sh

# 2. Prepare deployment package (copies fresh source from /src/)
./pi-deployment/scripts/pi-prep.sh

# 3. Install on Pi
./pi-deployment/install/install-pi.sh
```

**What happens:**
- `pi-prep.sh` copies **fresh source code** from `/src/` to `/pi-deployment/`
- All Python files, routes, services, templates are copied from the single source
- Pi-specific configuration (environment variables, nginx config) is preserved
- **No source code is maintained in multiple places**

### **2. Docker Deployment**
```bash
# Build production images
./scripts/build-prod.sh

# Start production environment
./scripts/start-prod.sh
```

**What happens:**
- Docker builds use `/src/` as the source
- Environment variables control behavior (IMAGE_STORAGE_METHOD=database)
- **Same source code, different configuration**

### **3. NAS Deployment**
```bash
# Package for NAS
./scripts/package-for-nas.sh
```

**What happens:**
- Copies `/src/` to deployment package
- Includes Docker images and configuration
- **Same source code, different deployment method**

## ⚙️ **Configuration Management**

### **Environment Variables**
```bash
# Development/Docker (database storage)
IMAGE_STORAGE_METHOD=database
IMAGE_DIR=/tmp/uploads

# Pi deployment (filesystem storage)
IMAGE_STORAGE_METHOD=filesystem
IMAGE_DIR=/var/lib/inventory/images
```

### **Conditional Logic**
The source code automatically adapts based on environment variables:

```python
# config.py
IMAGE_STORAGE_METHOD = os.environ.get('IMAGE_STORAGE_METHOD', 'database')
IMAGE_DIR = os.environ.get('IMAGE_DIR', '/tmp/uploads')

# database.py
image_column_type = 'TEXT' if IMAGE_STORAGE_METHOD == 'filesystem' else 'BYTEA'

# image_routes.py
if IMAGE_STORAGE_METHOD == 'filesystem':
    # Serve from filesystem
    return send_from_directory(IMAGE_DIR, filename)
else:
    # Serve from database
    return send_file(io.BytesIO(image_data))
```

## 🧹 **Maintenance**

### **Adding New Features**
1. **Only modify files in `/src/`**
2. **Never modify files in deployment directories**
3. **Run deployment scripts to propagate changes**

### **Updating Deployments**
```bash
# Clean up stale code
./scripts/cleanup-duplicate-src.sh

# Re-run deployment preparation
./pi-deployment/scripts/pi-prep.sh
```

### **Verifying Consistency**
```bash
# Check for any duplicate source files
find . -name "*.py" -path "*/pi-deployment/*" -not -path "*/install/*" -not -path "*/scripts/*"
find . -name "*.py" -path "*/pi-image-builder/*" -not -path "*/install/*" -not -path "*/scripts/*"
```

## ✅ **Benefits**

1. **Single Source of Truth**: All code changes happen in one place
2. **Consistency**: All deployments use identical source code
3. **Maintainability**: No more keeping multiple copies in sync
4. **Reliability**: Deployments always use the latest code
5. **Flexibility**: Same code adapts to different environments via configuration

## 🚨 **Important Rules**

1. **NEVER** edit files in `/pi-deployment/` (except deployment scripts)
2. **NEVER** edit files in `/pi-image-builder/.../pi-deployment/` (except deployment scripts)
3. **ALWAYS** edit files in `/src/`
4. **ALWAYS** run deployment scripts to propagate changes
5. **ALWAYS** run cleanup script if you suspect code duplication

## 🔍 **Troubleshooting**

### **"Code not working on Pi"**
```bash
# 1. Check if source code is stale
ls -la pi-deployment/config.py

# 2. Clean up and re-copy
./scripts/cleanup-duplicate-src.sh
./pi-deployment/scripts/pi-prep.sh

# 3. Verify fresh code was copied
grep "IMAGE_STORAGE_METHOD" pi-deployment/config.py
```

### **"Environment variables not working"**
```bash
# 1. Check Pi environment file
cat pi-deployment/config/environment-pi.env

# 2. Verify systemd service loads it
grep "EnvironmentFile" pi-deployment/config/inventory.service

# 3. Check if service is using the right file
systemctl cat inventory-app
```

## 🎉 **Summary**

This architecture ensures that:
- **`/src/` is the ONLY place to modify source code**
- **All deployments automatically use the latest code**
- **Configuration differences are handled via environment variables**
- **No more maintaining code in multiple places**
- **Deployments are always consistent and up-to-date**
