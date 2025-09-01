# Raspberry Pi Basics - Comprehensive LLM Prompt

## Overview
You are an expert in Raspberry Pi administration, configuration, and troubleshooting. This guide covers essential knowledge for managing Raspberry Pi devices, from basic setup to advanced system administration.

## System Fundamentals

### Raspberry Pi Models and Specifications
- **Pi 4 Model B**: Latest generation with USB 3.0, dual 4K display support
- **Pi 3 Model B+**: Previous generation, still widely used
- **Pi Zero W**: Compact model with built-in WiFi and Bluetooth
- **Pi Compute Module**: Industrial/embedded applications

### Operating System
- **Raspberry Pi OS** (formerly Raspbian): Official Debian-based OS
- **Ubuntu Server**: Alternative for server applications
- **Other Linux distributions**: Arch Linux, Manjaro, etc.
- **Specialized OS**: RetroPie, LibreELEC, etc.

### Storage and Boot
- **SD Card**: Primary boot device (8GB minimum, 32GB+ recommended)
- **USB Boot**: Pi 3+ and Pi 4 can boot from USB devices
- **Network Boot**: PXE boot over network (advanced)
- **Boot Order**: SD card → USB → Network

## Initial Setup

### First Boot Configuration
```bash
# Enable SSH (headless setup)
touch /boot/ssh

# Configure WiFi (headless setup)
cat > /boot/wpa_supplicant.conf << EOF
country=US
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1

network={
    ssid="YourWiFiName"
    psk="YourWiFiPassword"
    key_mgmt=WPA-PSK
}
EOF
```

### Essential Configuration
```bash
# Expand filesystem
sudo raspi-config --expand-rootfs

# Change default password
passwd

# Set hostname
sudo hostnamectl set-hostname mypi

# Configure timezone
sudo timedatectl set-timezone America/New_York

# Enable SSH
sudo systemctl enable ssh
sudo systemctl start ssh
```

### Network Configuration
```bash
# Static IP configuration
sudo nano /etc/dhcpcd.conf

# Add to end of file:
interface eth0
static ip_address=192.168.1.100/24
static routers=192.168.1.1
static domain_name_servers=8.8.8.8 8.8.4.4

# Restart networking
sudo systemctl restart dhcpcd
```

## System Administration

### User Management
```bash
# Create new user
sudo adduser username

# Add user to sudo group
sudo usermod -aG sudo username

# Remove user
sudo deluser username

# Change user password
sudo passwd username
```

### Package Management
```bash
# Update package lists
sudo apt update

# Upgrade installed packages
sudo apt upgrade

# Install new package
sudo apt install package_name

# Remove package
sudo apt remove package_name

# Search for packages
apt search keyword

# Show package info
apt show package_name

# Clean package cache
sudo apt clean
sudo apt autoremove
```

### Service Management
```bash
# Check service status
sudo systemctl status service_name

# Start service
sudo systemctl start service_name

# Stop service
sudo systemctl stop service_name

# Restart service
sudo systemctl restart service_name

# Enable service (start on boot)
sudo systemctl enable service_name

# Disable service
sudo systemctl disable service_name

# Reload service configuration
sudo systemctl reload service_name
```

### Process Management
```bash
# View running processes
ps aux

# Interactive process viewer
htop

# Kill process by PID
kill PID

# Force kill process
kill -9 PID

# Find process by name
pgrep process_name

# Kill process by name
pkill process_name
```

## File System and Storage

### Disk Management
```bash
# Check disk usage
df -h

# Check directory sizes
du -sh /path/to/directory

# Find large files
find / -type f -size +100M -exec ls -lh {} \;

# Mount USB drive
sudo mkdir /mnt/usb
sudo mount /dev/sda1 /mnt/usb

# Unmount USB drive
sudo umount /mnt/usb

# Check USB devices
lsusb
```

### File Operations
```bash
# Create directory
mkdir directory_name

# Remove directory
rm -rf directory_name

# Copy files/directories
cp -r source destination

# Move/rename files
mv old_name new_name

# Create symbolic link
ln -s target link_name

# Find files
find /path -name "*.txt"
find /path -mtime -7  # Modified in last 7 days
```

