# ThingDB Installation Guide

## Recommended: Automated Installation (3 Steps)

This is the **easiest and recommended** way to install ThingDB on Raspberry Pi, Ubuntu, Debian, or macOS:

### Step 1: Clone Repository

```bash
git clone https://github.com/mcyork/thingdb.git
cd thingdb
```

### Step 2: Install System Dependencies

```bash
./install_system_deps.sh
```

This script automatically:
- ✅ Detects your operating system
- ✅ Installs PostgreSQL 12+
- ✅ Installs Python development tools
- ✅ Installs required system libraries
- ✅ Creates `thingdb` database and user
- ✅ Generates `.env` configuration file

**No manual setup required!**

### Step 3: Install ThingDB

```bash
# Recommended: Use a virtual environment
python3 -m venv venv
source venv/bin/activate

# Raspberry Pi only: Set temp directory to disk (not RAM-based /tmp)
# This prevents "No space left on device" errors during large downloads
mkdir -p ~/tmp
export TMPDIR=~/tmp

# Install ThingDB (includes all ML dependencies)
pip install -e .
```

### Step 4: Run

```bash
# Initialize database tables
thingdb init

# Start the server
thingdb serve
```

Open `http://localhost:5000` in your browser 🎉

---

## Step-by-Step Installation

### 1. Prerequisites

**Python 3.9 or higher:**
```bash
python3 --version  # Should be 3.9+
```

**PostgreSQL 12 or higher:**
```bash
# Ubuntu/Debian
sudo apt update
sudo apt install postgresql postgresql-contrib

# macOS
brew install postgresql

# Start PostgreSQL
sudo systemctl start postgresql  # Linux
brew services start postgresql   # macOS
```

### 2. Database Setup

```bash
# Create database and user
sudo -u postgres psql

# In PostgreSQL prompt:
CREATE DATABASE thingdb;
CREATE USER thingdb WITH PASSWORD 'your_secure_password';
GRANT ALL PRIVILEGES ON DATABASE thingdb TO thingdb;
\q
```

### 3. Environment Configuration

```bash
# Copy example environment file
cp .env.example .env

# Edit with your settings
nano .env  # or vim, code, etc.
```

Update these key settings:
- `POSTGRES_PASSWORD` - Your database password
- `SECRET_KEY` - A random secure string
- `FLASK_DEBUG` - Set to 0 for production

### 4. Install ThingDB

```bash
pip install -e .
```

This installs:
- Core Flask application
- PyTorch (CPU-only, ~500MB)
- Sentence transformers for semantic search (~80MB)
- All dependencies (~600MB total)

**Note:** ML dependencies are required (not optional). Semantic search is a core feature of ThingDB.

### 5. Initialize Database

```bash
thingdb init
```

This creates all necessary database tables.

### 6. Start the Application

```bash
thingdb serve
```

Or with custom settings:
```bash
thingdb serve --host 0.0.0.0 --port 8080
```

Visit: `http://localhost:5000` (or your custom port)

## Installation on Raspberry Pi

### Recommended: Raspberry Pi 4 (4GB+ RAM)

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install git and dependencies
sudo apt install git python3-pip python3-venv postgresql libpq-dev -y

# Clone repository
git clone https://github.com/mcyork/thingdb.git
cd thingdb

# Install system dependencies
./install_system_deps.sh

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Set temp directory to disk (prevents RAM-based /tmp from filling up)
mkdir -p ~/tmp
export TMPDIR=~/tmp

# Install ThingDB
pip install -e .

# Initialize and start
thingdb init
sudo systemctl enable thingdb
sudo systemctl start thingdb
```

**Note:** ML features work but may be slow on Pi 3 or older. Consider using `pip install -e .` without ML on older hardware.

## Docker Installation

```bash
# Using Docker Compose (easiest)
docker-compose -f docker/docker-compose.yml up -d

# Access at: http://localhost
```

## Upgrading

```bash
# Pull latest code
git pull

# Reinstall
pip install -e .[ml] --upgrade

# Restart service
# (or docker-compose restart if using Docker)
```

## Uninstalling

```bash
pip uninstall thingdb
```

To completely remove including database:
```bash
pip uninstall thingdb
sudo -u postgres psql -c "DROP DATABASE thingdb;"
sudo -u postgres psql -c "DROP USER thingdb;"
```

## Troubleshooting

### Import Error: No module named 'thingdb'

Make sure you installed with `-e` flag:
```bash
pip install -e .[ml]
```

### Database Connection Error

Check PostgreSQL is running:
```bash
sudo systemctl status postgresql  # Linux
brew services list                # macOS
```

Verify `.env` settings match your database.

### Port Already in Use

Change the port:
```bash
thingdb serve --port 8080
```

### Slow Performance on Raspberry Pi

Try without ML features:
```bash
pip uninstall thingdb
pip install -e .
```

Or use Docker with memory limits.

## Production Deployment

For production use:

1. **Set `FLASK_DEBUG=0`** in `.env`
2. **Use a strong `SECRET_KEY`**
3. **Use Gunicorn** instead of Flask dev server:
   ```bash
   gunicorn -w 4 -b 0.0.0.0:5000 thingdb.main:app
   ```
4. **Set up systemd service** (see `docs/systemd-service.md`)
5. **Use Nginx** as reverse proxy (see `docker/nginx.conf`)

## Getting Help

- Check `README.md` for usage information
- Visit [GitHub Issues](https://github.com/mcyork/thingdb/issues)
- Read the docs in `docs/` folder

