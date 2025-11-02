# ThingDB - Master Goal & Renovation Plan

## Project Vision
A simplified, pip-installable inventory management system with semantic search and image support.

## Primary Objectives

### 1. **Simplification & Feature Removal**
The current goal is **NOT** to add features, but to **remove complexity** and simplify installation:

- **Remove Cloudflare Integration**
  - All Cloudflare tunnel/access capabilities
  - Remote access features that depend on Cloudflare
  - Associated configuration and setup scripts

- **Remove Network Deployment Features**
  - Network-based installation scripts
  - Remote deployment mechanisms
  - Network-specific configuration tools

- **Remove Serial Deployment**
  - All serial port communication scripts
  - Serial-based installation mechanisms
  - Serial configuration utilities

- **Remove Bluetooth Features**
  - Bluetooth WiFi configuration services
  - BLE-related setup tools
  - Associated dependencies

- **Remove Pi-Specific Image Building**
  - Custom Pi image generation tools
  - Pi-gen and CustomPiOS integration
  - SD card image creation scripts

### 2. **Core Functionality to Retain**
Keep the essential inventory application features:

- ✅ Web-based inventory UI
- ✅ Semantic search capabilities
- ✅ Image upload and management (stored in database)
- ✅ Item relationships
- ✅ Database backup/restore
- ✅ QR code generation and printing
- ✅ Admin interface
- ✅ Docker deployment option

### 3. **Installation Strategy**
- **Ultimate Goal**: `pip install thingdb` or `pip install .`
- **Approach**: Standard Python package distribution
- **Remove**: PyShell-based installation (for end users)
- **Keep**: PyShell for development/testing purposes only
- **Simplify**: Eliminate complex deployment scripts

### 4. **Code Organization**
- **Active Code**: Keep in standard project structure (`src/`, `docker/`, etc.)
- **Deprecated Code**: Move to `aaa/` folder for eventual deletion
- **Reference**: Original project copy exists as backup

## Cleanup Strategy

### Files/Folders to Move to `aaa/`:
1. `cloudflare/` - Entire directory
2. `pi-setup/` - Pi-specific setup scripts
3. `pi-image-builder/` - Custom OS image generation
4. `network/` - Network deployment scripts
5. `serial/` - Serial communication tools
6. `deploy/` - Complex deployment scripts (keep simple ones)
7. `push/` - File push utilities
8. `token_tests/` - Cloudflare token testing
9. `signing-cert-key/`, `signing-certs-and-root/` - Certificate signing infrastructure
10. `updates/` - Update distribution system
11. `fix-tunnel-reset.sh`, `fix-ssh-keys.sh` - Cloudflare/network-specific
12. `CF.md` - Cloudflare documentation
13. `src/routes/remote_access_routes.py` - Cloudflare remote access
14. `src/services/package_verification_service.py` - Update package verification

### Files to Keep:
1. `src/` - Core application (minus remote_access_routes.py)
2. `docker/` - Docker deployment
3. `requirements/` - Python dependencies
4. `scripts/` - Useful utility scripts (review individually)
5. `tools/` - Development tools/docs
6. Documentation files describing the core functionality

## Success Criteria
- [ ] Application runs with simple `pip install` or Docker
- [ ] No Cloudflare dependencies
- [ ] No network/serial installation complexity
- [ ] All core inventory features functional
- [ ] Clean, maintainable codebase
- [ ] Clear documentation for basic setup

## Development Tools (Keep)
- PyShell - For testing and debugging
- Docker - For containerized deployment
- Standard Python tooling

---
**Note**: This is a simplification project. We're removing features that made installation complex while keeping the core value: a powerful, searchable inventory system with image support.

