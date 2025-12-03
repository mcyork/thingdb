#!/bin/bash
# Setup Self-Signed SSL Certificate for ThingDB
# This enables HTTPS so camera access works on iPhone
#
# Usage:
#   ./setup_ssl.sh              - Smart setup (only regenerate if needed)
#   ./setup_ssl.sh --force      - Force regenerate certificates
#   ./setup_ssl.sh --service-only - Only update service file, don't touch certs

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
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
MARKER_FILE="$SSL_DIR/.thingdb_marker"

# BYO Certificate staging directory
STAGING_DIR="/var/lib/thingdb/certs"
STAGING_CERT="$STAGING_DIR/cert.pem"
STAGING_KEY="$STAGING_DIR/key.pem"

# Parse command line arguments
FORCE_REGEN=false
SERVICE_ONLY=false

for arg in "$@"; do
    case $arg in
        --force)
            FORCE_REGEN=true
            shift
            ;;
        --service-only)
            SERVICE_ONLY=true
            shift
            ;;
        *)
            ;;
    esac
done

# Get hostname and IP
HOSTNAME=$(hostname)
IP_ADDRESS=$(hostname -I | awk '{print $1}')

# Function to update systemd service file
update_service_file() {
    local use_ssl=$1  # "yes" or "no"
    
    echo -e "${BLUE}🔧 Updating systemd service configuration...${NC}"
    
    if [ "$use_ssl" = "yes" ]; then
        # HTTPS configuration with SSL
        # Bind to both port 5000 (standard) and port 443 (for scanners)
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
# Allow binding to port 443 (requires capability)
AmbientCapabilities=CAP_NET_BIND_SERVICE
ExecStart=/var/lib/thingdb/app/venv/bin/gunicorn \
    --bind 0.0.0.0:5000 \
    --bind 0.0.0.0:443 \
    --certfile /var/lib/thingdb/ssl/cert.pem \
    --keyfile /var/lib/thingdb/ssl/key.pem \
    --workers 2 \
    --timeout 600 \
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
        echo -e "${GREEN}✓${NC} Service configured for HTTPS (Gunicorn with SSL)"
        echo -e "${BLUE}  Listening on ports 5000 and 443${NC}"
    else
        # HTTP-only configuration
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
    --workers 2 \
    --timeout 600 \
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
        echo -e "${GREEN}✓${NC} Service configured for HTTP (Gunicorn without SSL)"
    fi
    
    sudo systemctl daemon-reload
}

# Function to check if service file needs updating
needs_service_update() {
    # Check if service file has correct timeout (600)
    if ! grep -q "timeout 600" /etc/systemd/system/thingdb.service 2>/dev/null; then
        return 0  # Needs update
    fi
    
    # Check if service file has correct worker config
    if ! grep -q "workers 2" /etc/systemd/system/thingdb.service 2>/dev/null; then
        return 0  # Needs update
    fi
    
    # Check if using old Flask dev server
    if grep -q "thingdb serve" /etc/systemd/system/thingdb.service 2>/dev/null; then
        return 0  # Needs update (upgrade scenario)
    fi
    
    # CRITICAL: Check if SSL certificates exist but service file doesn't have SSL config
    # This happens during upgrades when install.sh overwrites the service file
    if [ -f "$CERT_FILE" ] && [ -f "$KEY_FILE" ]; then
        if ! grep -q "--certfile" /etc/systemd/system/thingdb.service 2>/dev/null || \
           ! grep -q "--keyfile" /etc/systemd/system/thingdb.service 2>/dev/null; then
            return 0  # Needs update - certificates exist but service lacks SSL config
        fi
    fi
    
    return 1  # Up to date
}

# Function to validate BYO certificates
validate_byo_certs() {
    if [ ! -f "$STAGING_CERT" ] || [ ! -f "$STAGING_KEY" ]; then
        return 1  # Missing files
    fi
    
    # Validate certificate format
    if ! openssl x509 -in "$STAGING_CERT" -noout -text >/dev/null 2>&1; then
        echo -e "${RED}✗${NC} Invalid certificate file: $STAGING_CERT"
        return 1
    fi
    
    # Validate key format
    if ! openssl rsa -in "$STAGING_KEY" -check -noout >/dev/null 2>&1; then
        echo -e "${RED}✗${NC} Invalid private key file: $STAGING_KEY"
        return 1
    fi
    
    # Check if cert and key match
    CERT_MODULUS=$(openssl x509 -noout -modulus -in "$STAGING_CERT" 2>/dev/null | openssl md5)
    KEY_MODULUS=$(openssl rsa -noout -modulus -in "$STAGING_KEY" 2>/dev/null | openssl md5)
    
    if [ "$CERT_MODULUS" != "$KEY_MODULUS" ]; then
        echo -e "${RED}✗${NC} Certificate and private key do not match!"
        return 1
    fi
    
    return 0
}

