#!/bin/bash

# Raspberry Pi Bloat Cleanup Script
# Removes unnecessary packages to reduce image size from ~5GB to ~2GB

set -e

print_status() {
    echo "🔧 $1"
}

print_success() {
    echo "✅ $1"
}

print_warning() {
    echo "⚠️  $1"
}

print_error() {
    echo "❌ $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "Please run as root (use sudo)"
    exit 1
fi

print_status "Starting Raspberry Pi bloat cleanup..."

# Update package list first
print_status "Updating package list..."
apt update

# Remove development tools and compilers (huge space savings)
print_status "Removing development tools and compilers..."
apt remove --purge -y \
    gcc* g++* clang* \
    make cmake autotools-dev \
    build-essential \
    libc6-dev libc-dev \
    linux-libc-dev \
    || print_warning "Some dev tools already removed"

# Remove multiple Python versions and development packages
print_status "Removing Python development packages..."
apt remove --purge -y \
    python3-dev python3-distutils \
    python3-setuptools python3-wheel \
    python3-pip python3-venv \
    || print_warning "Some Python dev packages already removed"

# Remove Node.js and npm (if not needed)
print_status "Removing Node.js and npm..."
apt remove --purge -y \
    nodejs npm \
    || print_warning "Node.js already removed"

# Remove Java and OpenJDK
print_status "Removing Java and OpenJDK..."
apt remove --purge -y \
    openjdk* java* \
    || print_warning "Java already removed"

# Remove desktop environments and GUI packages
print_status "Removing desktop environments..."
apt remove --purge -y \
    gnome* kde* xfce* mate* lxde* budgie* \
    desktop-base desktop-file-utils \
    || print_warning "Some desktop packages already removed"

# Remove multimedia and graphics packages
print_status "Removing multimedia packages..."
apt remove --purge -y \
    vlc* gimp* inkscape* \
    audacity* ardour* \
    ffmpeg* libav* \
    || print_warning "Some multimedia packages already removed"

# Remove games and entertainment
print_status "Removing games and entertainment..."
apt remove --purge -y \
    bsdgames* \
    || print_warning "Games already removed"

# Remove documentation and man pages (can be reinstalled if needed)
print_status "Removing documentation packages..."
apt remove --purge -y \
    man-db manpages* \
    doc-base \
    || print_warning "Some docs already removed"

# Remove unnecessary Python packages (keep only essential ones)
print_status "Removing unnecessary Python packages..."
apt remove --purge -y \
    python3-* \
    || print_warning "Some Python packages already removed"

# Reinstall only essential Python packages
print_status "Reinstalling essential Python packages..."
apt install -y python3 python3-pip python3-venv

# Remove unnecessary fonts (keep only basic ones)
print_status "Removing unnecessary fonts..."
apt remove --purge -y \
    fonts-* \
    || print_warning "Some fonts already removed"

# Reinstall only essential fonts
print_status "Reinstalling essential fonts..."
apt install -y fonts-dejavu-core

# Remove unnecessary libraries and development headers
print_status "Removing unnecessary libraries..."
apt autoremove --purge -y

# Clean package cache
print_status "Cleaning package cache..."
apt autoclean
apt clean

# Remove unnecessary locales (keep only en_US)
print_status "Removing unnecessary locales..."
apt remove --purge -y \
    locales \
    || print_warning "Locales already removed"

# Reinstall only English locale
print_status "Reinstalling English locale..."
apt install -y locales
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen

# Remove unnecessary services and daemons
print_status "Removing unnecessary services..."
systemctl disable --now \
    bluetooth \
    cups \
    avahi-daemon \
    || print_warning "Some services already disabled"

# Clean up log files
print_status "Cleaning log files..."
find /var/log -type f -name "*.log" -exec truncate -s 0 {} \;
find /var/log -type f -name "*.gz" -delete 2>/dev/null || true

# Clean up temporary files
print_status "Cleaning temporary files..."
rm -rf /tmp/*
rm -rf /var/tmp/*

# Clean up package lists
print_status "Cleaning package lists..."
rm -rf /var/lib/apt/lists/*

# Clean up user caches
print_status "Cleaning user caches..."
rm -rf /home/*/.cache/*
rm -rf /root/.cache/*

# Clean up old kernels (keep only current)
print_status "Cleaning old kernels..."
apt autoremove --purge -y

# Show disk usage before and after
print_status "Disk usage after cleanup:"
df -h /

print_success "Bloat cleanup completed!"
print_status "You can now run your deployment script to install only what you need."

# Show what's left installed
print_status "Remaining installed packages:"
dpkg --get-selections | grep -v deinstall | wc -l
