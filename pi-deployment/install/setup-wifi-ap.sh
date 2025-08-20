#!/bin/bash
#
# ==============================================================================
# setup-wifi-ap.sh (v3 - With Connection Validation)
# ------------------------------------------------------------------------------
# This script prepares the Raspberry Pi for a user-friendly first-time Wi-Fi
# setup. It includes robust validation to ensure a connection is fully
# working before rebooting.
#
# What it does:
# 1. Stops and disables the main application services (Nginx, inventory-app).
# 2. Removes existing Wi-Fi credentials.
# 3. Installs and configures dnsmasq for DHCP/DNS.
# 4. Configures NetworkManager to create a Wi-Fi Access Point on boot.
# 5. Creates a Python Flask captive portal with a robust validation routine.
# 6. Sets up a systemd service to run the captive portal on boot.
# 7. Enables the AP/portal mode for the next boot.
# ==============================================================================

set -e
echo "[INFO] Starting Wi-Fi Access Point setup..."

# --- 1. Define constants and paths ---
AP_SSID="InventoryPi-Setup"
AP_IP="10.0.0.1"
PORTAL_APP_DIR="/opt/captive-portal"
PORTAL_SERVICE_FILE="/etc/systemd/system/captive-portal.service"
DNSMASQ_CONF_FILE="/etc/dnsmasq.d/captive-portal.conf"
NM_AP_CONNECTION_NAME="captive-portal-ap"

# --- 2. Stop and disable main application services to prevent conflict ---
echo "[INFO] Stopping and disabling main application services (nginx, inventory-app)..."
systemctl stop nginx || echo "Nginx was not running."
systemctl disable nginx
systemctl stop inventory-app || echo "Inventory-app was not running."
systemctl disable inventory-app

# --- 3. Install required packages ---
echo "[INFO] Installing dnsmasq..."
apt-get update
apt-get install -y dnsmasq

# --- 4. Clear existing Wi-Fi connections ---
echo "[INFO] Deleting all existing Wi-Fi connections..."
nmcli --fields UUID,TYPE con show | grep "wifi" | awk '{print $1}' | while read -r uuid; do
    echo "Deleting connection with UUID: $uuid"
    nmcli con delete "$uuid"
done
echo "[INFO] Wi-Fi connections cleared."

# --- 5. Configure NetworkManager to create an Access Point ---
echo "[INFO] Configuring NetworkManager to create an AP: ${AP_SSID}"
nmcli con add type wifi ifname wlan0 con-name "${NM_AP_CONNECTION_NAME}" autoconnect yes ssid "${AP_SSID}"
nmcli con modify "${NM_AP_CONNECTION_NAME}" 802-11-wireless.mode ap 802-11-wireless.band bg
nmcli con modify "${NM_AP_CONNECTION_NAME}" ipv4.method shared ipv4.addresses "${AP_IP}/24"
nmcli con modify "${NM_AP_CONNECTION_NAME}" wifi-sec.key-mgmt wpa-psk
nmcli con modify "${NM_AP_CONNECTION_NAME}" wifi-sec.psk "inventory"

# --- 6. Configure dnsmasq ---
echo "[INFO] Configuring dnsmasq..."
cat > "${DNSMASQ_CONF_FILE}" << EOF
interface=wlan0
dhcp-range=10.0.0.10,10.0.0.50,255.255.255.0,12h
address=/#/${AP_IP}
EOF

# --- 7. Create the Captive Portal Flask Application ---
echo "[INFO] Creating captive portal application at ${PORTAL_APP_DIR}"
mkdir -p "${PORTAL_APP_DIR}/templates"

# Python App with Validation
cat > "${PORTAL_APP_DIR}/portal.py" << EOF
import subprocess
import time
from flask import Flask, render_template, request, jsonify

app = Flask(__name__)