# Function to install BYO certificates
install_byo_certs() {
    echo -e "${BLUE}📥 Installing custom SSL certificates...${NC}"
    echo ""
    
    # Create SSL directory
    sudo mkdir -p "$SSL_DIR"
    
    # Copy certificates from staging
    sudo cp "$STAGING_CERT" "$CERT_FILE"
    sudo cp "$STAGING_KEY" "$KEY_FILE"
    
    # Set proper ownership and permissions
    sudo chown thingdb:thingdb "$CERT_FILE" "$KEY_FILE"
    sudo chmod 644 "$CERT_FILE"
    sudo chmod 600 "$KEY_FILE"
    
    # Remove any old marker file (marks as custom cert - NOT auto-generated)
    sudo rm -f "$MARKER_FILE"
    
    # Get certificate info
    CERT_SUBJECT=$(openssl x509 -in "$CERT_FILE" -noout -subject 2>/dev/null | sed 's/subject=//')
    CERT_ISSUER=$(openssl x509 -in "$CERT_FILE" -noout -issuer 2>/dev/null | sed 's/issuer=//')
    EXPIRY_DATE=$(openssl x509 -in "$CERT_FILE" -noout -enddate 2>/dev/null | cut -d= -f2)
    
    echo -e "${GREEN}✓${NC} Custom SSL certificates installed!"
    echo ""
    echo "Certificate details:"
    echo "  Subject: $CERT_SUBJECT"
    echo "  Issuer: $CERT_ISSUER"
    echo "  Expires: $EXPIRY_DATE"
    echo "  Location: $CERT_FILE"
    echo "  Key: $KEY_FILE"
    echo ""
    
    # Clean up staging directory
    echo "Cleaning up staging directory..."
    sudo rm -rf "$STAGING_DIR"
    echo -e "${GREEN}✓${NC} Staging directory removed"
    echo ""
}

# Function to generate SSL certificates
generate_certificates() {
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
    
    # Create marker file to identify ThingDB-generated certificates
    echo "thingdb-autogen-v1" | sudo tee "$SSL_DIR/.thingdb_marker" > /dev/null
    sudo chown thingdb:thingdb "$SSL_DIR/.thingdb_marker"
    
    echo -e "${GREEN}✓${NC} SSL certificate generated!"
    echo ""
    echo "Certificate details:"
    echo "  Location: $CERT_FILE"
    echo "  Key: $KEY_FILE"
    echo "  Hostname: ${HOSTNAME}"
    echo "  IP Address: ${IP_ADDRESS}"
    echo "  Valid for: 365 days"
    echo ""
}

# Main logic
REGEN_CERTS=false
UPDATE_SERVICE=false
BYO_MODE=false

# Check for BYO certificates FIRST (highest priority)
if [ -d "$STAGING_DIR" ] && [ "$SERVICE_ONLY" != true ]; then
    echo -e "${BLUE}📁 Bring-Your-Own certificate directory detected: $STAGING_DIR${NC}"
    echo ""
    
    if validate_byo_certs; then
        echo -e "${GREEN}✓${NC} Certificates validated successfully!"
        echo "  Certificate and key match"
        echo "  Files are valid"
        echo ""
        
        # Install BYO certificates
        install_byo_certs
        BYO_MODE=true
        UPDATE_SERVICE=true
        REGEN_CERTS=false
    else
        echo -e "${RED}✗${NC} Certificate validation failed!"
        echo ""
        echo "Please check:"
        echo "  - $STAGING_CERT exists and is a valid PEM certificate"
        echo "  - $STAGING_KEY exists and is a valid unencrypted RSA private key"
        echo "  - Certificate and key match each other"
        echo ""
        echo "Expected files in $STAGING_DIR:"
        echo "  - cert.pem    (certificate + intermediate CA chain concatenated)"
        echo "  - key.pem     (unencrypted private key)"
        echo ""
        exit 1
    fi
fi

# Determine what needs to be done
if [ "$BYO_MODE" = true ]; then
    # Already handled BYO installation above
    # Just need to update service
    :
elif [ "$SERVICE_ONLY" = true ]; then
    # Only update service file
    echo "Service-only mode: Will not touch certificates"
    UPDATE_SERVICE=true
    REGEN_CERTS=false
elif [ "$FORCE_REGEN" = true ]; then
    # Force regeneration
    echo "Force mode: Regenerating certificates and updating service"
    REGEN_CERTS=true
    UPDATE_SERVICE=true
    # Remove old certs/marker
    sudo rm -f "$CERT_FILE" "$KEY_FILE" "$MARKER_FILE"
