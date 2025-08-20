# PyBridge - Raspberry Pi Management Tool

## 🎯 **Overview**

PyBridge is a custom CLI tool for managing Raspberry Pi devices over SSH. It provides a unified interface for running commands, transferring files, and monitoring Pi status across multiple devices.

## 📍 **Location**

PyBridge is located in a separate repository:
```
/Users/ianmccutcheon/projects/pi-shell/
```

## 🚀 **Quick Start**

### **Basic Usage**
```bash
# Navigate to pi-shell directory
cd /Users/ianmccutcheon/projects/pi-shell

# Check Pi status
./pi status

# Run command on default Pi
./pi run "ls -la"

# Run command with streaming output
./pi run-stream "tail -f /var/log/syslog"

# Access specific Pi directly
./pi2 status
./pi1 status
```

### **Available Commands**
```bash
./pi --help
```

## 🔧 **Core Commands**

### **Pi Management**
```bash
./pi status                    # Check status of all Pis
./pi list                      # List all configured Pis
./pi add                       # Add new Pi to configuration
./pi remove                    # Remove Pi from configuration
./pi set-default              # Set default Pi for commands
```

### **Command Execution**
```bash
./pi run "command"            # Run single command
./pi run-stream "command"     # Run command with streaming output
```

### **File Operations**
```bash
./pi read "remote_path"       # Read file from Pi
./pi write "local_path"       # Write file to Pi
```

## 📱 **Current Pi Configuration**

### **Pi Status**
```
Name       Host                 Hostname             Status    
============================================================
pi1        192.168.43.200       N/A                  OFFLINE   
pi2        192.168.43.204       base-pi-dev          ONLINE    
```

### **Active Pi**
- **pi2** (192.168.43.204) - **ONLINE** - `base-pi-dev`
- **pi1** (192.168.43.200) - **OFFLINE** - Not available

## 🎯 **Pi Deployment Workflow**

### **1. Check Pi Status**
```bash
cd /Users/ianmccutcheon/projects/pi-shell
./pi status
```

### **2. Deploy Code Changes**
```bash
# From inv2-dev directory
cd /Users/ianmccutcheon/projects/inv2-dev

# Deploy to Pi2
py_bridge run-stream "cd /var/lib/inventory && git pull origin main"
py_bridge run-stream "sudo systemctl restart inventory"
```

### **3. Monitor Deployment**
```bash
# Check service status
py_bridge run-stream "sudo systemctl status inventory"

# Check logs
py_bridge run-stream "sudo journalctl -u inventory -f"

# Check application health
py_bridge run "curl -s http://localhost:8000/health"
```

### **4. Verify Functionality**
```bash
# Test homepage
py_bridge run-stream "curl -s http://localhost:8000/ | head -20"

# Check database connection
py_bridge run-stream "sudo -u postgres psql -d inventory_db -c 'SELECT COUNT(*) FROM items;'"

# Verify image directory
py_bridge run-stream "ls -la /var/lib/inventory/images/"
```

## 🔍 **Troubleshooting Commands**

### **Service Issues**
```bash
# Check service status
py_bridge run-stream "sudo systemctl status inventory"

# Restart service
py_bridge run-stream "sudo systemctl restart inventory"

# View service logs
py_bridge run-stream "sudo journalctl -u inventory -n 50"
```

### **Database Issues**
```bash
# Check PostgreSQL status
py_bridge run-stream "sudo systemctl status postgresql"

# Test database connection
py_bridge run-stream "sudo -u postgres psql -d inventory_db -c 'SELECT version();'"

# Check database logs
py_bridge run-stream "sudo tail -f /var/log/postgresql/postgresql-*.log"
```

### **Network Issues**
```bash
# Check network interfaces
py_bridge run-stream "ip addr show"

# Test connectivity
py_bridge run-stream "ping -c 3 8.8.8.8"

# Check listening ports
py_bridge run-stream "sudo netstat -tlnp"
```

### **Application Issues**
```bash
# Check Flask app logs
py_bridge run-stream "sudo tail -f /var/lib/inventory/logs/app.log"

# Test Flask endpoint
py_bridge run-stream "curl -v http://localhost:8000/"

# Check environment variables
py_bridge run-stream "cat /var/lib/inventory/config/.env"
```

## 📁 **File Transfer Operations**

### **Upload Configuration**
```bash
# Upload environment file
py_bridge write /var/lib/inventory/config/.env

# Upload updated source code
py_bridge write /var/lib/inventory/app/
```

### **Download Logs**
```bash
# Download application logs
py_bridge read /var/lib/inventory/logs/

# Download system logs
py_bridge read /var/log/syslog
```

