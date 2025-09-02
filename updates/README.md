# Inventory System Update Package System

This directory contains the update package system for the inventory application, including package creation, signing, and recovery mechanisms.

## Directory Structure

```
updates/
├── README.md                           # This file
├── UPGRADE_FLAG_PROTOCOL.md           # Upgrade flag protocol specification
├── build-update.sh                    # Package builder script (Mac side)
├── inventory-recovery                 # Recovery service script (Pi side)
├── inventory-recovery.service         # Systemd service file
├── signing-certs-and-root/            # Certificate directory
│   ├── root-ca.crt                    # Root CA certificate
│   ├── intermediate-ca.crt            # Intermediate CA certificate
│   └── intermediate-ca.key            # Intermediate CA private key
└── packages/                          # Generated packages
    ├── inventory-v1.1.0-bundle.tar.gz # Example update bundle
    └── ...
```

## Overview

The update system provides secure, signed package updates with automatic rollback capabilities:

1. **Package Creation**: Build signed update packages on Mac
2. **Package Upload**: Upload packages via admin interface
3. **Package Validation**: Verify signatures against embedded certificates
4. **Safe Installation**: Install with automatic rollback on failure
5. **Recovery Service**: Independent service monitors upgrade progress

## Mac Side (Package Creation)

### Prerequisites
- OpenSSL for signing
- Git for version detection
- Intermediate CA certificate and key

### Creating Update Packages

```bash
# Build package with auto-detected version
./updates/build-update.sh

# Build package with specific version
./updates/build-update.sh 1.1.0
```

### Package Contents
- **Source code**: Complete `src/` directory (148KB zipped)
- **Manifest**: Package metadata and upgrade steps
- **Signature**: Cryptographic signature for authenticity

## Pi Side (Package Installation)

### Recovery Service
- **Independent service**: Runs separately from main app
- **Boot-level recovery**: Can recover from failed upgrades
- **Continuous monitoring**: Checks upgrade flags every 30 seconds
- **Automatic rollback**: Restores previous version on failure

### Upgrade Flag Protocol
- **Rich state tracking**: Monitors upgrade progress
- **Restart counting**: Handles multiple service restarts
- **Timeout protection**: Automatic rollback after expected restarts
- **Step tracking**: Detailed upgrade step monitoring

## Security Model

### Certificate Chain
```
Root CA (TPM-secured Pi)
    ↓
Intermediate CA (Mac-based)
    ↓
Package Signatures
```

### Validation Process
1. **Package signature**: Verified against intermediate CA
2. **Certificate chain**: Validated against embedded root CA
3. **Package integrity**: SHA256 hash verification
4. **Version checking**: Prevents downgrades

## Upgrade Process

### Standard Upgrade Steps
1. **Backup**: Create backup of current version
2. **Extract**: Extract new package
3. **Install Dependencies**: Update Python packages
4. **Restart Service**: Restart inventory-app service
5. **Validate**: Run health checks
6. **Cleanup**: Remove backup if successful

### Rollback Scenarios
- **Upgrade timeout**: Too many restarts
- **Service failure**: Main app won't start
- **Validation failure**: Health checks fail
- **Manual rollback**: User-initiated rollback

## Admin Interface Integration

### Upload Package
- **File upload**: Upload signed package bundle
- **Validation**: Verify signature and manifest
- **Installation**: Safe package installation

### System Status
- **Current version**: Display installed version
- **Upgrade status**: Show upgrade progress
- **Rollback option**: Manual rollback button

### Package Management
- **Version history**: Track installed versions
- **Rollback safety**: Show rollback compatibility
- **Update notifications**: Check for new versions

## Development Workflow

### Creating Updates
1. **Make changes**: Modify source code
2. **Test locally**: Verify changes work
3. **Build package**: Run `build-update.sh`
4. **Test package**: Upload to test Pi
5. **Deploy**: Distribute to production

### Testing Updates
1. **Upload package**: Via admin interface
2. **Monitor progress**: Watch upgrade steps
3. **Verify functionality**: Test all features
4. **Rollback if needed**: Use rollback button

## Troubleshooting

### Common Issues
- **Signature validation fails**: Check certificate chain
- **Upgrade timeout**: Increase restart counter
- **Rollback fails**: Check backup directory
- **Service won't start**: Check logs and dependencies

### Recovery Options
- **Automatic rollback**: Recovery service handles it
- **Manual rollback**: Use admin interface
- **Boot recovery**: Recovery service runs on boot
- **Emergency recovery**: SSH access for manual fix

## Future Enhancements

### Planned Features
- **Delta packages**: Only changed files (if needed)
- **Database migrations**: Schema update support
- **Rollback safety**: Advanced compatibility checking
- **Update notifications**: Automatic update checking
- **Package repository**: Centralized package storage