else
    # Smart auto-detection
    if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
        # Certificates missing - generate them
        REGEN_CERTS=true
        UPDATE_SERVICE=true
    elif [ -f "$MARKER_FILE" ]; then
        # ThingDB-generated certs - check expiry
        EXPIRY_DATE=$(openssl x509 -in "$CERT_FILE" -noout -enddate 2>/dev/null | cut -d= -f2)
        if [ -n "$EXPIRY_DATE" ]; then
            EXPIRY_EPOCH=$(date -d "$EXPIRY_DATE" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$EXPIRY_DATE" +%s 2>/dev/null)
            NOW_EPOCH=$(date +%s)
            DAYS_LEFT=$(( ($EXPIRY_EPOCH - $NOW_EPOCH) / 86400 ))
            
            if [ $DAYS_LEFT -lt 30 ]; then
                echo -e "${YELLOW}⚠${NC}  SSL certificate expires in $DAYS_LEFT days - regenerating..."
                REGEN_CERTS=true
                UPDATE_SERVICE=true
            else
                echo -e "${GREEN}✓${NC} SSL certificate valid for $DAYS_LEFT more days"
                REGEN_CERTS=false
                # But still check if service needs update
                if needs_service_update; then
                    echo "  Service file needs updating (timeout/workers changed)"
                    UPDATE_SERVICE=true
                else
                    echo "  Service file up to date"
                    UPDATE_SERVICE=false
                fi
            fi
        fi
    else
        # Certs exist without marker - could be custom or old version
        if grep -q "thingdb serve" /etc/systemd/system/thingdb.service 2>/dev/null; then
            # Upgrade scenario - old HTTP-only service
            echo -e "${YELLOW}⚠${NC}  Detected upgrade from old version (HTTP-only)"
            echo "  Regenerating SSL certificates with marker..."
            REGEN_CERTS=true
            UPDATE_SERVICE=true
            sudo rm -f "$CERT_FILE" "$KEY_FILE"
        else
            # Truly custom certificates - preserve them
            echo -e "${YELLOW}⚠${NC}  Found custom SSL certificates (not ThingDB-generated)"
            echo "  Preserving custom certificates"
            REGEN_CERTS=false
            # But still update service if needed
            if needs_service_update; then
                echo "  Updating service file (timeout/workers) without touching certificates"
                UPDATE_SERVICE=true
            else
                echo "  Service file already up to date"
                echo ""
                echo "  To force regeneration: sudo ./setup_ssl.sh --force"
                exit 0
            fi
        fi
    fi
fi

# Execute actions
if [ "$REGEN_CERTS" = true ]; then
    generate_certificates
fi

if [ "$UPDATE_SERVICE" = true ]; then
    if [ -f "$CERT_FILE" ] && [ -f "$KEY_FILE" ]; then
        update_service_file "yes"
    else
        echo -e "${YELLOW}⚠${NC}  No SSL certificates found - configuring HTTP-only"
        update_service_file "no"
    fi
    
    echo -e "${BLUE}🚀 Restarting ThingDB service...${NC}"
    sudo systemctl restart thingdb
    
    # Wait for service to start
    sleep 5
    
    if sudo systemctl is-active --quiet thingdb; then
        if [ -f "$CERT_FILE" ]; then
            echo -e "${GREEN}✓${NC} ThingDB is running with HTTPS!"
        else
            echo -e "${GREEN}✓${NC} ThingDB is running with HTTP!"
        fi
    else
        echo -e "${YELLOW}⚠${NC}  Service may not have started. Check with: sudo systemctl status thingdb"
    fi
else
    echo ""
    echo -e "${GREEN}✓${NC} No changes needed - everything is up to date!"
    exit 0
fi

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║              🎉 Setup Complete! 🎉                             ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

if [ -f "$CERT_FILE" ]; then
    echo -e "${GREEN}Access ThingDB with HTTPS:${NC}"
    echo "  https://${IP_ADDRESS}:5000  (standard web access)"
    echo "  https://${IP_ADDRESS}:443   (scanner endpoint)"
    echo "  https://${HOSTNAME}.local:5000"
    echo "  https://${HOSTNAME}.local:443"
    echo ""
    
    # Check if this is a BYO cert or self-signed
    if [ ! -f "$MARKER_FILE" ]; then
        echo -e "${GREEN}✓${NC} Using custom SSL certificate (not self-signed)"
        echo "  Your certificate is from a recognized CA or custom PKI"
        echo "  Browsers will trust it if the CA is in their trust store"
        echo ""
        echo -e "${BLUE}💡 Certificate Renewal:${NC}"
        echo "  To update your certificate in the future:"
        echo "  1. Place new cert.pem and key.pem in /var/lib/thingdb/certs/"
        echo "  2. Run: sudo ./setup_ssl.sh"
        echo "  3. Your new certificates will be installed automatically"
    else
        echo -e "${YELLOW}⚠️  Self-Signed Certificate Warning${NC}"
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
        echo -e "${BLUE}💡 Want a trusted certificate?${NC}"
        echo "  Use a certificate from Let's Encrypt or your own CA"
        echo "  See INSTALL.md for Bring-Your-Own Certificate instructions"
    fi
    echo ""
    echo -e "${GREEN}📷 Camera scanning will work on iPhone!${NC}"
else
    echo -e "${GREEN}Access ThingDB with HTTP:${NC}"
    echo "  http://${IP_ADDRESS}:5000"
    echo ""
    echo -e "${YELLOW}Note: HTTPS disabled. Camera may not work on iPhone.${NC}"
    echo "  To enable HTTPS: sudo ./setup_ssl.sh"
fi
echo ""
