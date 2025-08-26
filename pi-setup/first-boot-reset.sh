#!/bin/bash

# This script runs once during first boot to clear all credentials
# It's designed to be safe and only run once

RESET_FLAG="/var/lib/inventory/.first-boot-complete"

# Check if we've already run this script
if [ -f "$RESET_FLAG" ]; then
    echo "First boot reset already completed. Skipping."
    exit 0
fi

echo "=== First Boot Reset Script ==="
echo "Clearing all credentials for new user setup..."

# Wait for system to be fully booted
sleep 30

# 1. Clear WiFi credentials
echo "Clearing WiFi credentials..."

# Backup current config
if [ -f "/etc/wpa_supplicant/wpa_supplicant.conf" ]; then
    sudo cp /etc/wpa_supplicant/wpa_supplicant.conf /etc/wpa_supplicant/wpa_supplicant.conf.backup
fi

# Reset to minimal config
sudo tee /etc/wpa_supplicant/wpa_supplicant.conf > /dev/null << 'EOF'
country=US
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
EOF

# 2. Clear SSH host keys (so new users get fresh ones)
echo "Clearing SSH host keys..."
sudo rm -f /etc/ssh/ssh_host_*
sudo rm -f /etc/ssh/ssh_host_rsa_key
sudo rm -f /etc/ssh/ssh_host_ecdsa_key
sudo rm -f /etc/ssh/ssh_host_ed25519_key

# 3. Clear authorized_keys (remove your SSH access)
echo "Clearing authorized SSH keys..."
sudo rm -f /home/pi/.ssh/authorized_keys
sudo rm -f /root/.ssh/authorized_keys

# 4. Clear any known_hosts
echo "Clearing known hosts..."
sudo rm -f /home/pi/.ssh/known_hosts
sudo rm -f /root/.ssh/known_hosts

# 5. Reset SSH service to generate new keys on next start
echo "Resetting SSH service..."
sudo systemctl stop ssh
sudo systemctl disable ssh

# 6. Clear any network configurations
echo "Clearing network configurations..."
sudo rm -f /etc/network/interfaces.d/*
sudo rm -f /etc/systemd/network/*

# 7. Reset hostname to default
echo "Resetting hostname..."
echo "raspberrypi" | sudo tee /etc/hostname > /dev/null
sudo sed -i 's/.*127.0.1.1.*/127.0.1.1\traspberrypi/' /etc/hosts

# 8. Clear any custom user configurations
echo "Clearing custom configurations..."
sudo rm -f /home/pi/.bash_history
sudo rm -f /root/.bash_history

# 9. Ensure BTBerryWifi service is running
echo "Ensuring BTBerryWifi service is ready..."
sudo systemctl enable btwifiset.service
sudo systemctl start btwifiset.service

# 10. Create a welcome message
echo "Creating welcome message..."
sudo tee /home/pi/welcome.txt > /dev/null << 'EOF'
Welcome to your new Inventory Pi!

This Pi has been reset and is ready for first-time setup.

To configure WiFi:
1. Install BTBerryWifi app on your phone
2. Open the app and scan for Bluetooth devices
3. Connect to this Pi and configure your WiFi network

The Pi will automatically connect to your network once configured.

For support, visit: [your-support-url]
EOF

# 11. Mark this script as complete
echo "Marking first boot as complete..."
sudo mkdir -p /var/lib/inventory
echo "$(date): First boot reset completed" | sudo tee "$RESET_FLAG" > /dev/null

echo "=== First Boot Reset Complete ==="
echo "Your Pi is now ready for new user setup!"
echo "WiFi credentials cleared, SSH keys reset, system ready for BTBerryWifi setup."

# Optional: Reboot to ensure all changes take effect
echo "Rebooting in 10 seconds to ensure all changes take effect..."
sleep 10
sudo reboot
