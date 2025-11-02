# ThingDB Installation Strategy

## The Challenge

When users run `pip install thingdb`, pip can only install Python packages. It cannot:
- Install PostgreSQL
- Install system libraries (libpq-dev, python3-dev)
- Create databases
- Configure system services

## Our Solution: Two-Step Installation

### Step 1: System Dependencies Script

**File:** `install_system_deps.sh`

This automated script:
1. **Detects OS** (Debian/Ubuntu/Raspberry Pi OS/macOS)
2. **Installs PostgreSQL** using apt or brew
3. **Installs development tools** (libpq-dev, python3-dev, etc.)
4. **Creates database and user** automatically
5. **Generates .env file** with default credentials
6. **Provides clear next steps**

**User runs:**
```bash
./install_system_deps.sh
```

**Result:** Complete system ready for ThingDB installation

### Step 2: Python Package Installation

**User runs:**
```bash
pip install -e .
```

**What happens:**
- pip reads `pyproject.toml`
- Installs all Python dependencies including:
  - Flask web framework
  - PostgreSQL driver (psycopg2-binary)
  - PyTorch (for ML)
  - Sentence-transformers (for semantic search)
  - Image processing libraries
  - QR code generation
  - All other dependencies
- Creates `thingdb` command-line tool
- Sets up editable installation

**Result:** ThingDB ready to run

---

## Why ML Dependencies are Required

### Decision: Make ML Non-Optional

**Reasons:**
1. **Core Feature** - Semantic search is a primary selling point
2. **User Experience** - Users expect it to work out of the box
3. **Simplicity** - One installation path, no confusion
4. **No Degraded Mode** - Don't ship a crippled version

**Implementation:**
- Moved ML deps from `[project.optional-dependencies]` to `dependencies`
- Updated to PyTorch 2.6+ (Python 3.13 support)
- Users get full functionality with single `pip install -e .`

---

## Dependency Management

### Before (Complex)
```bash
pip install -r requirements/base-requirements.txt
pip install -r requirements/ml-requirements.txt
# Plus manual PostgreSQL setup
# Plus manual database creation
# Plus manual .env configuration
```

### After (Simple)
```bash
./install_system_deps.sh  # One-time system setup
pip install -e .           # Install ThingDB
```

---

## Python 3.13 Compatibility

### Challenge
- Original config used PyTorch 2.1.1 (no Python 3.13 support)
- psycopg2-binary 2.9.7 (no Python 3.13 support)

### Solution
Updated `pyproject.toml`:
```toml
dependencies = [
    "psycopg2-binary>=2.9.9",  # Python 3.13 compatible
    "torch>=2.6.0",             # Python 3.13 support
    "sentence-transformers>=3.0.0",  # Latest version
]
```

**Result:** Works on Python 3.9 through 3.13

---

## Installation Workflow for Users

### First-Time Setup

```bash
# 1. Clone repository
git clone https://github.com/yourusername/thingdb.git
cd thingdb

# 2. Install system dependencies (automated)
./install_system_deps.sh
# ✅ PostgreSQL installed
# ✅ Database created
# ✅ .env file generated

# 3. Install ThingDB
python3 -m venv venv
source venv/bin/activate
pip install -e .
# ✅ All Python dependencies installed
# ✅ thingdb command available

# 4. Initialize and run
thingdb init   # Create database tables
thingdb serve  # Start server
```

**Total time:** ~5-10 minutes (depending on internet speed for PyTorch download)

### What Users See

```
╔════════════════════════════════════════════════════════════════╗
║         ThingDB System Dependencies Installer                  ║
╚════════════════════════════════════════════════════════════════╝

Detected OS: debian

📦 Installing dependencies for Debian/Ubuntu/Raspberry Pi OS...

Installing PostgreSQL and development tools...
[... package installation output ...]

✓ System dependencies installed successfully!

🔧 Setting up PostgreSQL database...
Creating ThingDB database and user...

✓ PostgreSQL database configured!

⚠  Default database credentials:
    Database: thingdb
    User: thingdb
    Password: thingdb_default_pass

    CHANGE THIS PASSWORD IN PRODUCTION!

✓ Created .env file
⚠  Please edit .env and set a secure SECRET_KEY and POSTGRES_PASSWORD!

╔════════════════════════════════════════════════════════════════╗
║                 ✅ Installation Complete!                      ║
╚════════════════════════════════════════════════════════════════╝

Next steps:

1. Edit .env file:
   nano .env

2. Install ThingDB:
   pip install -e .

3. Initialize database:
   thingdb init

4. Start ThingDB:
   thingdb serve

5. Open browser:
   http://localhost:5000
```

---

## Error Handling

### If PostgreSQL is Missing

The script detects and installs it automatically.

### If pip install Fails

Common issues:
1. **No system dependencies** → Run `./install_system_deps.sh` first
2. **Python version** → Requires Python 3.9-3.13
3. **Network issues** → PyTorch download is ~500MB

### If Database Connection Fails

```bash
# Check PostgreSQL is running
sudo systemctl status postgresql

# Check .env file has correct credentials
cat .env

# Test connection
psql -h localhost -U thingdb -d thingdb
```

---

## Deployment Options

### Option 1: Git Clone (Recommended for Pi)
```bash
git clone https://github.com/yourusername/thingdb.git
cd thingdb
./install_system_deps.sh
pip install -e .
thingdb serve
```

### Option 2: Docker (No System Setup)
```bash
docker-compose -f docker/docker-compose.yml up -d
```

### Option 3: PyPI (Future)
Once published to PyPI:
```bash
# System deps still required
./install_system_deps.sh  # From downloaded script

# Then install from PyPI
pip install thingdb
thingdb serve
```

---

## File Structure

```
thingdb/
├── install_system_deps.sh      # System dependencies installer
├── pyproject.toml               # Python package metadata
├── setup.py                     # Compatibility shim
├── .env.example                 # Example configuration
├── README.md                    # User-facing guide
├── INSTALL.md                   # Detailed installation guide
├── INSTALLATION_STRATEGY.md     # This document
└── src/                         # Application code
```

---

## Success Metrics

✅ **Simple** - Three commands: script, pip, run
✅ **Automatic** - No manual PostgreSQL setup
✅ **Safe** - Detects existing installations
✅ **Clear** - Helpful error messages and next steps
✅ **Complete** - Includes all dependencies (no surprises)
✅ **Cross-platform** - Works on Debian/Ubuntu/Pi/macOS
✅ **Modern** - Python 3.13 compatible

---

## Summary

**Problem:** pip can't install system dependencies
**Solution:** Automated shell script + proper Python packaging
**Result:** Simple 3-step installation for any user

Users get:
1. Automated system setup
2. Complete ML functionality
3. Clear instructions
4. Works on fresh Raspberry Pi
5. No complex configuration

**Bottom line:** From zero to running ThingDB in 3 commands. 🚀

