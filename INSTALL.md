# ThingDB Installation Guide

## ⚡ Quick Install (Recommended)

**One command. That's it.**

```bash
wget -qO- https://raw.githubusercontent.com/mcyork/thingdb/main/bootstrap.sh | bash
```

This downloads, extracts, and installs ThingDB automatically. Works on:
- ✅ Raspberry Pi (all models)
- ✅ Ubuntu/Debian
- ✅ macOS (with Homebrew)

**What it does:**
1. Downloads ThingDB from GitHub
2. Creates dedicated `thingdb` system user
3. Installs PostgreSQL and dependencies
4. Sets up Python environment with ML support
5. Initializes database
6. Configures systemd service (auto-start on boot)
7. Starts ThingDB immediately

**Access:** `http://YOUR_IP:5000` (displayed after install)

---

## 📦 Manual Installation (3 Steps)

If you prefer to see what's happening or want more control:

### Step 1: Download ThingDB

```bash
# Download from GitHub (no git required!)
wget https://github.com/mcyork/thingdb/archive/refs/heads/main.zip
unzip main.zip
cd thingdb-main
```

### Step 2: Run Installer

```bash
./install.sh
```

That's it! The installer handles everything automatically.

---

## 🔧 Advanced Installation

### For Developers

If you want to customize or develop:

```bash
# Clone repository
git clone https://github.com/mcyork/thingdb.git
cd thingdb

# Install system dependencies
./install_system_deps.sh

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Raspberry Pi only: Set temp directory to disk (not RAM-based /tmp)
# This prevents "No space left on device" errors during large downloads
mkdir -p ~/tmp
export TMPDIR=~/tmp

# Install ThingDB (includes all ML dependencies)
pip install -e .

# Initialize database
thingdb init

# Start server
thingdb serve
```

Open `http://localhost:5000` in your browser 🎉

---

## 🍓 Raspberry Pi Notes

### Recommended Hardware
- **Raspberry Pi 4 or 5** (4GB+ RAM) - Best performance
- **Pi Zero 2 W** (512MB RAM) - Works, but slower ML operations

### Pi-Specific Tips

**RAM Management:**
- Pi Zero/older models may use swap heavily
- ML semantic search works but takes longer
- Consider Pi 4+ for best experience

**Installation:**
```bash
# Update system first
sudo apt update && sudo apt upgrade -y

# Use the one-command installer
wget -qO- https://raw.githubusercontent.com/mcyork/thingdb/main/bootstrap.sh | bash
```

**After Installation:**
```bash
# Check status
sudo systemctl status thingdb

# View logs
sudo journalctl -u thingdb -f

# Restart if needed
sudo systemctl restart thingdb
```

---

## 🔐 HTTPS Setup

**Good news:** HTTPS is automatically configured during installation! 

The installer generates a self-signed SSL certificate, which enables:
- ✅ Camera access on iPhone (required by iOS)
- ✅ Secure connections
- ✅ Modern browser features

**Already configured!** Just access `https://YOUR_IP:5000`

### Bring Your Own Certificate (BYO)

Want to use a certificate from **Let's Encrypt**, your company's **internal PKI**, or a **commercial CA** instead of self-signed? Easy!

#### Step 1: Prepare Your Certificates

You need two files:

1. **cert.pem** - Your certificate + intermediate CA chain (concatenated)
   ```bash
   # Let's Encrypt example:
   cat fullchain.pem > cert.pem
   
   # Or from separate files:
   cat your-cert.pem intermediate-ca.pem > cert.pem
   ```

2. **key.pem** - Your unencrypted private key
   ```bash
   # Copy your private key
   cp privkey.pem key.pem
   
   # If encrypted, decrypt it first:
   openssl rsa -in encrypted-key.pem -out key.pem
   ```

#### Step 2: Place Certificates in Staging Directory

```bash
# Create staging directory
sudo mkdir -p /var/lib/thingdb/certs

# Copy your certificates
sudo cp cert.pem /var/lib/thingdb/certs/
sudo cp key.pem /var/lib/thingdb/certs/

# Verify files are there
ls -la /var/lib/thingdb/certs/
```

#### Step 3: Run SSL Setup

```bash
cd /var/lib/thingdb/app
sudo ./setup_ssl.sh
```

**What happens:**
- ✅ Validates your certificates
- ✅ Checks cert and key match
- ✅ Installs to `/var/lib/thingdb/ssl/` with secure permissions
- ✅ Updates service to use your certificates
- ✅ Cleans up staging directory
- ✅ Restarts ThingDB with HTTPS

**Your certificate is now active!** Browsers will trust it (if your CA is trusted).

#### Certificate Renewal

