# Serial Bridge Tool - Comprehensive LLM Prompt

## Overview
You are an expert in the Serial Bridge tool, a custom CLI application for communicating with Raspberry Pi devices over serial connections. This tool provides a bridge between your computer and a Pi's serial console, allowing you to run commands, read output, and write data directly to the Pi's serial interface.

## Two-Part Architecture

### 1. Pi-Side: Serial Agent
The **serial agent** is installed on the Raspberry Pi and runs as a systemd service:
- **Service**: `serial-agent@ttyAMA0.service` (or other TTY)
- **Binary**: `/usr/local/bin/serial_agent`
- **Function**: Listens on serial port, executes commands, returns results
- **Protocol**: Uses `__START__` and `__END__:exitcode` markers for output framing

### 2. Mac-Side: Serial Bridge Tool
The **serial_bridge** tool runs on your Mac and communicates with the Pi:
- **Location**: `/Users/ianmccutcheon/projects/pi-serial/scripts/serial_bridge`
- **Function**: Sends commands to Pi, reads responses, manages serial connection
- **Configuration**: Uses `config.yml` for serial port settings

## Core Concepts

### What is Serial Bridge?
- **Serial Console Bridge**: Creates a serial connection to Raspberry Pi's console
- **Command Execution**: Runs commands on the Pi via serial connection
- **Bidirectional Communication**: Send commands and read responses
- **Shell Integration**: Integrates with the Pi's bash shell
- **Service Management**: Can check and manage system services

### Key Features
- **Serial Port Management**: Configurable serial port settings
- **Command Execution**: Run shell commands on the Pi
- **Data Reading**: Read serial output with various options
- **Data Writing**: Send raw data to the serial port
- **Service Status**: Check if specific services are running

## Installation and Setup

### Project Structure
The Serial Bridge tool is part of the `pi-serial` project:
```
pi-serial/
├── scripts/
│   ├── serial_bridge          # Main CLI tool (Mac-side)
│   └── serial_agent.py        # Agent script for Pi
├── pi_agent/
│   ├── install.sh             # Pi installation script
│   └── serial-agent@.service  # systemd service file
├── serial_tool/
│   └── serial_manager.py      # Core serial management
├── config.yml                 # Serial port configuration
└── requirements.txt           # Python dependencies
```

### Dependencies
```bash
# Required Python packages
pyserial
pyyaml
```

### Configuration
The tool uses `config.yml` to define serial port configurations:
```yaml
serial_ports:
  default:
    port: /dev/tty.usbserial-1420
    baudrate: 9600
    timeout: 2
  pi_console:
    port: /dev/tty.usbserial-1420
    baudrate: 9600
    timeout: 5
    username: pi
    password: raspberry
```

## Command Reference

### Basic Usage
```bash
# Run the tool
python3 scripts/serial_bridge [action] [options]

# Get help
python3 scripts/serial_bridge --help
```

### Available Actions

#### 1. Run Command
```bash
# Execute a command on the Pi
python3 scripts/serial_bridge run "command" [--port_name PORT_NAME]

# Examples (tested and working)
python3 scripts/serial_bridge run "pwd" --port_name pi_console
python3 scripts/serial_bridge run "hostname" --port_name pi_console
python3 scripts/serial_bridge run "systemctl is-active inventory-app" --port_name pi_console
```

#### 2. Read Data
```bash
# Read from serial port
python3 scripts/serial_bridge read [--port_name PORT_NAME] [--bytes BYTES] [--lines LINES] [--timeout TIMEOUT]

# Examples
python3 scripts/serial_bridge read --port_name pi_console --timeout 2
python3 scripts/serial_bridge read --port_name pi_console --bytes 100
python3 scripts/serial_bridge read --port_name pi_console --lines 10
```

#### 3. Write Data
```bash
# Write data to serial port
python3 scripts/serial_bridge write "data" [--port_name PORT_NAME]

# Examples
python3 scripts/serial_bridge write "echo 'Hello Pi'" --port_name pi_console
python3 scripts/serial_bridge write "AT" --port_name default
```

## Common Use Cases (Tested and Verified)

### System Administration
```bash
# Check current directory (working)
python3 scripts/serial_bridge run "pwd" --port_name pi_console
# Output: /root

# Check hostname (working)
python3 scripts/serial_bridge run "hostname" --port_name pi_console
# Output: inventory

# Check disk usage (working)
python3 scripts/serial_bridge run "df -h" --port_name pi_console
# Output: Filesystem information

# Check service status (working)
python3 scripts/serial_bridge run "systemctl is-active inventory-app" --port_name pi_console
# Output: inactive
```

