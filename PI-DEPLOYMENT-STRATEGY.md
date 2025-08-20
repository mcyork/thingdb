# Raspberry Pi Deployment Strategy

## 🎯 **Overarching Goal**

Build a **reproducible SD card image** that users can burn to an SD card, plug into their Pi, and have a fully functional personal inventory system running immediately.

## 🏗️ **Project Milestones**

### **Milestone 1: Pi Deployment with Filesystem Images** ⭐ **CURRENT FOCUS**
- Get the inventory system running on Pi with all features working
- Use filesystem-based image storage (not database BLOB)
- Establish iterative development/deployment process
- Achieve stable, working Pi build

### **Milestone 2: First Boot Configuration** 🔧
- Implement first-boot setup wizard
- Wipe development credentials
- Configure Pi as WiFi access point
- User-friendly initial configuration experience

### **Milestone 3: Internet-Enabled Deployment** 🌐
- Web app for Pi registration
- Automatic Let's Encrypt certificate generation
- Real domain names for users
- Cloud-based Pi management

---

## 🚀 **Current Status: Milestone 1**

### **✅ What We've Accomplished**

1. **Environment Variable System**
   - Fixed `src/main.py` to load environment variables before imports
   - Updated `src/config.py` to prioritize external PostgreSQL settings
   - Both Docker configurations now work with correct database connections

2. **Docker Testing Environment**
   - Created isolated dual-storage testing environment
   - Database storage (PostgreSQL BLOB) working on port 8444
   - Filesystem storage (local files) working on port 8443
   - No more container conflicts or volume issues

3. **Configuration Management**
   - `IMAGE_STORAGE_METHOD=filesystem` for Pi deployment
   - `IMAGE_DIR=/var/lib/inventory/images` for Pi filesystem storage
   - Environment variables properly loaded from `/var/lib/inventory/config/.env`

### **🔍 What We've Learned**

1. **Environment Variable Loading Order**
   - Must load environment variables BEFORE importing modules
   - `config.py` evaluates `DB_CONFIG` at import time
   - Pi deployment needs `/var/lib/inventory/config/.env` file

2. **Docker vs Pi Differences**
   - Docker: Uses container names for database connections
   - Pi: Uses `localhost` or external PostgreSQL
   - Both need same environment variable structure

3. **Storage Method Switching**
   - Code conditionally handles `database` vs `filesystem` storage
   - Filesystem storage requires directory creation and permissions
   - Nginx must be configured to serve images from filesystem

---

## 🎯 **Next Steps for Pi Deployment**

### **Phase 1: Prepare Pi Environment**
1. **Wipe Pi2 completely** (already done)
2. **Deploy latest code** with environment variable fixes
3. **Verify filesystem image storage** works on Pi
4. **Test all features** (homepage, re-indexing, ML, image upload/display)

### **Phase 2: Iterative Development**
1. **Establish rsync workflow** for code updates
2. **Test code changes** locally in Docker first
3. **Deploy to Pi** and verify functionality
4. **Iterate rapidly** without breaking Docker environment

### **Phase 3: Pi Optimization**
1. **Performance tuning** for Pi hardware
2. **Service management** (systemd, auto-start)
3. **Logging and monitoring**
4. **Backup and recovery** procedures

---

## 🔧 **Technical Requirements for Pi**

### **Environment Variables**
```bash
# Pi deployment environment
IMAGE_STORAGE_METHOD=filesystem
IMAGE_DIR=/var/lib/inventory/images
POSTGRES_USER=inventory
POSTGRES_PASSWORD=inventory_pi_2024
POSTGRES_DB=inventory_db
FLASK_ENV=production
SECRET_KEY=<generated-secret>
```

### **Directory Structure**
```
/var/lib/inventory/
├── app/                    # Application code
├── config/
│   └── .env              # Environment variables
├── images/                # Stored images
├── logs/                  # Application logs
└── data/                  # PostgreSQL data
```

### **System Services**
- **PostgreSQL**: Database server
- **Nginx**: Web server and image serving
- **Gunicorn**: Flask application server
- **Systemd**: Service management

