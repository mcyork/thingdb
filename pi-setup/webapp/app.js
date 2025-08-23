document.addEventListener('DOMContentLoaded', () => {
    // --- DOM Elements ---
    const connectButton = document.getElementById('connect-button');
    const statusMessages = document.getElementById('status-messages');
    const configForm = document.getElementById('config-form');
    const wifiSsidInput = document.getElementById('wifi-ssid');
    const wifiPasswordInput = document.getElementById('wifi-password');
    const submitWifiButton = document.getElementById('submit-wifi-button');
    const deviceNameInput = document.getElementById('device-name');
    const submitNameButton = document.getElementById('submit-name-button');
    const rebootButton = document.getElementById('reboot-button');

    // --- BLE UUIDs (must match Python script) ---
    const SERVICE_UUID = "a1a1a1a1-0000-1000-8000-00805f9b34fb";
    const WIFI_SSID_CHAR_UUID = "a1a1a1a1-0001-1000-8000-00805f9b34fb";
    const WIFI_PASSWORD_CHAR_UUID = "a1a1a1a1-0002-1000-8000-00805f9b34fb";
    const DEVICE_NAME_CHAR_UUID = "a1a1a1a1-0003-1000-8000-00805f9b34fb";
    const STATUS_CHAR_UUID = "a1a1a1a1-0004-1000-8000-00805f9b34fb";
    const COMMAND_CHAR_UUID = "a1a1a1a1-0005-1000-8000-00805f9b34fb";

    // --- State ---
    let bleDevice;
    let gattServer;
    let bleService;
    const characteristics = {};
    const textEncoder = new TextEncoder();

    const logStatus = (message) => {
        console.log(message);
        statusMessages.textContent = message;
    };

    const handleStatusNotifications = (event) => {
        const value = event.target.value;
        const message = new TextDecoder().decode(value);
        logStatus(`PI SAYS: ${message}`);
    };

    const connectToDevice = async () => {
        try {
            logStatus('Requesting Bluetooth device...');
            bleDevice = await navigator.bluetooth.requestDevice({
                filters: [{ services: [SERVICE_UUID] }],
                optionalServices: [SERVICE_UUID]
            });

            logStatus('Connecting to GATT server...');
            gattServer = await bleDevice.gatt.connect();

            logStatus('Getting service...');
            bleService = await gattServer.getPrimaryService(SERVICE_UUID);

            logStatus('Getting characteristics...');
            const allChars = await bleService.getCharacteristics();
            
            for (const char of allChars) {
                characteristics[char.uuid] = char;
            }

            // Subscribe to status notifications
            const statusChar = characteristics[STATUS_CHAR_UUID];
            if (statusChar) {
                await statusChar.startNotifications();
                statusChar.addEventListener('characteristicvaluechanged', handleStatusNotifications);
                logStatus('Subscribed to status notifications.');
            }

            logStatus('Connected successfully!');
            connectButton.classList.add('d-none');
            configForm.classList.remove('d-none');

        } catch (error) {
            logStatus(`Error: ${error.message}`);
            console.error(error);
        }
    };

    const writeCharacteristic = async (uuid, value) => {
        try {
            const char = characteristics[uuid];
            if (!char) {
                throw new Error(`Characteristic ${uuid} not found.`);
            }
            const data = typeof value === 'string' ? textEncoder.encode(value) : value;
            await char.writeValue(data);
            logStatus(`Wrote to ${uuid}: ${value}`);
        } catch (error) {
            logStatus(`Write Error: ${error.message}`);
            console.error(error);
        }
    };

    const handleWifiSubmit = async () => {
        const ssid = wifiSsidInput.value;
        const password = wifiPasswordInput.value;

        if (!ssid) {
            logStatus('SSID cannot be empty.');
            return;
        }

        logStatus('Sending Wi-Fi credentials...');
        await writeCharacteristic(WIFI_SSID_CHAR_UUID, ssid);
        await writeCharacteristic(WIFI_PASSWORD_CHAR_UUID, password);
        // Tell the Pi to process the credentials
        await writeCharacteristic(COMMAND_CHAR_UUID, 'apply_wifi');
    };

    const handleNameSubmit = async () => {
        const name = deviceNameInput.value;
        if (!name) {
            logStatus('Device name cannot be empty.');
            return;
        }
        logStatus(`Setting device name to ${name}...`);
        await writeCharacteristic(DEVICE_NAME_CHAR_UUID, name);
    };

    const handleReboot = async () => {
        logStatus('Sending reboot command...');
        await writeCharacteristic(COMMAND_CHAR_UUID, 'reboot');
    };

    // --- Event Listeners ---
    connectButton.addEventListener('click', connectToDevice);
    submitWifiButton.addEventListener('click', handleWifiSubmit);
    submitNameButton.addEventListener('click', handleNameSubmit);
    rebootButton.addEventListener('click', handleReboot);
});
