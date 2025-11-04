# ThingDB - Smart Inventory Management

A powerful, searchable inventory system with semantic search, image support, and hierarchical organization. **Designed for Raspberry Pi 5.** 🐳 Docker coming soon.

## Features

- 🔍 **Semantic Search** - Find items by meaning, not just keywords
- 📸 **Image Management** - Multiple photos per item with automatic thumbnails
- 🏷️ **QR Code Labels** - Generate and scan QR codes for quick access
- 🌳 **Hierarchical Organization** - Organize items in nested categories
- 🔗 **Relationships** - Link related items together
- 💾 **Backup & Restore** - Protect your inventory data
- 📊 **Statistics** - View insights about your inventory
- 🐳 **Docker Ready** - Easy deployment with Docker Compose

## Super Quick Install (One Command!)

```bash
wget -qO- https://raw.githubusercontent.com/mcyork/thingdb/main/bootstrap.sh | bash
```

**That's it!** Visit `https://YOUR_IP:5000` 🎉

This downloads, installs, and starts ThingDB with HTTPS automatically. **Tested on Raspberry Pi 5.**

**Note:** You'll see a one-time certificate warning (self-signed cert) - just click through it.

**⚠️ Pi Zero 2 W:** Installs successfully but has significant memory limitations (512MB RAM). The ML semantic search features consume too much memory for long-term functionality. **Recommended: Pi 4 or Pi 5** with 2GB+ RAM.

**🐳 Docker:** Docker Compose configuration available but not yet tested. See [INSTALL.md](INSTALL.md) for Docker setup.

**See [INSTALL.md](INSTALL.md) for other installation options** (manual install, Docker, development setup, etc.)

---

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

---

## System Requirements

- **Python**: 3.9-3.13
- **PostgreSQL**: 12+
- **RAM**: 2GB minimum (4GB recommended for ML features)
- **Disk Space**: ~2GB (includes ML models)
- **Recommended Hardware**: Raspberry Pi 4 or Pi 5 (2GB+ RAM)
- **Tested Platforms**: 
  - ✅ Raspberry Pi 5 (fully tested, recommended)
  - ⚠️ Pi Zero 2 W (installs but 512MB RAM insufficient for ML features)
  - 🐳 Docker (configuration available, not yet tested)

---

## Service Management

Once installed, ThingDB runs as a systemd service:

```bash
# Check status
sudo systemctl status thingdb

# Start/stop/restart
sudo systemctl start thingdb
sudo systemctl stop thingdb
sudo systemctl restart thingdb

# View live logs
sudo journalctl -u thingdb -f

# Enable/disable auto-start on boot
sudo systemctl enable thingdb
sudo systemctl disable thingdb
```

The service automatically:
- ✅ Starts on system boot
- ✅ Restarts if it crashes
- ✅ Logs to system journal
- ✅ Runs as unprivileged user

---

## For Developers

Want to contribute, test experimental features, or understand internals?

See **[DEVELOPER.md](DEVELOPER.md)** for:
- Development branch access
- Architecture overview
- API endpoints
- Database schema
- Contributing guidelines
- Troubleshooting

## License

MIT License - see LICENSE file for details

## Support

- **Issues**: [GitHub Issues](https://github.com/mcyork/thingdb/issues)
- **Discussions**: [GitHub Discussions](https://github.com/mcyork/thingdb/discussions)


---

**ThingDB**: Know what you have, find what you need. 📦