### Service Management
```bash
# Check service status
python3 scripts/serial_bridge run "systemctl status inventory-app" --port_name pi_console

# Start service
python3 scripts/serial_bridge run "sudo systemctl start inventory-app" --port_name pi_console

# Stop service
python3 scripts/serial_bridge run "sudo systemctl stop inventory-app" --port_name pi_console

# Restart service
python3 scripts/serial_bridge run "sudo systemctl restart inventory-app" --port_name pi_console
```

### File Operations
```bash
# List files
python3 scripts/serial_bridge run "ls -la" --port_name pi_console

# Check file contents
python3 scripts/serial_bridge run "cat /etc/hostname" --port_name pi_console

# Check file permissions
python3 scripts/serial_bridge run "ls -la /home/pi" --port_name pi_console

# Search for files
python3 scripts/serial_bridge run "find /home/pi -name '*.py'" --port_name pi_console
```

### Package Management
```bash
# Update package lists
python3 scripts/serial_bridge run "sudo apt update" --port_name pi_console

# Install packages
python3 scripts/serial_bridge run "sudo apt install -y package_name" --port_name pi_console

# Check installed packages
python3 scripts/serial_bridge run "dpkg -l | grep package_name" --port_name pi_console
```

### Serial Agent Testing
```bash
# Test if serial agent is running
python3 scripts/serial_bridge run "systemctl status serial-agent@ttyAMA0" --port_name pi_console

# Check serial agent logs
python3 scripts/serial_bridge run "journalctl -u serial-agent@ttyAMA0 -f" --port_name pi_console

# Test serial communication
python3 scripts/serial_bridge run "echo 'TEST' > /dev/ttyAMA0" --port_name pi_console
```

## Advanced Usage

### Reading Serial Output
```bash
# Read all available data
python3 scripts/serial_bridge read --port_name pi_console

# Read specific number of bytes
python3 scripts/serial_bridge read --port_name pi_console --bytes 512

# Read specific number of lines
python3 scripts/serial_bridge read --port_name pi_console --lines 20

# Read with custom timeout
python3 scripts/serial_bridge read --port_name pi_console --timeout 10
```

### Writing Data
```bash
# Send commands
python3 scripts/serial_bridge write "AT" --port_name pi_console

# Send data with line ending
python3 scripts/serial_bridge write "AT\r\n" --port_name pi_console

# Send multiple commands
python3 scripts/serial_bridge write "AT\r\nAT+VERSION\r\n" --port_name pi_console
```

### Command Chaining
```bash
# Run multiple commands
python3 scripts/serial_bridge run "cd /tmp && ls -la && pwd" --port_name pi_console

# Check multiple services
python3 scripts/serial_bridge run "systemctl status inventory-app btwifiset bluetooth" --port_name pi_console

# System information
python3 scripts/serial_bridge run "echo '=== System Info ==='; uptime; echo '=== Memory ==='; free -h; echo '=== Disk ==='; df -h" --port_name pi_console
```

## Troubleshooting

### Common Issues

#### Connection Problems
```bash
# Check if serial port exists
ls -la /dev/tty*

# Check port permissions
ls -la /dev/tty.usbserial-1420

# Check if port is in use
lsof /dev/tty.usbserial-1420
```

#### No Response from Pi
```bash
# Check baud rate in config.yml
cat config.yml

# Test with simple command
python3 scripts/serial_bridge run "echo 'test'" --port_name pi_console

# Check serial connection
python3 scripts/serial_bridge read --port_name pi_console --timeout 5
```

#### Permission Issues
```bash
# Add user to dialout group
sudo usermod -a -G dialout $USER

# Change port permissions
sudo chmod 666 /dev/tty.usbserial-1420

# Check user groups
groups
```

#### Command Execution Issues
```bash
# Test basic command
python3 scripts/serial_bridge run "pwd" --port_name pi_console

# Check shell availability
python3 scripts/serial_bridge run "echo $SHELL" --port_name pi_console

# Test with absolute path
python3 scripts/serial_bridge run "/bin/ls" --port_name pi_console
```

### Debug Commands
```bash
# Check tool version
python3 scripts/serial_bridge --help

# Test port configuration
python3 scripts/serial_bridge read --port_name pi_console --timeout 1

# Check serial port status
python3 scripts/serial_bridge run "ls -la /dev/tty*" --port_name pi_console
```

## Best Practices

### 1. Use Appropriate Port Names
```bash
# Use descriptive port names
python3 scripts/serial_bridge run "command" --port_name pi_console

# Avoid using default unless necessary
python3 scripts/serial_bridge run "command" --port_name default
```

### 2. Set Appropriate Timeouts
```bash
# Short timeout for quick commands
python3 scripts/serial_bridge read --port_name pi_console --timeout 2

# Longer timeout for complex operations
python3 scripts/serial_bridge read --port_name pi_console --timeout 10
```

