# Printing System Guide

## Overview

The Inventory Management System includes a comprehensive printing solution that allows you to print:
- **Inventory Lists** - Formatted lists of all items or filtered by container
- **QR Code Labels** - QR codes for items that can be scanned to access item details
- **Item Details** - Detailed information for specific items
- **Complete Inventory** - Both list and QR codes in one print job

All printing is handled locally on the Raspberry Pi using CUPS (Common Unix Printing System), ensuring reliable printing regardless of the device accessing the system.

## Printer Setup

### 1. Install CUPS on Raspberry Pi

The printing system requires CUPS to be installed on your Raspberry Pi:

```bash
# Update package lists
sudo apt update

# Install CUPS and related packages
sudo apt install cups cups-client cups-daemon

# Add your user to the lpadmin group
sudo usermod -a -G lpadmin pi

# Start and enable CUPS service
sudo systemctl start cups
sudo systemctl enable cups
```

### 2. Configure Printer

#### USB Printer
1. Connect your USB printer to the Raspberry Pi
2. CUPS should automatically detect it
3. Access CUPS web interface: `http://raspberry-pi-ip:631`
4. Add the printer through the web interface

#### Network Printer
1. Ensure the printer is on the same network as the Raspberry Pi
2. Access CUPS web interface: `http://raspberry-pi-ip:631`
3. Add the printer using its network address

#### Set Default Printer
```bash
# List available printers
lpstat -p

# Set default printer
lpoptions -d PRINTER_NAME
```

### 3. Test Printer Connection

Use the built-in printer test function in the web interface:
1. Go to any printing page
2. Click "🔧 Test Printer Connection"
3. Verify the printer responds correctly

## Using the Printing System

### Print Inventory List

1. **Access**: Click "🖨️ Print List" from the home page
2. **Filter Options**:
   - Leave empty to print all root items
   - Enter a container GUID to print only items within that container
3. **Printer Selection**:
   - Use default printer (recommended)
   - Or select a specific printer from the dropdown
4. **Print**: Click "🖨️ Print Inventory List"

**Output Format**:
- Professional table layout with item details
- Includes item number, name, description, creation date, and image count
- Summary with total item count
- Timestamp of when the list was generated

### Print QR Codes

1. **Access**: Click "📱 Print QR Codes" from the home page
2. **Filter Options**:
   - Leave empty to print QR codes for all root items
   - Enter a container GUID to print QR codes only for items within that container
3. **Printer Selection**: Choose your preferred printer
4. **Print**: Click "📱 Print QR Codes"

**Output Format**:
- 3-column layout of QR codes
- Each QR code includes:
  - The full GUID (scannable)
  - Item name (truncated if too long)
  - Shortened GUID for reference
- Optimized for label printing

### Print Item Details

1. **Access**: Click the "🖨️" button in the item header
2. **Automatic**: Uses the default printer
3. **Output**: Detailed single-page report for the item

**Output Format**:
- Item name and label number
- Full GUID
- Creation date and image count
- Description (if available)
- QR code section for future scanning

### Print Complete Inventory

For a comprehensive print job that includes both the inventory list and QR codes:

1. **Access**: Use the API endpoint `/print/print-all`
2. **Method**: POST request
3. **Output**: Two separate print jobs - list first, then QR codes

## API Endpoints

### Print Inventory List
```
POST /print/inventory-list
Parameters:
- parent_guid (optional): Container GUID to filter items
- printer_name (optional): Specific printer to use
```

### Print QR Codes
```
POST /print/qr-codes
Parameters:
- parent_guid (optional): Container GUID to filter items
- printer_name (optional): Specific printer to use
```

### Print Item Details
```
POST /print/item/<guid>
Parameters:
- printer_name (optional): Specific printer to use
```

### Get Available Printers
```
GET /print/printers
Response: List of available printers with status
```

### Test Printer Connection
```
POST /print/test-printer
Parameters:
- printer_name (optional): Printer to test
```

### Print Complete Inventory
```
POST /print/print-all
Parameters:
- printer_name (optional): Specific printer to use
```

## Troubleshooting

### Printer Not Found
1. Check if CUPS is running: `sudo systemctl status cups`
2. Verify printer is connected and powered on
3. Check CUPS web interface: `http://raspberry-pi-ip:631`
4. Restart CUPS: `sudo systemctl restart cups`

### Print Jobs Fail
1. Check printer status: `lpstat -p`
2. View print queue: `lpq`
3. Cancel stuck jobs: `lprm -`
4. Check CUPS error logs: `sudo tail -f /var/log/cups/error_log`

### QR Codes Not Scanning
1. Ensure QR codes are printed clearly
2. Check that the GUID is correctly encoded
3. Verify the QR code size is appropriate for your scanner
4. Test with a different QR code scanner app

### Font Issues
The system automatically detects system fonts. If text appears incorrectly:
1. Install additional fonts: `sudo apt install fonts-dejavu-core`
2. Restart the application after font installation

## Advanced Configuration

### Custom Printer Settings
Edit CUPS configuration:
```bash
sudo nano /etc/cups/cupsd.conf
```

### Printer Driver Installation
For specific printer models, install additional drivers:
```bash
# HP printers
sudo apt install hplip

# Brother printers
sudo apt install brother-lpr-drivers-extra

# Canon printers
sudo apt install cnijfilter-common
```

### Network Printer Discovery
Enable network printer discovery:
```bash
sudo apt install avahi-daemon
sudo systemctl enable avahi-daemon
```

## Security Considerations

- CUPS web interface is accessible on port 631
- Consider firewall rules to restrict access if needed
- Printer access is limited to users in the `lpadmin` group
- Print jobs are processed locally on the Raspberry Pi

## Performance Tips

- Large inventories (>1000 items) may take longer to process
- QR code generation is optimized for batches
- Consider printing in smaller batches for very large inventories
- Monitor system resources during large print jobs

## Integration with Existing Workflows

The printing system integrates seamlessly with existing inventory workflows:

1. **Scan QR Code** → **View Item** → **Print Details**
2. **Search Items** → **Filter Results** → **Print List**
3. **Organize Items** → **Select Container** → **Print Container Contents**
4. **Add New Items** → **Generate QR Codes** → **Print Labels**

This comprehensive printing solution ensures that your inventory system can produce professional documentation and labels for any use case.
