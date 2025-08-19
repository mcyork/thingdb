# Flask Inventory Management System - Development Context

## Project Overview
This is a Flask-based inventory management system with Docker containerization, designed for tracking physical items with QR codes, images, and hierarchical relationships.

## Architecture
- **Backend**: Flask with PostgreSQL database
- **Frontend**: HTML templates with JavaScript
- **Infrastructure**: Docker containers (Flask app + Nginx proxy)
- **Storage**: PostgreSQL with image data stored as BYTEA

## Key Features
- **QR Code Scanning**: Camera-based QR code scanner with flashlight support
- **Hierarchical Items**: Items can contain other items (parent-child relationships)
- **Image Management**: Multiple images per item with thumbnails and rotation
- **Search**: Both traditional and semantic search capabilities
- **Tree/List Views**: Toggle between flat list and hierarchical tree view

## Recent Development Work

### Session 1: Move Function Bug Fix (2025-08-15)
**Problem**: Move item functionality was broken after refactoring from app.py to modular structure
**Root Cause**: Frontend JavaScript had mismatched URLs and data formats from old code
**Solution**: Fixed in `src/templates/item.html`
- Changed `/set-parent-item/` to `/set-parent/` (URL mismatch)
- Changed `/remove-parent-item/` calls to use `/set-parent/` with empty parent_guid
- Changed FormData to JSON format to match backend expectations

**Files Modified**: `src/templates/item.html`
**Commit**: `e872893` - "Fix broken move item functionality"

### Session 2: Manual Item Creation & QR Association (2025-08-15)

#### Feature 1: Plus Sign Button
**Purpose**: Allow manual item creation without QR scanning
**Implementation**: 
- Added ➕ button next to camera icon in home page header
- Calls `/create-item` endpoint via JavaScript
- Generates items with timestamp-based names
- Navigates directly to new item page for editing

**Files Modified**: `src/templates/home.html`
**Commit**: `2b1441d` - "Add manual item creation with plus sign button"

#### Feature 2: QR Code Association Dialog
**Purpose**: Handle multiple QR codes per physical item (e.g., box with codes on different sides)
**Problem Solved**: Previously, scanning new QR codes auto-created duplicate items
**Solution**: 
- Show association dialog when new QR code is scanned
- Options: "Associate with existing item" / "Create new item" / "Cancel"
- Uses `qr_aliases` table to map multiple QR codes to single items
- Subsequent scans of associated QR codes redirect directly to target item

**Technical Changes**:
- Modified `/process-guid` in `src/routes/core_routes.py` to create temporary items and show dialog
- Added `/associate-item/<guid>` endpoint in `src/routes/relationship_routes.py`
- Leveraged existing association banner UI in `item.html`

**Database Schema**: 
- `qr_aliases` table: `qr_code` → `item_guid` mapping
- Allows one-to-many relationship (multiple QR codes per item)

**Workflow**:
1. Scan new QR code → temporary item created → association dialog shown
2. User chooses "Associate" → search existing items → create QR alias → delete temp item
3. User chooses "Create new" → dismiss dialog → keep as new item
4. Future scans → direct redirect to associated item

**Files Modified**: `src/routes/core_routes.py`, `src/routes/relationship_routes.py`
**Commit**: `d8f3f83` - "Implement QR code association dialog for multiple QR codes per item"

## Database Schema (Key Tables)
- **items**: Main inventory items (guid, item_name, description, parent_guid, label_number, etc.)
- **images**: Item photos with thumbnails (linked to items via item_guid)
- **qr_aliases**: QR code to item mappings (qr_code → item_guid)
- **categories**: Item tags/categories

## Development Environment
- **Start**: `./scripts/start-dev.sh`
- **Build**: `./scripts/build-dev.sh`
- **Access**: https://localhost (with self-signed SSL)
- **Database**: PostgreSQL in Docker container

## Code Structure
- **Main App**: `src/main.py` (refactored from monolithic `src/app.py.old`)
- **Routes**: Modular blueprints in `src/routes/`
  - `core_routes.py`: Home page, item detail, GUID processing
  - `item_routes.py`: Item CRUD operations, parent/child relationships
  - `relationship_routes.py`: Item relationships, move operations, QR associations
  - `search_routes.py`: Search functionality
  - `image_routes.py`: Image upload/management
  - `admin_routes.py`: System administration
- **Templates**: `src/templates/` (Jinja2 HTML templates)
- **Utils**: `src/utils/helpers.py` (validation, GUID generation, etc.)

## Testing Commands
- **Move Item**: Test via item page search box → select parent → move
- **Manual Creation**: Click ➕ button on home page
- **QR Association**: Scan new QR code → see dialog → test both "associate" and "create new" paths
- **Database**: `docker-compose -f docker/docker-compose-dev.yml exec flask-app psql -U docker -d docker_dev`

## Known Working Features
- ✅ QR Code scanning with camera
- ✅ Item creation (manual and QR-based)
- ✅ Item relationships (parent/child, moving items)
- ✅ QR code association (multiple QR codes per item)
- ✅ Image upload and management
- ✅ Search (traditional and semantic)
- ✅ Tree/List view toggle

## Development Notes
- Frontend uses JavaScript fetch API with JSON format for most operations
- Backend expects `request.json` for POST operations (not FormData)
- QR scanner optimized for small QR codes with focus adjustments
- Association dialog leverages existing UI components for consistency
- All database operations use connection pooling via `src/database.py`

## Future Considerations
- Embedding generation is skipped for faster item creation (can be added later)
- Association dialog could be enhanced with more sophisticated search/filtering
- Consider adding batch QR association operations
- Might want to add QR alias management UI for administrators