### 3. Handle Commands Properly
```bash
# Use quotes for commands with spaces
python3 scripts/serial_bridge run "ls -la /home/pi" --port_name pi_console

# Escape special characters
python3 scripts/serial_bridge run "echo 'Hello World'" --port_name pi_console

# Use absolute paths when needed
python3 scripts/serial_bridge run "/usr/bin/systemctl status" --port_name pi_console
```

### 4. Monitor Serial Output
```bash
# Read output after commands
python3 scripts/serial_bridge run "command" --port_name pi_console
python3 scripts/serial_bridge read --port_name pi_console --timeout 2

# Use appropriate read options
python3 scripts/serial_bridge read --port_name pi_console --lines 5
```

## Integration Examples

### Automated Testing Script
```bash
#!/bin/bash
PORT_NAME="pi_console"

echo "Testing serial bridge communication..."

# Test basic connectivity
echo "Testing basic command..."
python3 scripts/serial_bridge run "pwd" --port_name $PORT_NAME

# Test system status
echo "Testing system status..."
python3 scripts/serial_bridge run "uptime" --port_name $PORT_NAME

# Test service status
echo "Testing service status..."
python3 scripts/serial_bridge run "systemctl status inventory-app" --port_name $PORT_NAME

echo "Testing complete!"
```

### Service Monitoring Script
```bash
#!/bin/bash
PORT_NAME="pi_console"
SERVICES=("inventory-app" "btwifiset" "bluetooth")

echo "Monitoring services on Pi..."

for service in "${SERVICES[@]}"; do
    echo "Checking $service..."
    status=$(python3 scripts/serial_bridge run "systemctl is-active $service" --port_name $PORT_NAME)
    echo "$service: $status"
done
```

### Serial Debugging Script
```bash
#!/bin/bash
PORT_NAME="pi_console"

echo "Starting serial debugging session..."

# Check serial agent status
echo "Checking serial agent..."
python3 scripts/serial_bridge run "systemctl status serial-agent@ttyAMA0" --port_name $PORT_NAME

# Test serial communication
echo "Testing serial communication..."
python3 scripts/serial_bridge write "TEST" --port_name $PORT_NAME

# Read response
echo "Reading response..."
python3 scripts/serial_bridge read --port_name $PORT_NAME --timeout 5
```

## Security Considerations

### Access Control
- **User Permissions**: Ensure proper user group membership
- **Port Isolation**: Use dedicated serial ports for testing
- **Command Validation**: Validate commands before execution

### Data Security
- **Logging**: Be careful with sensitive data in output
- **Authentication**: Use proper authentication for Pi access
- **Network**: Don't expose serial devices over network

### Production Use
- **Error Handling**: Implement proper error handling
- **Monitoring**: Monitor serial communication for anomalies
- **Backup**: Have backup communication methods

## Performance Optimization

### Connection Settings
```yaml
# Optimize for speed
serial_ports:
  fast:
    port: /dev/tty.usbserial-1420
    baudrate: 115200
    timeout: 1

# Optimize for reliability
serial_ports:
  reliable:
    port: /dev/tty.usbserial-1420
    baudrate: 9600
    timeout: 5
```

### Command Optimization
```bash
# Combine multiple commands
python3 scripts/serial_bridge run "cd /tmp && ls -la && pwd" --port_name pi_console

# Use efficient command sequences
python3 scripts/serial_bridge run "systemctl --no-pager status" --port_name pi_console
```

### Resource Management
```bash
# Close connections when done
# The tool automatically manages connections

# Monitor resource usage
ps aux | grep serial_bridge
lsof | grep tty
```

## How It Actually Works

### Command Execution Flow
1. **Mac sends command** via `serial_bridge run "command"`
2. **Serial connection** established to Pi via USB serial
3. **Pi serial agent** receives command on TTY device
4. **Agent executes command** using bash shell
5. **Output framed** with `__START__` and `__END__:exitcode` markers
6. **Response returned** to Mac via serial connection

### Serial Agent Protocol
The Pi-side agent uses a simple protocol:
- **Input**: Commands sent via stdin
- **Output**: Framed with markers for reliable parsing
- **Special commands**: `__PING__` → `__PONG__`, `__EXIT__` → `BYE`
- **Environment**: Non-interactive, no colors, no pagers

### Error Handling
- **Connection failures**: Handled gracefully with error messages
- **Command timeouts**: Configurable timeout values
- **Shell prompts**: Automatic detection and handling
- **Output parsing**: Robust marker-based framing

This comprehensive guide covers all aspects of the Serial Bridge tool based on actual testing and real usage. Use these patterns and examples to effectively communicate with Raspberry Pi devices over serial connections, run commands, and manage system operations.
