# ThingDB Demo Databases

This directory contains pre-populated demo databases that help new users explore ThingDB features.

## 📦 What are Demo Databases?

Demo databases are `.zip` backup files that contain:
- Pre-configured items and hierarchies
- Sample images and photos
- Categories and tags
- Real-world organization examples

## 🚀 Using Demo Databases

### For End Users:
1. Navigate to **Admin → Backup & Restore**
2. Find the **📚 Demo Databases** section
3. Click **📥 Load Demo** on any available demo
4. The demo will replace your current database (backup first if needed!)

### For Developers:
Demo databases are automatically detected from `/var/lib/thingdb/demos/` on the server.

During installation, demo files from this Git directory are copied to the server's demo directory.

## 📝 Creating Your Own Demos

1. **Set up your example data** in a ThingDB instance
2. **Create a backup** via the Backup page
3. **Download the `.zip` file**
4. **Rename it descriptively** (e.g., `home_inventory_demo.zip`, `workshop_organization.zip`)
5. **Add it to this directory** in Git
6. **Update the installation script** to copy it during install

### Naming Convention:
- Use lowercase with underscores: `home_inventory_demo.zip`
- The UI will automatically convert to: "Home Inventory Demo"
- Keep filenames short and descriptive

## 📋 Available Demos

Currently, no demo databases are included in this repository. To add demos:

1. Create example content in ThingDB
2. Generate a backup
3. Place the `.zip` file in this directory
4. Commit to Git

## 🔧 Installation Script Integration

The `install.sh` script should be updated to:
```bash
# Copy demo databases if they exist
if [ -d "demos" ]; then
    mkdir -p /var/lib/thingdb/demos
    cp demos/*.zip /var/lib/thingdb/demos/ 2>/dev/null || true
fi
```

## ⚠️ Important Notes

- Demo databases **replace all existing data**
- Always backup your data before loading a demo
- Demos are great for:
  - First-time users learning the system
  - Screenshots and documentation
  - Testing features
  - Training sessions
  
- Demos are NOT for:
  - Production data
  - Sensitive information
  - Real inventory tracking

## 💡 Demo Ideas

Consider creating demos for:
- 🏠 **Home Inventory** - Living room, kitchen, garage organization
- 🔧 **Workshop Organization** - Tools, materials, project supplies
- 📚 **Book Collection** - Personal library with categories
- 🎮 **Game Collection** - Video games, board games
- 🍷 **Wine Cellar** - Wine inventory with ratings and locations
- 🎨 **Art Supplies** - Paints, brushes, canvases
- 🏕️ **Camping Gear** - Outdoor equipment organization

## 🤝 Contributing Demos

If you create a useful demo, consider contributing it back to the project!

1. Ensure it contains no personal/sensitive data
2. Use clear, descriptive item names
3. Include representative images (low-res, public domain)
4. Test the restore process
5. Submit a pull request with your demo and description

---

**Questions?** Check the main [README.md](../README.md) or [DEVELOPER.md](../DEVELOPER.md) for more information.



