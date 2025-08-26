#!/bin/bash

# This script wipes all credentials from the Pi before creating a distributable image
# Run this BEFORE creating your SD card image

echo "=== Wiping All Credentials ==="
echo "This will remove all WiFi, SSH, and personal data from this Pi."
echo "Make sure you have a monitor/keyboard connected as SSH will be disabled."
echo ""
read -p "Are you sure you want to continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

echo "Wiping credentials..."

# 1. Clear WiFi credentials
echo "Clearing WiFi credentials..."
sudo rm -f /etc/wpa_supplicant/wpa_supplicant.conf
sudo tee /etc/wpa_supplicant/wpa_supplicant.conf > /dev/null << 'EOF'
country=US
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
EOF

# 2. Clear SSH host keys
echo "Clearing SSH host keys..."
sudo rm -f /etc/ssh/ssh_host_*
sudo rm -f /etc/ssh/ssh_host_rsa_key
sudo rm -f /etc/ssh/ssh_host_ecdsa_key
sudo rm -f /etc/ssh/ssh_host_ed25519_key

# 3. Clear authorized_keys
echo "Clearing authorized SSH keys..."
sudo rm -f /home/pi/.ssh/authorized_keys
sudo rm -f /root/.ssh/authorized_keys

# 4. Clear known_hosts
echo "Clearing known hosts..."
sudo rm -f /home/pi/.ssh/known_hosts
sudo rm -f /root/.ssh/known_hosts

# 5. Disable SSH service
echo "Disabling SSH service..."
sudo systemctl stop ssh
sudo systemctl disable ssh

# 6. Clear network configurations
echo "Clearing network configurations..."
sudo rm -f /etc/network/interfaces.d/*
sudo rm -f /etc/systemd/network/*

# 7. Reset hostname
echo "Resetting hostname..."
echo "raspberrypi" | sudo tee /etc/hostname > /dev/null
sudo sed -i 's/.*127.0.1.1.*/127.0.1.1\traspberrypi/' /etc/hosts

# 8. Clear bash history
echo "Clearing bash history..."
sudo rm -f /home/pi/.bash_history
sudo rm -f /root/.bash_history

# 9. Clear any custom configurations
echo "Clearing custom configurations..."
sudo rm -f /home/pi/.profile
sudo rm -f /home/pi/.bashrc
sudo rm -f /root/.profile
sudo rm -f /root/.bashrc

# 10. Ensure BTBerryWifi service is ready
echo "Ensuring BTBerryWifi service is ready..."
sudo systemctl enable btwifiset.service

# 11. Create welcome message
echo "Creating welcome message..."
sudo tee /home/pi/welcome.txt > /dev/null << 'EOF'
Welcome to your new Inventory Pi!

This Pi is ready for first-time setup.

To configure WiFi:
1. Install BTBerryWifi app on your phone
2. Open the app and scan for Bluetooth devices
3. Connect to this Pi and configure your WiFi network

The Pi will automatically connect to your network once configured.

IMPORTANT: Bluetooth is only enabled for 10 minutes after boot for security.
If you need more time, reboot the Pi or manually re-enable Bluetooth.

For support, visit: [your-support-url]
EOF

# 12. Clear any logs that might contain sensitive info
echo "Clearing sensitive logs..."
sudo journalctl --vacuum-time=1s
sudo rm -f /var/log/auth.log*
sudo rm -f /var/log/daemon.log*
sudo rm -f /var/log/syslog*

echo ""
echo "=== Credentials Wiped Successfully ==="
echo "Your Pi is now clean and ready for distribution!"
echo ""
echo "Next steps:"
echo "1. Power off the Pi"
echo "2. Remove the SD card"
echo "3. Create an image using: sudo dd if=/dev/sdX of=inventory-pi-image.img bs=4M status=progress"
echo "4. Compress it: gzip inventory-pi-image.img"
echo ""
echo "The resulting .img.gz file can be distributed and will work on any SD card size."
echo "Users just need to flash it with Pi Imager, which handles partition resizing automatically."