def run_command(command, timeout=10):
    """Executes a shell command and returns its output."""
    try:
        result = subprocess.run(
            command,
            shell=True,
            check=True,
            capture_output=True,
            text=True,
            timeout=timeout
        )
        return result.stdout.strip(), 0
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
        output = e.stderr.strip() if hasattr(e, 'stderr') else "Command timed out"
        return output, e.returncode if hasattr(e, 'returncode') else 1

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/scan_wifi')
def scan_wifi():
    """Scans for Wi-Fi networks using nmcli."""
    output, _ = run_command("nmcli --terse --fields SSID,SECURITY device wifi list --rescan yes")
    networks = []
    for line in output.splitlines():
        parts = line.split(':')
        if len(parts) >= 1 and parts[0]:
            networks.append({"ssid": parts[0], "security": parts[1] if len(parts) > 1 else "Open"})
    return jsonify(networks)

@app.route('/connect', methods=['POST'])
def connect():
    """Attempts to connect to Wi-Fi and validates the connection before rebooting."""
    data = request.json
    ssid = data.get('ssid')
    password = data.get('password')

    if not ssid:
        return jsonify({"success": False, "message": "SSID is required."}), 400

    print(f"Attempting to connect to SSID: {ssid}")
    connect_command = f"nmcli device wifi connect '{ssid}' password '{password}'"
    output, returncode = run_command(connect_command)

    if returncode != 0:
        print(f"Initial connection command failed: {output}")
        return jsonify({"success": False, "message": f"Failed to initiate connection: {output}"}), 500

    # --- VALIDATION STAGE ---
    print("Connection initiated. Validating network state...")
    
    # 1. Poll for IP address
    ip_address = None
    for _ in range(6): # Try for 30 seconds (6 * 5s)
        time.sleep(5)
        ip_info, _ = run_command("nmcli -t -f IP4.ADDRESS device show wlan0")
        if 'IP4.ADDRESS' in ip_info and '/' in ip_info:
            ip_address = ip_info.split(':')[1].split('/')[0]
            if ip_address:
                print(f"Successfully acquired IP address: {ip_address}")
                break
    
    if not ip_address:
        print("Validation failed: Could not get an IP address.")
        run_command(f"nmcli con delete '{ssid}'") # Clean up failed connection
        return jsonify({"success": False, "message": "Could not get an IP address. Please check password."}), 500

    # 2. Test internet connectivity
    print("Validating internet connectivity...")
    ping_output, ping_code = run_command("ping -c 1 8.8.8.8")
    
    if ping_code != 0:
        print(f"Validation failed: Ping test failed. Output: {ping_output}")
        run_command(f"nmcli con delete '{ssid}'") # Clean up failed connection
        return jsonify({"success": False, "message": "Connected to Wi-Fi, but no internet access. Check network."}), 500

    # --- SUCCESS ---
    print("Validation successful! Handing back control and rebooting.")
    # Disable captive portal and re-enable main application
    run_command("systemctl stop captive-portal; systemctl disable captive-portal")
    run_command("systemctl stop dnsmasq; systemctl disable dnsmasq")
    run_command("systemctl enable nginx; systemctl enable inventory-app")
    
    # Use a separate process for reboot to allow the success response to be sent
    subprocess.Popen(["/sbin/reboot"])
    
    return jsonify({"success": True, "message": "Success! The device will now reboot and connect to your network."})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=80)
EOF

