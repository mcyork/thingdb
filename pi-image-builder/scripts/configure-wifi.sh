#!/bin/bash

echo "📶 Wi-Fi Configuration Tool"
echo "============================"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILDER_DIR="$(dirname "$SCRIPT_DIR")"
WPA_CONF="$BUILDER_DIR/config/wpa_supplicant.conf"
SETTINGS_CONF="$BUILDER_DIR/config/settings.conf"

if [ $# -eq 0 ]; then
    echo "Usage: $0 <wifi-password>"
    echo "   or: $0 configure  # Interactive setup"
    echo ""
    echo "Current Wi-Fi SSID: $(grep 'WIFI_SSID=' "$SETTINGS_CONF" | cut -d'=' -f2 | tr -d '"')"
    echo ""
    exit 1
fi

if [ "$1" = "configure" ]; then
    # Interactive configuration
    echo "Wi-Fi Configuration"
    echo "==================="
    
    current_ssid=$(grep 'WIFI_SSID=' "$SETTINGS_CONF" | cut -d'=' -f2 | tr -d '"')
    read -p "Wi-Fi SSID [$current_ssid]: " ssid
    ssid=${ssid:-$current_ssid}
    
    read -s -p "Wi-Fi Password: " password
    echo ""
    
    read -p "Country code [US]: " country
    country=${country:-US}
    
    echo "Updating configuration..."
    
    # Update settings.conf
    sed -i.bak "s/WIFI_SSID=.*/WIFI_SSID=\"$ssid\"/" "$SETTINGS_CONF"
    sed -i.bak "s/WIFI_PASSWORD=.*/WIFI_PASSWORD=\"$password\"/" "$SETTINGS_CONF"
    sed -i.bak "s/WIFI_COUNTRY=.*/WIFI_COUNTRY=\"$country\"/" "$SETTINGS_CONF"
    
    # Update wpa_supplicant.conf
    cat > "$WPA_CONF" << EOF
country=$country
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1

network={
    ssid="$ssid"
    psk="$password"
    key_mgmt=WPA-PSK
    scan_ssid=1
}
EOF

else
    # Command line password update
    password="$1"
    ssid=$(grep 'WIFI_SSID=' "$SETTINGS_CONF" | cut -d'=' -f2 | tr -d '"')
    country=$(grep 'WIFI_COUNTRY=' "$SETTINGS_CONF" | cut -d'=' -f2 | tr -d '"')
    
    echo "Updating Wi-Fi password for SSID: $ssid"
    
    # Update wpa_supplicant.conf
    sed -i.bak "s/psk=\".*\"/psk=\"$password\"/" "$WPA_CONF"
    
    # Update settings.conf
    sed -i.bak "s/WIFI_PASSWORD=.*/WIFI_PASSWORD=\"$password\"/" "$SETTINGS_CONF"
fi

echo "✅ Wi-Fi configuration updated!"
echo ""
echo "📝 Configuration files updated:"
echo "  - $WPA_CONF"
echo "  - $SETTINGS_CONF"
echo ""
echo "🔨 Ready to build image with Wi-Fi credentials"