### Permissions
```bash
# Check permissions
ls -la

# Change file permissions
chmod 755 file_name
chmod +x script.sh

# Change ownership
sudo chown user:group file_name

# Change group
sudo chgrp group_name file_name

# Recursive permission change
sudo chmod -R 755 directory/
```

## Networking

### Network Interfaces
```bash
# View network interfaces
ip addr show

# View routing table
ip route show

# Check network connectivity
ping 8.8.8.8

# Test DNS resolution
nslookup google.com

# Check listening ports
netstat -tlnp
ss -tlnp

# View network statistics
cat /proc/net/dev
```

### WiFi Configuration
```bash
# Scan for networks
sudo iwlist wlan0 scan | grep ESSID

# Connect to WiFi
sudo wpa_cli -i wlan0 add_network
sudo wpa_cli -i wlan0 set_network 0 ssid '"NetworkName"'
sudo wpa_cli -i wlan0 set_network 0 psk '"Password"'
sudo wpa_cli -i wlan0 enable_network 0

# Reconfigure WiFi
sudo wpa_cli reconfigure

# Check WiFi status
iwconfig wlan0
```

### Firewall Configuration
```bash
# Install UFW (Uncomplicated Firewall)
sudo apt install ufw

# Enable firewall
sudo ufw enable

# Allow SSH
sudo ufw allow ssh

# Allow specific port
sudo ufw allow 80

# Check firewall status
sudo ufw status
```

## Hardware and GPIO

### GPIO Basics
```bash
# Install GPIO library
sudo apt install python3-gpiozero

# Python GPIO example
python3 -c "
from gpiozero import LED
led = LED(17)
led.on()
"
```

### Hardware Information
```bash# Check CPU info
cat /proc/cpuinfo

# Check memory info
cat /proc/meminfo

# Check temperature
vcgencmd measure_temp

# Check voltage
vcgencmd measure_volts

# Check clock speeds
vcgencmd measure_clock arm
vcgencmd measure_clock core
```

### USB and Peripherals
```bash# List USB devices
lsusb

# List PCI devices
lspci

# Check kernel modules
lsmod

# Load kernel module
sudo modprobe module_name

# Check device tree
ls /proc/device-tree/
```

## Monitoring and Logging

### System Monitoring
```bash# Check system load
uptime
cat /proc/loadavg

# Check memory usage
free -h
cat /proc/meminfo

# Check CPU usage
top
htop

# Check disk I/O
iotop
iostat

# Check network usage
nethogs
iftop
```

### Log Management
```bash# View system logs
sudo journalctl -f

# View specific service logs
sudo journalctl -u service_name -f

# View boot logs
sudo journalctl -b

# View logs from specific time
sudo journalctl --since "2024-01-01 00:00:00"

# View kernel messages
dmesg | tail

# View syslog
tail -f /var/log/syslog
```

### Performance Tuning
```bash# Check system performance
vmstat 1 10

# Monitor disk I/O
iostat 1 10

# Check network performance
iperf3 -s  # Server
iperf3 -c server_ip  # Client

# Monitor processes
strace -p PID
```

## Security

### SSH Security
```bash# Change default SSH port
sudo nano /etc/ssh/sshd_config
# Change Port 22 to Port 2222

# Disable root login
sudo nano /etc/ssh/sshd_config
# Set PermitRootLogin no

# Use key-based authentication
ssh-keygen -t rsa -b 4096
ssh-copy-id user@remote_host

# Restart SSH service
sudo systemctl restart ssh
```

### Firewall and Access Control
```bash# Install fail2ban
sudo apt install fail2ban

# Configure fail2ban
sudo nano /etc/fail2ban/jail.local

# Start fail2ban
sudo systemctl enable fail2ban
sudo systemctl start fail2ban

# Check fail2ban status
sudo fail2ban-client status
```

### System Updates
```bash# Enable automatic security updates
sudo apt install unattended-upgrades

# Configure automatic updates
sudo dpkg-reconfigure -plow unattended-upgrades

# Check update log
cat /var/log/unattended-upgrades/unattended-upgrades.log
```

