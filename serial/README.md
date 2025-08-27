# Pi Serial Agent - Remote Installer

This folder contains a remote installer for the Pi Serial Agent using the `pi` CLI tool. It provides a reliable serial console fallback on any Raspberry Pi without requiring direct SSH access.

## What It Does

- **Enables UART** at 9600 baud on the hardware serial port
- **Installs serial agent** as a systemd service
- **Provides fallback access** when SSH/network is unavailable
- **Executes commands** over serial connection
- **Remote installation** using pi CLI tool

## Prerequisites

- **pi CLI tool** installed and configured
- **Default Pi set** in pi-shell configuration
- **SSH access** to the target Pi (for initial installation)

## Quick Install

1. **From your Mac**, run the installer:
   ```bash
   ./install-serial-agent.sh
   ```
2. **The script will**:
   - Detect your default Pi from pi-shell
   - Transfer the serial agent package
   - Install it remotely using sudo
3. **Reboot the Pi** to activate UART:
   ```bash
   pi run --pi <pi_name> 'sudo reboot'
   ```

## What Gets Installed

- UART configuration in `/boot/firmware/config.txt`
- Serial agent service (`serial-agent@ttyAMA0.service`)
- Hardware serial port enabled at `/dev/ttyAMA0`

## Testing the Serial Agent

After reboot, you can test the serial communication:

### Option 1: Use Serial Bridge Tool
```bash
# From the pi-serial project directory
./scripts/serial_bridge run --port_name pi_console "echo hello"
```

### Option 2: Use Terminal Software
- Connect at 9600 baud
- Send commands like `echo hello` or `ls -la`
- The agent will execute and return results

## When to Use

- **Before network changes** that might break SSH
- **During early Pi setup** when networking isn't configured
- **As a fallback** when SSH becomes unavailable
- **For debugging** network configuration issues

## Files

- `pi-serial-agent.tar.gz` - Complete serial agent package
- `install-serial-agent.sh` - Remote installer script using pi CLI
- `README.md` - This documentation

## Notes

- **Remote installation** - no need to manually SSH to the Pi
- **Uses pi CLI tool** - automatically detects and connects to your Pi
- **UART set to 9600 baud** - standard for reliable communication
- **Service starts automatically** on boot
- **No manual configuration** required
