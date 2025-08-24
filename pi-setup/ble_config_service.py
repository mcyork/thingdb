#!/usr/bin/env python3
import asyncio
import subprocess
import uuid
import logging
from typing import Any

from bleak import BleakServer, BleakGATTService, BleakGATTCharacteristic, Advertisement

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

# ---
# Configuration ---
# Use `uuidgen` or a similar tool to generate your own unique UUIDs
SERVICE_UUID = "a1a1a1a1-0000-1000-8000-00805f9b34fb"
WIFI_SSID_CHAR_UUID = "a1a1a1a1-0001-1000-8000-00805f9b34fb"
WIFI_PASSWORD_CHAR_UUID = "a1a1a1a1-0002-1000-8000-00805f9b34fb"
DEVICE_NAME_CHAR_UUID = "a1a1a1a1-0003-1000-8000-00805f9b34fb"
STATUS_CHAR_UUID = "a1a1a1a1-0004-1000-8000-00805f9b34fb"
COMMAND_CHAR_UUID = "a1a1a1a1-0005-1000-8000-00805f9b34fb"

WPA_SUPPLICANT_CONF = "/etc/wpa_supplicant/wpa_supplicant.conf"
HOTNAME_FILE = "/etc/hostname"

class InventoryPiBLEService:
    """
    BLE Service for configuring the Raspberry Pi Inventory System.
    Handles Wi-Fi credentials, device name, and system commands.
    """
    def __init__(self):
        self.ssid: bytes | None = None
        self.password: bytes | None = None
        self.status_char: BleakGATTCharacteristic | None = None
        self.server: BleakServer | None = None

    async def write_char(self, characteristic: BleakGATTCharacteristic, value: bytearray):
        """General purpose write handler."""
        logging.info(f"Write to {characteristic.uuid}: {value.decode('utf-8', 'ignore')}")

    def _update_status(self, message: str):
        """Updates the status characteristic."""
        if self.status_char and self.server:
            logging.info(f"Updating status: {message}")
            try:
                self.server.get_service(SERVICE_UUID).get_characteristic(STATUS_CHAR_UUID).value = message.encode("utf-8")
            except Exception as e:
                logging.error(f"Could not update status: {e}")

    def _run_command(self, command: list[str]) -> bool:
        """Runs a shell command and logs its output."""
        try:
            logging.info(f"Running command: {' '.join(command)}")
            process = subprocess.run(command, check=True, capture_output=True, text=True)
            logging.info(f"Command stdout: {process.stdout}")
            if process.stderr:
                logging.warning(f"Command stderr: {process.stderr}")
            return True
        except subprocess.CalledProcessError as e:
            logging.error(f"Command failed: {e.stderr}")
            return False

    def _set_hostname(self, name: str):
        """Sets the system hostname."""
        self._update_status(f"Setting hostname to {name}...")
        try:
            with open(HOSTNAME_FILE, "w") as f:
                f.write(name + "\n")
            if self._run_command(["hostnamectl", "set-hostname", name]):
                 self._update_status(f"Hostname set to {name}. Reboot required.")
            else:
                raise Exception("hostnamectl command failed")
        except Exception as e:
            logging.error(f"Failed to set hostname: {e}")
            self._update_status(f"Error: Failed to set hostname.")

    def _configure_wifi(self):
        """Configures and applies Wi-Fi settings."""
        if not self.ssid:
            logging.warning("SSID not set. Cannot configure Wi-Fi.")
            self._update_status("Error: SSID not set.")
            return

        ssid_str = self.ssid.decode('utf-8')
        password_str = self.password.decode('utf-8') if self.password else ''
        self._update_status(f"Configuring Wi-Fi for {ssid_str}...")

        try:
            if self._run_command(["wpa_passphrase", ssid_str, password_str]):
                network_config = subprocess.check_output(["wpa_passphrase", ssid_str, password_str]).decode('utf-8')
                
                with open(WPA_SUPPLICANT_CONF, "a") as f:
                    f.write("\n" + network_config)

                self._update_status("Wi-Fi config written. Reconfiguring...")
                if self._run_command(["wpa_cli", "-i", "wlan0", "reconfigure"]):
                    self._update_status("Wi-Fi configured successfully!")
                else:
                    raise Exception("wpa_cli reconfigure failed")
            else:
                raise Exception("wpa_passphrase command failed")

        except Exception as e:
            logging.error(f"Failed to configure Wi-Fi: {e}")
            self._update_status(f"Error: Wi-Fi configuration failed.")

    async def handle_command(self, characteristic: BleakGATTCharacteristic, value: bytearray):
        command = value.decode('utf-8').lower()
        logging.info(f"Received command: {command}")

        if command == "apply_wifi":
            self._configure_wifi()
        elif command == "reboot":
            self._update_status("Rebooting now...")
            await asyncio.sleep(1)
            self._run_command(["reboot"])
        else:
            self._update_status(f"Unknown command: {command}")

    async def handle_ssid_write(self, characteristic: BleakGATTCharacteristic, value: bytearray):
        self.ssid = value
        logging.info(f"SSID set to: {self.ssid.decode('utf-8')}")
        self._update_status("SSID received.")

    async def handle_password_write(self, characteristic: BleakGATTCharacteristic, value: bytearray):
        self.password = value
        logging.info("Password received.")
        self._update_status("Password received. Send 'apply_wifi' command.")

    async def handle_name_write(self, characteristic: BleakGATTCharacteristic, value: bytearray):
        name = value.decode('utf-8')
        logging.info(f"Device name set to: {name}")
        self._set_hostname(name)


async def main():
    """Main function to run the BLE server."""
    service_handler = InventoryPiBLEService()
    
    app = BleakGATTService(SERVICE_UUID)
    app.add_characteristic(BleakGATTCharacteristic(WIFI_SSID_CHAR_UUID, ["write"], write_callback=service_handler.handle_ssid_write))
    app.add_characteristic(BleakGATTCharacteristic(WIFI_PASSWORD_CHAR_UUID, ["write"], write_callback=service_handler.handle_password_write))
    app.add_characteristic(BleakGATTCharacteristic(DEVICE_NAME_CHAR_UUID, ["write"], write_callback=service_handler.handle_name_write))
    app.add_characteristic(BleakGATTCharacteristic(COMMAND_CHAR_UUID, ["write"], write_callback=service_handler.handle_command))
    
    status_char = BleakGATTCharacteristic(STATUS_CHAR_UUID, ["read", "notify"])
    app.add_characteristic(status_char)
    service_handler.status_char = status_char

    advertisement = Advertisement(
        local_name="Inventory Pi Setup",
        service_uuids=[SERVICE_UUID],
    )

    async with BleakServer(app, advertisement_data=advertisement) as server:
        service_handler.server = server
        service_handler._update_status("BLE Service Started. Waiting for connection...")
        logging.info("BLE Server started. Advertising as 'Inventory Pi Setup'.")
        await asyncio.Event().wait() # Keep the server running indefinitely

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        logging.info("Server stopped by user.")
