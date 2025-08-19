#!/bin/bash

# Create SSL directory if it doesn't exist
mkdir -p /ssl-certs

# Set ACME server from environment variable or use default
ACME_SERVER=${ACME_SERVER:-"https://acme.mcyork.com:10443/acme/acme/directory"}

# Function to check if domain is accessible
check_domain() {
    local domain=$1
    echo "Checking if domain $domain is accessible..."
    
    # Check if domain resolves and ports are open
    if ! nslookup $domain >/dev/null 2>&1; then
        echo "WARNING: Domain $domain does not resolve. Using self-signed certificate."
        return 1
    fi
    
    # Check if ports 80 and 443 are accessible
    if ! nc -z $domain 80 2>/dev/null; then
        echo "WARNING: Port 80 not accessible on $domain. Using self-signed certificate."
        return 1
    fi
    
    if ! nc -z $domain 443 2>/dev/null; then
        echo "WARNING: Port 443 not accessible on $domain. Using self-signed certificate."
        return 1
    fi
    
    echo "Domain $domain is accessible"
    return 0
}

# Function to generate self-signed certificate (fallback)
generate_self_signed() {
    echo "Generating self-signed SSL certificate..."
    
    # Create private key
    openssl genrsa -out /ssl-certs/private.key 2048
    
    # Create certificate signing request
    openssl req -new -key /ssl-certs/private.key -out /ssl-certs/cert.csr -subj "/C=US/ST=Local/L=Development/O=DevContainer/CN=localhost"
    
    # Generate self-signed certificate
    openssl x509 -req -days 365 -in /ssl-certs/cert.csr -signkey /ssl-certs/private.key -out /ssl-certs/cert.crt
    
    # Combine for Nginx
    cat /ssl-certs/cert.crt /ssl-certs/private.key > /ssl-certs/cert.pem
    
    echo "Self-signed SSL certificate generated successfully"
}

# Function to request certificate with acme.sh
request_acme_certificate() {
    local domain=$1
    echo "Requesting ACME certificate for domain: $domain"
    
    # Configure acme.sh with custom server
    acme.sh --set-default-ca --server $ACME_SERVER
    
    # Request certificate using HTTP challenge
    # Using /var/lib/letsencrypt to match NAS configuration
    acme.sh --issue -d $domain --webroot /var/lib/letsencrypt --server $ACME_SERVER --insecure
    
    # Install certificate for Nginx
    acme.sh --install-cert -d $domain \
        --key-file /ssl-certs/private.key \
        --fullchain-file /ssl-certs/cert.pem \
        --reloadcmd "nginx -s reload"
    
    # Install cron job for automatic renewal
    acme.sh --install-cronjob
    
    echo "ACME certificate installed successfully with auto-renewal"
}

# Main certificate logic
if [ ! -f /ssl-certs/cert.pem ]; then
    # Try to get domain from environment or use localhost
    DOMAIN=${DOMAIN:-"localhost"}
    
    echo "ACME Server: $ACME_SERVER"
    echo "Domain: $DOMAIN"
    
    # Check if acme.sh is available
    if command -v acme.sh >/dev/null 2>&1; then
        echo "acme.sh is available"
        
        # Check if domain is accessible
        if check_domain $DOMAIN; then
            # Try to request ACME certificate
            if request_acme_certificate $DOMAIN; then
                echo "ACME certificate requested successfully"
            else
                echo "ACME certificate request failed, falling back to self-signed"
                generate_self_signed
            fi
        else
            echo "Domain not accessible, using self-signed certificate"
            generate_self_signed
        fi
    else
        echo "acme.sh not available, using self-signed certificate"
        generate_self_signed
    fi
else
    echo "SSL certificate already exists - using existing certificates"
fi

# Verify certificates exist and are readable
if [ -f /ssl-certs/cert.pem ] && [ -f /ssl-certs/private.key ]; then
    echo "Certificate files found, validating..."
    
    # Check certificate details
    echo "----------------------------------------"
    echo "📜 Certificate Information:"
    openssl x509 -in /ssl-certs/cert.pem -noout -subject -issuer -dates | sed 's/^/   /'
    
    # Check if self-signed
    SUBJECT=$(openssl x509 -in /ssl-certs/cert.pem -noout -subject)
    ISSUER=$(openssl x509 -in /ssl-certs/cert.pem -noout -issuer)
    
    if [ "$SUBJECT" = "$ISSUER" ]; then
        echo "   ⚠️  Certificate Type: SELF-SIGNED"
        echo "   ⚠️  This certificate is NOT from a trusted authority"
    else
        echo "   ✅ Certificate Type: CA-SIGNED"
        ISSUER_CN=$(echo $ISSUER | grep -o 'CN=[^,]*' | cut -d'=' -f2)
        echo "   ✅ Issued by: $ISSUER_CN"
        
        # Check if it's from our private PKI
        if echo "$ISSUER" | grep -q "mcyork"; then
            echo "   ✅ From Private PKI (mcyork.com)"
        fi
    fi
    
    # Check expiration
    EXPIRY=$(openssl x509 -in /ssl-certs/cert.pem -noout -enddate | cut -d'=' -f2)
    EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s 2>/dev/null || date -j -f "%b %d %H:%M:%S %Y %Z" "$EXPIRY" +%s)
    NOW_EPOCH=$(date +%s)
    DAYS_LEFT=$(( ($EXPIRY_EPOCH - $NOW_EPOCH) / 86400 ))
    
    if [ $DAYS_LEFT -lt 0 ]; then
        echo "   ❌ Certificate Status: EXPIRED"
    elif [ $DAYS_LEFT -lt 30 ]; then
        echo "   ⚠️  Certificate expires in $DAYS_LEFT days"
    else
        echo "   ✅ Certificate valid for $DAYS_LEFT more days"
    fi
    
    # Check domains covered
    echo "   📍 Domains covered:"
    openssl x509 -in /ssl-certs/cert.pem -noout -text | grep -A1 "Subject Alternative Name" | tail -1 | sed 's/DNS://g' | sed 's/,/\n   /g' | sed 's/^/   /'
    
    echo "----------------------------------------"
    echo "Certificate verification: COMPLETE"
else
    echo "ERROR: SSL certificates not found after generation"
    exit 1
fi 