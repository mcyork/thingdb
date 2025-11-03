#!/bin/bash
# Setup Self-Signed SSL Certificate for ThingDB
# This enables HTTPS so camera access works on iPhone

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║         ThingDB SSL Certificate Setup                          ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

SSL_DIR="/var/lib/thingdb/ssl"
CERT_FILE="$SSL_DIR/cert.pem"
KEY_FILE="$SSL_DIR/key.pem"

# Get hostname and IP
HOSTNAME=$(hostname)
IP_ADDRESS=$(hostname -I | awk '{print $1}')

echo -e "${BLUE}🔐 Generating self-signed SSL certificate...${NC}"
echo ""

# Create SSL directory
sudo mkdir -p "$SSL_DIR"

# Generate self-signed certificate
# Valid for 365 days, includes both hostname and IP as Subject Alternative Names
sudo openssl req -x509 -newkey rsa:4096 -nodes \
    -keyout "$KEY_FILE" \
    -out "$CERT_FILE" \
    -days 365 \
    -subj "/CN=${HOSTNAME}/O=ThingDB/C=US" \
    -addext "subjectAltName=DNS:${HOSTNAME},DNS:${HOSTNAME}.local,IP:${IP_ADDRESS},DNS:localhost,IP:127.0.0.1" \
    2>/dev/null

# Set ownership to thingdb user
sudo chown thingdb:thingdb "$KEY_FILE" "$CERT_FILE"
sudo chmod 600 "$KEY_FILE"
sudo chmod 644 "$CERT_FILE"

echo -e "${GREEN}✓${NC} SSL certificate generated!"
echo ""
echo "Certificate details:"
echo "  Location: $CERT_FILE"
echo "  Key: $KEY_FILE"
echo "  Hostname: ${HOSTNAME}"
echo "  IP Address: ${IP_ADDRESS}"
echo "  Valid for: 365 days"
echo ""

echo -e "${BLUE}🔧 Updating systemd service for HTTPS...${NC}"

# Update the systemd service to use SSL
sudo tee /etc/systemd/system/thingdb.service > /dev/null << 'SERVICEEOF'
[Unit]
Description=ThingDB Inventory Management System
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
User=thingdb
Group=thingdb
WorkingDirectory=/var/lib/thingdb/app
Environment="PATH=/var/lib/thingdb/app/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStart=/var/lib/thingdb/app/venv/bin/gunicorn \
    --bind 0.0.0.0:5000 \
    --certfile /var/lib/thingdb/ssl/cert.pem \
    --keyfile /var/lib/thingdb/ssl/key.pem \
    --workers 2 \
    --timeout 120 \
    --access-logfile - \
    --error-logfile - \
    "thingdb.main:app"

# Restart policy
Restart=always
RestartSec=10

# Security settings
# NoNewPrivileges disabled to allow sudo for power management
# thingdb user has NOPASSWD access only to: shutdown, reboot, sync, restart
PrivateTmp=true

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=thingdb

[Install]
WantedBy=multi-user.target
SERVICEEOF

sudo systemctl daemon-reload

echo -e "${GREEN}✓${NC} Service updated to use HTTPS"
echo ""

echo -e "${BLUE}🚀 Restarting ThingDB service...${NC}"
sudo systemctl restart thingdb

# Wait for service to start
sleep 5

if sudo systemctl is-active --quiet thingdb; then
    echo -e "${GREEN}✓${NC} ThingDB is running with HTTPS!"
else
    echo -e "${YELLOW}⚠${NC}  Service may not have started. Check with: sudo systemctl status thingdb"
fi

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║              🎉 HTTPS Setup Complete! 🎉                       ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo -e "${GREEN}Access ThingDB with HTTPS:${NC}"
echo "  https://${IP_ADDRESS}:5000"
echo "  https://${HOSTNAME}.local:5000"
echo ""
echo -e "${YELLOW}⚠️  Important: Self-Signed Certificate Warning${NC}"
echo ""
echo "Your browser will show a security warning because this is a"
echo "self-signed certificate. This is NORMAL and SAFE on your local network."
echo ""
echo -e "${BLUE}To bypass the warning:${NC}"
echo ""
echo "📱 ${BLUE}On iPhone/Safari:${NC}"
echo "   1. Tap 'Show Details'"
echo "   2. Tap 'visit this website'"
echo "   3. Tap 'Visit Website' again"
echo ""
echo "💻 ${BLUE}On Chrome/Edge:${NC}"
echo "   1. Click 'Advanced'"
echo "   2. Click 'Proceed to ${IP_ADDRESS} (unsafe)'"
echo ""
echo "🦊 ${BLUE}On Firefox:${NC}"
echo "   1. Click 'Advanced...'"
echo "   2. Click 'Accept the Risk and Continue'"
echo ""
echo -e "${GREEN}📷 Camera scanning will now work on iPhone!${NC}"
echo ""