---

## 📋 **Deployment Checklist**

### **Pre-Deployment**
- [ ] Code tested in Docker dual-storage environment
- [ ] Environment variables documented and tested
- [ ] Pi hardware ready (wiped, fresh OS)
- [ ] Network access to Pi established

### **Deployment**
- [ ] Deploy latest source code to Pi
- [ ] Install system dependencies (PostgreSQL, Nginx, Python)
- [ ] Configure environment variables
- [ ] Set up database and user accounts
- [ ] Configure Nginx for image serving
- [ ] Start all services

### **Verification**
- [ ] Homepage loads correctly
- [ ] Database connection established
- [ ] Image upload works
- [ ] Images display on homepage
- [ ] Re-indexing functionality works
- [ ] ML features working
- [ ] All services auto-start on boot

---

## 🚨 **Known Issues & Solutions**

### **Environment Variable Loading**
- **Problem**: Flask app not loading environment variables on Pi
- **Solution**: Fixed `src/main.py` to load `.env` before imports
- **Status**: ✅ Resolved

### **Database Connection**
- **Problem**: App trying to connect to wrong database host
- **Solution**: Updated `src/config.py` to use `EXTERNAL_POSTGRES_*` variables
- **Status**: ✅ Resolved

### **Container Conflicts**
- **Problem**: Docker configurations interfering with each other
- **Solution**: Isolated directories and unique volume names
- **Status**: ✅ Resolved

---

## 🔄 **Development Workflow**

### **Daily Development**
1. **Make code changes** in `src/` directory
2. **Test locally** with `./scripts/manage-docker-storage.sh test`
3. **Verify both storage methods** work correctly
4. **Deploy to Pi** when ready for Pi-specific testing

### **Pi Deployment Cycle**
1. **Code changes** → Docker testing → Pi deployment
2. **Pi testing** → Bug fixes → Docker testing → Pi deployment
3. **Repeat** until Pi deployment is stable

### **Code Quality Gates**
- [ ] Docker dual-storage tests pass
- [ ] Environment variables load correctly
- [ ] Both storage methods functional
- [ ] No breaking changes to existing functionality

---

## 📚 **Reference Materials**

### **Key Files**
- `src/main.py` - Environment variable loading
- `src/config.py` - Database configuration
- `pi-deployment/config/environment-pi.env` - Pi environment template
- `scripts/manage-docker-storage.sh` - Local testing environment

### **Useful Commands**
```bash
# Test locally
./scripts/manage-docker-storage.sh start
./scripts/manage-docker-storage.sh test
./scripts/manage-docker-storage.sh stop

# Check Pi status
py_bridge run-stream "systemctl status inventory"
py_bridge run-stream "docker ps"  # if using Docker on Pi
```

### **Pi Access**
- **IP Address**: 192.168.43.204 (when available)
- **User**: pi
- **SSH Key**: Configured in PyBridge
- **Web Access**: http://192.168.43.204:8000 (when running)

### **PyBridge Best Practices**
- **Always use `run-stream`** for better visibility and debugging
- **`run-stream` shows real-time output** and helps catch failures
- **`run` can hide failures** and hang without feedback
- **Use `py_bridge` alias** from inv2-dev directory for convenience

---

## 🎯 **Success Criteria for Milestone 1**

- [ ] Pi boots and runs inventory system automatically
- [ ] All features work: homepage, images, re-indexing, ML
- [ ] Filesystem image storage working correctly
- [ ] Environment variables loading properly
- [ ] Iterative development process established
- [ ] Docker environment remains functional
- [ ] Ready to move to Milestone 2 (first boot configuration)

---

## 💡 **Lessons Learned**

1. **Environment variables must load early** - before any module imports
2. **Docker isolation is critical** - separate directories prevent conflicts
3. **Test both storage methods** - ensures code works in all scenarios
4. **Iterative deployment** - small changes, frequent testing
5. **Document everything** - saves time and prevents repeated mistakes

---

*Last Updated: August 20, 2025*
*Status: Milestone 1 - Pi Deployment with Filesystem Images*
