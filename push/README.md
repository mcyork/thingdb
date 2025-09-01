# Push Directory - Rapid Development Workflow

This directory contains scripts for rapid development iteration with your Raspberry Pi. These tools allow you to quickly push code changes to the Pi and restart the application for immediate testing.

## Overview

The push workflow is designed for rapid development iteration after the base Pi setup is complete. It provides multiple ways to deploy code changes:

1. **Full source push** - Push entire src directory
2. **Single file push** - Push individual files
3. **Watch and push** - Automatically push on file changes
4. **Status checking** - Monitor application health

## Scripts

### 1. `push-source.sh` - Full Source Push
Pushes the entire `src` directory to the Pi and restarts the application.

```bash
# Push all source files
./push/push-source.sh
```

**What it does:**
- Creates a compressed archive of the src directory
- Excludes unnecessary files (__pycache__, .pyc, logs, etc.)
- Stops the inventory-app service
- Deploys the archive to `/var/lib/inventory/app/`
- Restarts the service
- Shows service status

### 2. `push-file.sh` - Single File Push
Pushes a single file to the Pi for quick iteration.

```bash
# Push a specific file
./push/push-file.sh src/main.py
./push/push-file.sh src/routes/inventory.py
```

**What it does:**
- Validates the file is in the src directory
- Stops the inventory-app service
- Pushes the file to the correct location on Pi
- Restarts the service
- Shows service status

### 3. `watch-and-push.sh` - Automatic File Watching
Watches for file changes and automatically pushes them to the Pi.

```bash
# Start watching for changes (requires fswatch)
./push/watch-and-push.sh
```

**Requirements:**
- Install fswatch: `brew install fswatch`

**What it does:**
- Monitors the src directory for file changes
- Automatically pushes changed files to the Pi
- Restarts the service after each push
- Skips cache files and logs

### 4. `status.sh` - Application Status
Quickly check the status of your application on the Pi.

```bash
# Check application status
./push/status.sh
```

**What it shows:**
- Service status (active/inactive)
- Recent application logs
- Application directory contents
- Running processes

## Configuration

All scripts use these default settings:
- **Pi Name**: `pi1` (default Pi)
- **App Directory**: `/var/lib/inventory/app`
- **Service Name**: `inventory-app`
- **Local Source**: `src/` directory

To change these settings, edit the variables at the top of each script.

## Prerequisites

1. **Pi CLI Tool**: Must be installed and configured
2. **Pi Online**: Target Pi must be online and accessible
3. **Application Deployed**: Full application must be deployed first
4. **fswatch** (for watch-and-push): `brew install fswatch`

## Usage Examples

### Development Workflow

```bash
# 1. Make changes to your code in src/
# 2. Push changes to Pi
./push/push-file.sh src/main.py

# 3. Check if it's working
./push/status.sh

# 4. Or push all changes at once
./push/push-source.sh
```

### Continuous Development

```bash
# Start watching for changes (in one terminal)
./push/watch-and-push.sh

# Make changes in your editor (changes auto-push)
# Check status in another terminal
./push/status.sh
```

### Troubleshooting

```bash
# Check if Pi is online
pi status pi1

# Check application status
./push/status.sh

# Check service logs
pi run --pi pi1 "sudo journalctl -u inventory-app -f"
```

## File Structure

```
push/
├── push-source.sh      # Push entire src directory
├── push-file.sh        # Push single file
├── watch-and-push.sh   # Auto-push on file changes
├── status.sh           # Check application status
└── README.md           # This documentation
```

## Best Practices

1. **Use push-file.sh** for quick iterations on single files
2. **Use push-source.sh** when making changes to multiple files
3. **Use watch-and-push.sh** for continuous development
4. **Always check status.sh** after pushing to verify deployment
5. **Keep your src/ directory clean** - exclude unnecessary files

## Integration with Other Tools

These push scripts work alongside your other development tools:

- **install script**: For component deployment
- **deploy scripts**: For full system deployment
- **serial bridge**: For debugging and testing
- **pi CLI**: For general Pi management

## Troubleshooting

### Common Issues

**Service won't start:**
```bash
# Check logs
./push/status.sh

# Check file permissions
pi run --pi pi1 "ls -la /var/lib/inventory/app/"
```

**File not found:**
```bash
# Verify file exists locally
ls -la src/your-file.py

# Check Pi app directory
pi run --pi pi1 "ls -la /var/lib/inventory/app/"
```

**Permission denied:**
```bash
# Check file ownership on Pi
pi run --pi pi1 "sudo chown -R inventory:inventory /var/lib/inventory/app/"
```

This push workflow enables rapid development iteration, making it easy to test changes quickly without the overhead of full deployment.
