# Interactive Installer for Raspberry Pi Components

This interactive installer provides a simple way to deploy different components to your Raspberry Pi without remembering complex commands.

## Quick Start

Just run the installer from your project root:

```bash
./install
```

## What It Does

The installer provides a menu-driven interface for:

1. **Deploy Serial Agent** - Installs the serial communication agent for UART communication
2. **Deploy Network Components** - Installs BTBerryWifi network management 
3. **Deploy Application** - Deploys the full inventory application
4. **Show Status** - Shows current system status and available components
5. **Quick Deploy (Serial + Network)** - Installs both serial and network components in sequence
6. **Reboot Pi** - Safely reboots the Raspberry Pi (useful after installing components that require reboot)
7. **Exit** - Quits the installer

## Use Cases

### Development Workflow
- **Build multiple SD cards** with just serial components for testing
- **Add networking** to any card when you need WiFi/Bluetooth management
- **Deploy the app** to any card when ready for full testing

### Quick Setup
- **Quick Deploy option** installs both serial and network components in one go
- Perfect for setting up a new SD card with basic functionality
- Reduces the number of menu selections needed

### System Management
- **Reboot option** for when components require a restart to take effect
- Especially useful after installing serial agent (UART configuration)
- Safe reboot with confirmation prompt

### SD Card Management
- **Serial-only cards**: For hardware testing without network complexity
- **Network-enabled cards**: For remote management and WiFi configuration  
- **Full application cards**: For complete system testing

## Prerequisites

- `pi` CLI tool installed and configured with a default Pi
- Your Raspberry Pi must be online and accessible
- For application deployment: run `./deploy/deploy-prepare-clean.sh` first

## How It Works

The installer:
1. Checks if your Pi is online and ready
2. Runs the appropriate installation scripts from the `serial/`, `network/`, and `deploy/` directories
3. Provides clear feedback and error messages
4. Handles dependencies automatically

## Example Session

```
$ ./install

Raspberry Pi Component Installer
================================
Choose what you want to install:
1. Deploy Serial Agent
2. Deploy Network Components
3. Deploy Application
4. Show Status
5. Exit

Enter your choice (1-5): 1

Deploying Serial Agent
======================
[SUCCESS] Pi status: Pi 'pi2' is online
[INFO] Running serial agent installation...
[SUCCESS] Serial agent deployment completed!
```

## Troubleshooting

- **"pi CLI tool not found"**: Install the pi-shell tool first
- **"Pi is not ready"**: Check your Pi's network connection and pi CLI configuration
- **"Deployment package not found"**: Run `./deploy/deploy-prepare-clean.sh` first
- **Script not found errors**: Make sure you're running from the project root directory

## File Structure

```
inv2-dev/
├── install                    # This interactive installer
├── serial/                    # Serial agent installation scripts
├── network/                   # Network component scripts  
├── deploy/                    # Application deployment scripts
└── INSTALL_README.md         # This documentation
```

## Benefits

- **Reduces friction** during development and testing
- **Standardizes deployment** across multiple SD cards
- **Clear feedback** on what's happening and what's needed
- **Handles dependencies** automatically
- **Easy to use** - just one command to remember
