# Getting Started with Your Inventory System

## Quick Setup

### 1. First Boot
- Burn the downloaded image to an SD card  (Consider [Etcher](https://etcher.balena.io/) or [Raspberry Pi Imager](https://www.raspberrypi.com/software/))
> [!WARNING]  
> Do not use the Custom Settings options of the [Raspberry Pi Imager](https://www.raspberrypi.com/software/) - the image includes ssh and wifi configuration tools that conflict with the custom settings.

- Insert into your Pi and boot it up
- **Important**: Let the power light flicker until it stops - the image auto-expands to fill the SD card on first boot
- Once expansion is complete, you can safely power off anytime

- If on a prior RC run a backup - image sd card - restore back - yer on your way
- [RC7 image link](https://ln5.sync.com/dl/21dd9c9f0#2qw8wjmv-nd69at47-m6jk2wju-c8rhynd2)

### 2. Network Setup

**Ethernet (Easiest):**
- Plug in Ethernet cable
- Access via `https://inventory.local`

**WiFi (Using BTBerryWifi):**
- Download BTBerryWifi from the App Store
- Scan your network for "Inventory" device
- Follow prompts to scan for SSIDs and enter WiFi password
- Access via `https://inventory.local`

> **Note**: Don't rename the device through imaging tools or SSH - we've hardcoded the hostname in too many places. A rename function is coming soon.

## Basic Usage

### Adding Your First Item
- Click the **+** button in the top bar
- Add a title, description, and photos
- Use the **#** button to edit the item number (these auto-increment but you can customize them)

### Organizing Items
- Use **"Move Item"** to create hierarchies
- Create pseudo-locations like:
  - closet
  - office  
  - bedroom
  - garage
  - garage shelf
  - camping equipment

**Example**: Garage → shelf 2 → camping equipment

### Finding Items
- **List/Tree View**: Toggle in the homepage slider
- **Semantic Search**: The ML model finds items by meaning, not just keywords
  - Search "camping gear" → finds "sleeping bag, stove, picnic items"
  - More description = better search results
- **Hierarchy Navigation**: Click through location chains to find items

## Advanced Features

### QR Codes
- **Generate**: Admin page → "QR Code Generation" → downloads PDF
- **Use**: Stick QR codes on boxes/containers
- **Scan**: Use camera button on homepage → link to existing item or create new one
- **Already Linked**: If you scan a QR code that's already linked to an item, it opens that item directly
- **GUIDs**: Each QR code contains a unique GUIDv4 - every generated code is globally unique

### Photos & Media
- Take photos directly or upload from library
- **Show Controls** button: Delete and rotate images
- Camera permissions may prompt frequently (web app limitation)

### Tags & Descriptions
- **Tags**: Type and press Enter to add (used for search)
- **Descriptions**: Click pencil icon to edit
- **Pro tip**: Use voice-to-text tools like Wispr Flow for detailed descriptions

## Admin Features

### Database Management
- **Re-index All Embeddings**: Run this if semantic search isn't working well
- **Validate Database**: Basic integrity checks
- **Optimize Database**: May help with performance on large inventories
- **Clear Image Cache**: Clear cache if images are wrong or memory is full

### Backup & Restore
- **Highly recommended**: Regular backups via admin page
- Backups are forward-compatible
- If system crashes: re-image SD card → restore backup = full recovery
- Backups are stored in the file structure if you can mount the SD card

### Package Management (Updates)
**Essential buttons:**
- **Upload Package**: Upload update bundles
- **Install Package**: Install after validation (enabled after successful upload)
- **Restart Services**: Apply changes after installation

**Other buttons (debugging/experimental):**
- Rollback, Test API, Simple Test, Upgrade Status - mostly unused

### System Monitoring
- **System Stats**: Homepage overview
- **Inventory Stats**: Fun metrics about your collection
- **System Status**: Quick health check

## Troubleshooting

### Search Not Working?
- Try **Re-index All Embeddings** in admin
- Add more descriptive text to items

### Updates Not Showing?
- Click **Restart Services** after installing packages

### Camera Issues?
- Web app limitation - just allow camera when prompted

### Memory Problems?
- Try **Clear Image Cache** in admin
- Check System Stats for memory usage

## Item Management

### Editing
- **Title**: Click pencil icon next to title
- **Description**: Click pencil icon next to description  
- **Number**: Click # button to edit item number
- **Delete**: Red button at bottom 

### Navigation
- **Back button**: Returns to homepage or previous item
- **GUID**: Bottom gray text shows unique item identifier

---

**Need help?** Check the admin page system status or restart services if something seems off.

## Customization Ideas

**QR Code Hacks:**
- Print QR codes on labels/stickers for easy application
- Create themed QR code sheets (e.g., "Garage Items", "Office Supplies")
- Use different colored labels to match item categories
- Generate QR codes for locations (not just items) to quickly navigate hierarchies

**Workflow Tips:**
- Use voice-to-text tool [Wispr Flow](https://wisprflow.ai/) for detailed descriptions
- Take photos from multiple angles for better future recognition
- Use the item numbers (#) as physical labels on containers

**Organization Strategies:**
- Use tags for cross-category organization (e.g., "valuable", "fragile")
- Set up location-based pseudo-items as your main organization structure
- Create "maintenance" items for things that need regular attention

**Pro Tips:**
- The more descriptive text you add, the better semantic search works
- Regular backups are your friend - especially before major reorganizations
- Use the tree view to see your full organization structure at a glance