## 🔄 **Development Workflow Integration**

### **Local Development Cycle**
1. **Make code changes** in `inv2-dev/src/`
2. **Test locally** with Docker dual-storage environment
3. **Deploy to Pi** using PyBridge
4. **Verify functionality** on Pi
5. **Iterate** based on results

### **PyBridge Commands in Workflow**
```bash
# Deploy latest changes
py_bridge run-stream "cd /var/lib/inventory && git pull origin main"

# Restart services
py_bridge run-stream "sudo systemctl restart inventory postgresql nginx"

# Check deployment
py_bridge run-stream "sudo journalctl -u inventory -f"
```

## 🛠️ **Advanced Features**

### **Streaming Output**
```bash
# Monitor logs in real-time
py_bridge run-stream "sudo journalctl -u inventory -f"

# Watch system resources
py_bridge run-stream "htop"

# Monitor network traffic
py_bridge run-stream "iftop"
```

### **Batch Operations**
```bash
# Run multiple commands
py_bridge run-stream "cd /var/lib/inventory && git pull && sudo systemctl restart inventory"

# Conditional execution
py_bridge run-stream "if systemctl is-active --quiet inventory; then echo 'Service running'; else echo 'Service stopped'; fi"
```

## 📋 **Configuration Management**

### **Pi Configuration File**
```yaml
# Location: /Users/ianmccutcheon/projects/pi-shell/config.yml
# Contains SSH keys, hostnames, and connection details
```

### **Environment Variables**
```bash
# Pi deployment environment
IMAGE_STORAGE_METHOD=filesystem
IMAGE_DIR=/var/lib/inventory/images
POSTGRES_USER=inventory
POSTGRES_PASSWORD=inventory_pi_2024
POSTGRES_DB=inventory_db
```

## 🚨 **Common Issues & Solutions**

### **Connection Refused**
```bash
# Check if Pi is online
./pi status

# Verify SSH key permissions
ls -la ~/.ssh/id_rsa

# Test SSH connection manually
ssh pi@192.168.43.204
```

### **Permission Denied**
```bash
# Use sudo for system commands
py_bridge run-stream "sudo systemctl status inventory"

# Check user permissions
py_bridge run-stream "whoami && groups"
```

### **Service Not Found**
```bash
# Check if service exists
py_bridge run-stream "sudo systemctl list-units --type=service | grep inventory"

# Verify service file
py_bridge run-stream "ls -la /etc/systemd/system/inventory.service"
```

## 📚 **Integration with Project**

### **From inv2-dev Directory**
```bash
# Use py_bridge alias (if configured)
py_bridge status

# Or use full path
/Users/ianmccutcheon/projects/pi-shell/pi status
```

### **In Scripts**
```bash
#!/bin/bash
# Reference PyBridge in deployment scripts
PYBRIDGE_PATH="/Users/ianmccutcheon/projects/pi-shell/pi"

# Check Pi status
$PYBRIDGE_PATH status

# Deploy changes
$PYBRIDGE_PATH run-stream "cd /var/lib/inventory && git pull"
```

## 🎯 **Best Practices**

### **Command Execution**
- **Always use `run-stream`** for better visibility and debugging
- **`run-stream` shows real-time output** and helps catch failures
- **`run` can hide failures** and hang without feedback
- **Always check Pi status** before running commands
- **Use sudo** for system-level operations

### **File Operations**
- **Verify file paths** before read/write operations
- **Check permissions** on target directories
- **Use absolute paths** for reliability

### **Error Handling**
- **Check command exit codes** when possible
- **Monitor logs** for detailed error information
- **Test connectivity** before complex operations

## 🔮 **Future Enhancements**

### **Planned Features**
- [ ] **Automated deployment** scripts
- [ ] **Health monitoring** dashboard
- [ ] **Backup and restore** functionality
- [ **Multi-Pi** simultaneous operations
- [ ] **Configuration validation** tools

### **Integration Goals**
- [ ] **CI/CD pipeline** integration
- [ ] **Monitoring and alerting** setup
- [ ] **Automated testing** on Pi
- [ ] **Rollback capabilities** for failed deployments

---

## 📖 **Reference Links**

- **PyBridge Repository**: `/Users/ianmccutcheon/projects/pi-shell/`
- **Main Project**: `/Users/ianmccutcheon/projects/inv2-dev/`
- **Pi Deployment Strategy**: `PI-DEPLOYMENT-STRATEGY.md`
- **Docker Testing**: `DOCKER-STORAGE-QUICK-REF.md`

---

*Last Updated: August 20, 2025*
*Status: Active development and Pi deployment*
*PyBridge Version: Current (from pi-shell repository)*