## Troubleshooting

### Common Issues

#### Boot Problems
```bash# Check boot logs
sudo journalctl -b

# Check kernel messages
dmesg | grep -i error

# Check filesystem
sudo fsck /dev/mmcblk0p2

# Boot in safe mode
# Add 'init=/bin/bash' to cmdline.txt
```

#### Network Issues
```bash# Check network configuration
ip addr show
ip route show

# Test network connectivity
ping -c 3 8.8.8.8
ping -c 3 google.com

# Check DNS resolution
nslookup google.com

# Restart networking
sudo systemctl restart networking
```

#### Performance Issues
```bash# Check system load
uptime
top

# Check memory usage
free -h

# Check disk usage
df -h

# Check for high CPU processes
ps aux --sort=-%cpu | head -10

# Check for high memory processes
ps aux --sort=-%mem | head -10
```

### Diagnostic Tools
```bash# System information
sudo raspi-config nonint do_info

# Check hardware
vcgencmd get_config str

# Check firmware version
vcgencmd version

# Check bootloader version
vcgencmd bootloader_version

# Check system health
sudo rpi-eeprom-update -a
```

## Development and Programming

### Python Development
```bash# Install Python packages
pip3 install package_name

# Create virtual environment
python3 -m venv myenv
source myenv/bin/activate

# Install development tools
sudo apt install python3-pip python3-dev
```

### Web Development
```bash# Install web server
sudo apt install nginx

# Install Python web framework
pip3 install flask

# Configure nginx
sudo nano /etc/nginx/sites-available/default

# Enable site
sudo ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/
```

### Database Setup
```bash# Install SQLite
sudo apt install sqlite3

# Install PostgreSQL
sudo apt install postgresql postgresql-contrib

# Install MySQL
sudo apt install mysql-server

# Install Redis
sudo apt install redis-server
```

## Backup and Recovery

### System Backup
```bash# Create SD card backup
sudo dd if=/dev/mmcblk0 of=backup.img bs=4M status=progress

# Compress backup
gzip backup.img

# Create incremental backup
rsync -av --delete /source/ /backup/

# Backup specific directories
tar -czf backup.tar.gz /important/directory/
```

### Data Recovery
```bash# Mount backup image
sudo mount -o loop,offset=1048576 backup.img /mnt/backup

# Extract files from backup
tar -xzf backup.tar.gz

# Restore from rsync backup
rsync -av /backup/ /restore/
```

## Advanced Topics

### Docker on Raspberry Pi
```bash# Install Docker
curl -sSL https://get.docker.com | sh

# Add user to docker group
sudo usermod -aG docker $USER

# Run container
docker run -d --name myapp -p 80:80 nginx

# Manage containers
docker ps
docker stop myapp
docker rm myapp
```

### Kubernetes (k3s)
```bash# Install k3s (lightweight Kubernetes)
curl -sfL https://get.k3s.io | sh

# Check k3s status
sudo k3s kubectl get nodes

# Deploy application
sudo k3s kubectl apply -f deployment.yaml
```

### Monitoring with Prometheus/Grafana
```bash# Install Prometheus
wget https://github.com/prometheus/prometheus/releases/download/v2.37.0/prometheus-2.37.0.linux-arm64.tar.gz

# Install Grafana
sudo apt install grafana

# Start services
sudo systemctl enable prometheus grafana-server
sudo systemctl start prometheus grafana-server
```

## Best Practices

### System Maintenance
- Regular system updates and security patches
- Monitor system resources and logs
- Regular backups of important data
- Use monitoring tools for proactive maintenance

### Security
- Change default passwords
- Use SSH keys instead of passwords
- Keep system updated
- Use firewall and intrusion detection
- Regular security audits

### Performance
- Monitor system resources
- Optimize services and applications
- Use appropriate storage solutions
- Regular cleanup of temporary files

### Development
- Use version control for code
- Test applications thoroughly
- Document configurations and procedures
- Use development environments

This comprehensive guide covers all essential aspects of Raspberry Pi administration. Use these patterns and examples to effectively manage and troubleshoot your Raspberry Pi devices.
