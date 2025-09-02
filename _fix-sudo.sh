#!/bin/bash

# Fix sudo configuration for pi user
echo "pi ALL=(ALL) NOPASSWD: ALL" > /tmp/pi-sudoers
chmod 440 /tmp/pi-sudoers
mv /tmp/pi-sudoers /etc/sudoers.d/010_pi-nopasswd
chmod 440 /etc/sudoers.d/010_pi-nopasswd

echo "Sudo configuration fixed"
