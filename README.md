# ThingDB - Smart Inventory Management

A powerful, searchable inventory system with semantic search, image support, and hierarchical organization.

## Features

- 🔍 **Semantic Search** - Find items by meaning, not just keywords
- 📸 **Image Management** - Multiple photos per item with automatic thumbnails
- 🏷️ **QR Code Labels** - Generate and scan QR codes for quick access
- 🌳 **Hierarchical Organization** - Organize items in nested categories
- 🔗 **Relationships** - Link related items together
- 💾 **Backup & Restore** - Protect your inventory data
- 📊 **Statistics** - View insights about your inventory
- 🐳 **Docker Ready** - Easy deployment with Docker Compose

## Quick Start

### ⚡ Super Quick Install (One Command!)

```bash
wget -qO- https://raw.githubusercontent.com/mcyork/thingdb/main/bootstrap.sh | bash
```

**That's it!** Visit `https://YOUR_IP:5000` 🎉

This downloads, installs, and starts ThingDB with HTTPS automatically. Works on Raspberry Pi, Ubuntu, Debian, and macOS.

**Note:** You'll see a one-time certificate warning (self-signed cert) - just click through it.

**See [INSTALL.md](INSTALL.md) for other installation options** (manual install, Docker, development setup, etc.)

---

## 🧪 Development Branch (Bleeding Edge)

Want to test new features before they're released? Use the `dev` branch:

```bash
# Dev branch one-liner:
wget -qO- https://raw.githubusercontent.com/mcyork/thingdb/dev/bootstrap.sh | bash
```

Or manual install:
```bash
wget https://github.com/mcyork/thingdb/archive/refs/heads/dev.zip
unzip dev.zip
cd thingdb-dev
./install.sh
```

**Note:** Dev branch may have experimental features. Use `main` branch for stability.

---

## Service Management (Linux/Raspberry Pi)

Once installed with `./install.sh`, ThingDB runs as a systemd service:

```bash
# Check status
sudo systemctl status thingdb

# Start service
sudo systemctl start thingdb

# Stop service
sudo systemctl stop thingdb

# Restart service
sudo systemctl restart thingdb

# View live logs
sudo journalctl -u thingdb -f

# Disable auto-start on boot
sudo systemctl disable thingdb

# Enable auto-start on boot
sudo systemctl enable thingdb
```

The service automatically:
- ✅ Starts on system boot
- ✅ Restarts if it crashes
- ✅ Logs to system journal
- ✅ Runs as unprivileged user

## Requirements

### System Requirements
- **Python**: 3.9-3.13
- **PostgreSQL**: 12+
- **RAM**: 2GB minimum (4GB recommended for ML features)
- **Disk Space**: ~2GB (includes ML models)
- **OS**: Linux (Debian/Ubuntu/Raspberry Pi OS), macOS

### Automatic Installation
The `install_system_deps.sh` script handles all system dependencies automatically.
No manual PostgreSQL setup required!

## Configuration

Create a `.env` file in the root directory:

```bash
# Database Configuration
POSTGRES_HOST=localhost
POSTGRES_PORT=5432
POSTGRES_DB=inventory_db
POSTGRES_USER=inventory
POSTGRES_PASSWORD=your_secure_password

# Flask Configuration
FLASK_DEBUG=0
SECRET_KEY=your_secret_key_here

# Optional: External PostgreSQL
# EXTERNAL_POSTGRES_HOST=your_external_host
# EXTERNAL_POSTGRES_DB=inventory_db
# EXTERNAL_POSTGRES_USER=inventory
# EXTERNAL_POSTGRES_PASSWORD=secure_password
```

## Usage

### Adding Items

1. Click the **+** button to create a new item
2. Add a title, description, and photos
3. Optionally scan or generate a QR code

### Organizing Items

- Use **"Move Item"** to create hierarchies
- Create locations like "Garage → Shelf 2 → Box A"
- Items can have parent-child relationships

### Searching

- **Semantic Search**: Natural language queries
  - "camping gear" → finds sleeping bags, stoves, etc.
  - More detailed descriptions = better results
- **Tree/List View**: Toggle between flat and hierarchical views
- **QR Codes**: Scan codes to jump directly to items

### Backup & Restore

- Visit the **Admin Panel** → **Backup & Restore**
- Create backups before major changes
- Restore from previous backups if needed

## Architecture

```
thingdb/
├── src/
│   ├── main.py              # Flask application entry point
│   ├── config.py            # Configuration settings
│   ├── database.py          # Database connection
│   ├── models.py            # Data models
│   ├── routes/              # API routes
│   │   ├── core_routes.py
│   │   ├── item_routes.py
│   │   ├── search_routes.py
│   │   └── ...
│   ├── services/            # Business logic
│   │   ├── embedding_service.py
│   │   ├── image_service.py
│   │   └── ...
│   └── templates/           # HTML templates
├── docker/                  # Docker configuration
├── requirements/            # Python dependencies
└── scripts/                 # Utility scripts
```

## Database Schema

### Core Tables

- **items**: Main inventory items (GUID, name, description, parent)
- **images**: Item photos with thumbnails
- **qr_aliases**: QR code to item mappings
- **categories**: Tags and categories
- **embeddings**: Semantic search vectors

## Development

### Running Tests

```bash
# Test the application
python -m pytest tests/

# Check linting
flake8 src/

# Type checking
mypy src/
```

### Building for Production

```bash
# Build Docker image
docker build -f docker/Dockerfile -t thingdb:latest .

# Run production
docker-compose -f docker/docker-compose-prod.yml up -d
```

## API Endpoints

### Items

- `GET /` - Home page with item list
- `GET /item/<guid>` - Item detail page
- `POST /api/create-item` - Create new item
- `PUT /api/update-item/<guid>` - Update item
- `DELETE /api/delete-item/<guid>` - Delete item

### Search

- `GET /api/search?q=<query>` - Semantic search
- `GET /api/search?traditional=<query>` - Traditional search

### Images

- `POST /api/upload-image` - Upload item image
- `GET /api/image/<guid>` - Get full image
- `GET /api/thumbnail/<guid>` - Get thumbnail

### Admin

- `GET /admin` - Admin panel
- `POST /api/reindex-embeddings` - Regenerate search indexes
- `POST /api/optimize-database` - Database maintenance
- `GET /backup` - Backup management

## Semantic Search

ThingDB uses [sentence-transformers](https://www.sbert.net/) for semantic search:

- **Model**: `all-MiniLM-L6-v2` (80MB)
- **Vector Size**: 384 dimensions
- **Search Method**: Cosine similarity
- **Performance**: Sub-second searches on 10,000+ items

The better your item descriptions, the better the search results!

## Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## License

MIT License - see LICENSE file for details

## Support

- **Issues**: [GitHub Issues](https://github.com/mcyork/thingdb/issues)
- **Discussions**: [GitHub Discussions](https://github.com/mcyork/thingdb/discussions)

## Roadmap

- [ ] PyPI package distribution (`pip install thingdb`)
- [ ] Mobile app (iOS/Android)
- [ ] Multi-user support
- [ ] Advanced reporting
- [ ] Import/Export (CSV, JSON)
- [ ] API authentication
- [ ] Barcode support

---

**ThingDB**: Know what you have, find what you need. 📦