When your certificate needs renewal (Let's Encrypt renews every 90 days):

```bash
# 1. Get new certificate from your CA
# 2. Place in staging directory
sudo cp new-fullchain.pem /var/lib/thingdb/certs/cert.pem
sudo cp new-privkey.pem /var/lib/thingdb/certs/key.pem

# 3. Run setup (same command)
cd /var/lib/thingdb/app
sudo ./setup_ssl.sh

# Done! New certificate installed automatically
```

#### Let's Encrypt Example

```bash
# Assuming you have certbot installed and certs obtained
sudo mkdir -p /var/lib/thingdb/certs
sudo cp /etc/letsencrypt/live/yourdomain.com/fullchain.pem /var/lib/thingdb/certs/cert.pem
sudo cp /etc/letsencrypt/live/yourdomain.com/privkey.pem /var/lib/thingdb/certs/key.pem

cd /var/lib/thingdb/app
sudo ./setup_ssl.sh
```

**No browser warnings, trusted by all devices!** 🎉

---

### Manual SSL Setup (Self-Signed)

If you need to regenerate self-signed certificates:

```bash
cd /var/lib/thingdb/app
sudo ./setup_ssl.sh --force
```

---

## 🐳 Docker Installation

```bash
# Using Docker Compose (easiest)
cd docker
docker-compose up -d

# Access at: http://localhost:5000
```

The Docker image includes PostgreSQL, Python, and all dependencies in one container.

---

## 📋 System Requirements

### Minimum
- **OS:** Raspberry Pi OS, Ubuntu 20.04+, Debian 11+, macOS 12+
- **Python:** 3.9 or higher
- **PostgreSQL:** 12 or higher
- **RAM:** 512MB (1GB+ recommended)
- **Disk:** 2GB free space

### Dependencies (auto-installed)
- PostgreSQL database
- Python 3 + pip + venv
- Build tools (gcc, make, etc.)
- libpq-dev (PostgreSQL headers)
- PyTorch (CPU-only, ~500MB)
- Sentence Transformers (~80MB)

**Total download:** ~600MB

---

## ⚙️ Configuration

### Database Settings

Default credentials (automatically configured):
- **Database:** `thingdb`
- **User:** `thingdb`
- **Password:** `thingdb_default_pass`

**⚠️ Change the password in production!**

Edit `.env` file:
```bash
# Location depends on installation method:
# Quick install: /var/lib/thingdb/app/.env
# Manual install: ./env

nano /var/lib/thingdb/app/.env
```

Update these settings:
```env
POSTGRES_PASSWORD=your_secure_password
SECRET_KEY=your_random_secret_key
FLASK_DEBUG=0
```

Restart after changes:
```bash
sudo systemctl restart thingdb
```

### Image Storage

By default, images are stored in filesystem:
```env
IMAGE_STORAGE_METHOD=filesystem
IMAGE_DIR=/var/lib/thingdb/images
```

---

## 🔄 Upgrading

```bash
cd /var/lib/thingdb/app
git pull
pip install -e . --upgrade
sudo systemctl restart thingdb
```

---

## 🗑️ Uninstalling

### Remove Application
```bash
# Stop service
sudo systemctl stop thingdb
sudo systemctl disable thingdb

# Remove files
sudo rm -rf /var/lib/thingdb
sudo rm /etc/systemd/system/thingdb.service
sudo systemctl daemon-reload

# Remove user
sudo userdel thingdb

# Uninstall Python package
pip uninstall thingdb
```

### Remove Database (optional)
```bash
sudo -u postgres psql -c "DROP DATABASE thingdb;"
sudo -u postgres psql -c "DROP USER thingdb;"
```

---

## 🐛 Troubleshooting

### Service Won't Start

**Check logs:**
```bash
sudo journalctl -u thingdb -n 50
```

**Common issues:**
- PostgreSQL not running: `sudo systemctl start postgresql`
- Port 5000 in use: Change port in `.env`
- Permission errors: Check file ownership (`sudo chown -R thingdb:thingdb /var/lib/thingdb`)

### Database Connection Error

**Verify PostgreSQL is running:**
```bash
sudo systemctl status postgresql
```

**Check database exists:**
```bash
sudo -u postgres psql -l | grep thingdb
```

**Verify `.env` settings match database credentials**

### Import Error: No module named 'thingdb'

Make sure you installed with `-e` flag:
```bash
pip install -e .
```

And activate the virtual environment:
```bash
source venv/bin/activate  # or: source /var/lib/thingdb/app/venv/bin/activate
```

### Raspberry Pi: "No space left on device"

On Pi Zero/older models, `/tmp` is RAM-based and too small for PyTorch:

```bash
mkdir -p ~/tmp
export TMPDIR=~/tmp
pip install -e .
```

Or use the quick installer which handles this automatically.

### Camera Not Working on iPhone

iPhone requires HTTPS for camera access. See [HTTPS Setup](#-https-setup-iphone-camera-support) above.

---

## 📚 Additional Resources

- **README.md** - Project overview and features
- **docker/README.md** - Docker deployment guide
- **GitHub Issues** - https://github.com/mcyork/thingdb/issues

---

## 🚀 Production Deployment

For production use:

1. **Change default passwords** in `.env`
2. **Use HTTPS** (run `setup_ssl.sh`)
3. **Set `FLASK_DEBUG=0`** in `.env`
4. **Configure firewall** (open port 5000 or use reverse proxy)
5. **Set up backups** (use Admin → Backup feature)
6. **Monitor logs** (`journalctl -u thingdb -f`)

The installer already uses Gunicorn (production WSGI server) with 2 workers and proper timeouts.

---

## 💬 Getting Help

- Check the logs: `sudo journalctl -u thingdb -n 50`
- Review this guide's Troubleshooting section
- Open an issue: https://github.com/mcyork/thingdb/issues
- Check existing issues for solutions

---

**Quick Install Reminder:**
```bash
wget -qO- https://raw.githubusercontent.com/mcyork/thingdb/main/bootstrap.sh | bash
```

**That's all you need!** 🎉