# HTML Template
cat > "${PORTAL_APP_DIR}/templates/index.html" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Inventory System Wi-Fi Setup</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; margin: 0; background-color: #f0f2f5; display: flex; justify-content: center; align-items: center; height: 100vh; }
        .container { background-color: white; padding: 2rem; border-radius: 8px; box-shadow: 0 4px 12px rgba(0,0,0,0.1); text-align: center; max-width: 400px; width: 90%; }
        h1 { color: #333; }
        select, input { width: 100%; padding: 0.8rem; margin: 0.5rem 0; border: 1px solid #ccc; border-radius: 4px; box-sizing: border-box; }
        button { width: 100%; padding: 0.8rem; background-color: #007bff; color: white; border: none; border-radius: 4px; font-size: 1rem; cursor: pointer; transition: background-color 0.2s; }
        button:hover { background-color: #0056b3; }
        button:disabled { background-color: #aaa; }
        #status { margin-top: 1rem; font-weight: bold; }
        #status.success { color: green; }
        #status.error { color: red; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Wi-Fi Setup</h1>
        <p>Please select your Wi-Fi network and enter the password.</p>
        <form id="wifi-form">
            <select id="ssid-select" name="ssid" required>
                <option value="">Scanning for networks...</option>
            </select>
            <input type="password" id="password" name="password" placeholder="Password" required>
            <button type="submit" id="connect-btn">Connect</button>
        </form>
        <div id="status"></div>
    </div>

    <script>
        document.addEventListener('DOMContentLoaded', () => {
            const ssidSelect = document.getElementById('ssid-select');
            const wifiForm = document.getElementById('wifi-form');
            const statusDiv = document.getElementById('status');
            const connectBtn = document.getElementById('connect-btn');

            // Scan for networks on page load
            fetch('/scan_wifi')
                .then(response => response.json())
                .then(networks => {
                    ssidSelect.innerHTML = '<option value="">Select your network</option>';
                    networks.forEach(net => {
                        const option = document.createElement('option');
                        option.value = net.ssid;
                        option.textContent = `${net.ssid} (${net.security})`;
                        ssidSelect.appendChild(option);
                    });
                })
                .catch(err => {
                    ssidSelect.innerHTML = '<option value="">Could not scan networks</option>';
                    console.error('Scan error:', err);
                });

            // Handle form submission
            wifiForm.addEventListener('submit', (event) => {
                event.preventDefault();
                statusDiv.textContent = 'Connecting and validating... This may take up to 30 seconds.';
                statusDiv.className = '';
                connectBtn.disabled = true;

                const formData = new FormData(wifiForm);
                const data = Object.fromEntries(formData.entries());

                fetch('/connect', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(data)
                })
                .then(response => response.json())
                .then(result => {
                    if (result.success) {
                        statusDiv.textContent = result.message;
                        statusDiv.className = 'success';
                        // Button remains disabled as we are rebooting
                    } else {
                        statusDiv.textContent = `Error: ${result.message}`;
                        statusDiv.className = 'error';
                        connectBtn.disabled = false; // Re-enable button on failure
                    }
                })
                .catch(err => {
                    statusDiv.textContent = 'An unexpected error occurred.';
                    statusDiv.className = 'error';
                    connectBtn.disabled = false;
                    console.error('Connect error:', err);
                });
            });
        });
    </script>
</body>
</html>
EOF

# --- 8. Create and Enable the systemd Service ---
echo "[INFO] Creating and enabling systemd service for captive portal..."
cat > "${PORTAL_SERVICE_FILE}" << EOF
[Unit]
Description=Captive Portal for Wi-Fi Setup
After=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 ${PORTAL_APP_DIR}/portal.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# --- 9. Finalize and Activate AP Mode ---
echo "[INFO] Activating AP mode for next boot..."
systemctl daemon-reload
systemctl stop wpa_supplicant || true
systemctl disable wpa_supplicant || true
systemctl enable captive-portal.service
systemctl restart dnsmasq
systemctl enable dnsmasq

echo ""
echo "========================================================================"
echo "✅ PREPARATION COMPLETE"
echo "The device is now configured to start in Access Point mode on next boot."
echo "The main nginx and inventory-app services have been disabled."
echo "They will be re-enabled automatically after the user sets up Wi-Fi."
echo ""
echo "SSID: ${AP_SSID}"
echo "Password: inventory"
echo "Please reboot the device now to activate the changes."
echo "========================================================================"
echo ""
