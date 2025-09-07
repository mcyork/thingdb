# Technical Implementation Document: Cloudflare Tunnel Integration for Inventory Pi

## Executive Summary 

This document outlines the implementation of secure remote access for Inventory Pi devices using Cloudflare Tunnels. Users provide their Cloudflare API token, we automate the entire setup including security configuration, and technical users can optionally add custom domains.

## Architecture Overview

```
┌─────────────┐      ┌──────────────┐      ┌─────────────────┐
│  Customer   │      │   Your CF    │      │  Customer CF    │
│     Pi      │─────▶│   Worker     │      │    Account      │
│             │      │              │      │                 │
│  - Flask    │      │ - Add DNS    │      │ - Tunnel runs   │
│  - Nginx    │      │   pi-XXX.    │      │ - Access rules  │
│  - Self-    │      │   inv.esoup  │      │ - Auth required │
│    signed   │      │   .net       │      │                 │
└─────────────┘      └──────────────┘      └─────────────────┘
        │                                            │
        └────────────────────────────────────────────┘
                    Outbound tunnel connection
```

## Implementation Components

### 1. Flask Application Extension (`/app/remote_access.py`)

```python
"""
remote_access.py - Cloudflare Tunnel setup module
"""

from flask import Blueprint, render_template, request, jsonify, current_app
import subprocess
import requests
import json
import base64
import os
from typing import Dict, Tuple, Optional
import uuid
from datetime import datetime

remote_access_bp = Blueprint('remote_access', __name__)

class CloudflareTunnelManager:
    """Manages Cloudflare tunnel creation and configuration"""
    
    def __init__(self):
        self.device_serial = self._get_device_serial()
        self.worker_url = current_app.config.get(
            'CF_WORKER_URL', 
            'https://register.inv.esoup.net'
        )
        # Leaf certificate for Worker authentication
        self.device_cert_path = '/etc/inventory/device.crt'
        
    def _get_device_serial(self) -> str:
        """Extract unique device identifier"""
        try:
            with open('/proc/cpuinfo', 'r') as f:
                for line in f:
                    if line.startswith('Serial'):
                        # Use last 8 chars of Pi serial
                        return line.split(':')[1].strip()[-8:]
        except:
            # Fallback to MAC-based serial
            import uuid
            return hex(uuid.getnode())[-8:]
    
    def validate_cf_token(self, token: str) -> Tuple[bool, Optional[str]]:
        """Validate Cloudflare API token has required permissions"""
        headers = {
            'Authorization': f'Bearer {token}',
            'Content-Type': 'application/json'
        }
        
        # Verify token
        verify_resp = requests.get(
            'https://api.cloudflare.com/client/v4/user/tokens/verify',
            headers=headers
        )
        
        if verify_resp.status_code != 200:
            return False, "Invalid token"
        
        # Check permissions (simplified check)
        perms = verify_resp.json().get('result', {}).get('status')
        if perms != 'active':
            return False, "Token is not active"
            
        return True, None
    
    def create_tunnel(self, cf_token: str) -> Dict:
        """Create Cloudflare tunnel in customer's account"""
        tunnel_name = f"inventory-pi-{self.device_serial}"
        
        # Use cloudflared CLI to create tunnel
        # Store credentials temporarily
        creds_file = f'/tmp/cf-creds-{uuid.uuid4()}.json'
        
        try:
            # Login with token
            env = os.environ.copy()
            env['TUNNEL_TOKEN'] = cf_token
            
            # Create tunnel via CLI
            result = subprocess.run(
                ['cloudflared', 'tunnel', 'create', '--cred-file', creds_file, tunnel_name],
                capture_output=True,
                text=True,
                env=env
            )
            
            if result.returncode != 0:
                raise Exception(f"Failed to create tunnel: {result.stderr}")
            
            # Parse tunnel ID from credentials file
            with open(creds_file, 'r') as f:
                creds = json.load(f)
                tunnel_id = creds['TunnelID']
                tunnel_secret = creds['TunnelSecret']
            
            # Move credentials to permanent location
            perm_creds = f'/home/pi/.cloudflared/{tunnel_id}.json'
            os.makedirs(os.path.dirname(perm_creds), exist_ok=True)
            os.rename(creds_file, perm_creds)
            
            return {
                'tunnel_id': tunnel_id,
                'tunnel_secret': tunnel_secret,
                'tunnel_name': tunnel_name
            }
            
        finally:
            # Cleanup temp files
            if os.path.exists(creds_file):
                os.remove(creds_file)
    
    def setup_access_policy(self, cf_token: str, tunnel_id: str, 
                          email: str, hostname: str) -> bool:
        """Configure Cloudflare Access to require authentication"""
        headers = {
            'Authorization': f'Bearer {cf_token}',
            'Content-Type': 'application/json'
        }
        
        # Get account ID
        accounts = requests.get(
            'https://api.cloudflare.com/client/v4/accounts',
            headers=headers
        ).json()
        
        account_id = accounts['result'][0]['id']
        
        # Create Access application
        app_data = {
            'name': f'Inventory Pi {self.device_serial}',
            'domain': hostname,
            'type': 'self_hosted',
            'session_duration': '24h',
            'auto_redirect_to_identity': True,
            'allowed_idps': ['email'],  # Email OTP authentication
            'custom_deny_message': 'Access restricted to authorized users only.',
            'logo_url': 'https://your-domain.com/logo.png'  # Optional
        }
        
        app_resp = requests.post(
            f'https://api.cloudflare.com/client/v4/accounts/{account_id}/access/apps',
            headers=headers,
            json=app_data
        )
        
        if app_resp.status_code != 200:
            raise Exception(f"Failed to create Access app: {app_resp.text}")
        
        app_id = app_resp.json()['result']['id']
        
        # Create Access policy - ONLY specified email can access
        policy_data = {
            'name': 'Owner Access Only',
            'precedence': 1,
            'decision': 'allow',
            'include': [
                {'email': {'email': email}}
            ],
            'exclude': [],
            'require': []
        }
        
        policy_resp = requests.post(
            f'https://api.cloudflare.com/client/v4/accounts/{account_id}/access/apps/{app_id}/policies',
            headers=headers,
            json=policy_data
        )
        
        if policy_resp.status_code != 200:
            raise Exception(f"Failed to create Access policy: {policy_resp.text}")
        
        # Add explicit deny-all policy
        deny_policy = {
            'name': 'Deny All Others',
            'precedence': 2,
            'decision': 'deny',
            'include': [{'everyone': {}}]
        }
        
        requests.post(
            f'https://api.cloudflare.com/client/v4/accounts/{account_id}/access/apps/{app_id}/policies',
            headers=headers,
            json=deny_policy
        )
        
        return True
    
    def register_dns_with_worker(self, tunnel_id: str, email: str) -> str:
        """Register DNS via your Cloudflare Worker"""
        # Load device certificate for authentication
        with open(self.device_cert_path, 'rb') as f:
            device_cert = base64.b64encode(f.read()).decode()
        
        response = requests.post(
            self.worker_url,
            json={
                'serial': self.device_serial,
                'tunnel_id': tunnel_id,
                'email': email,
                'timestamp': datetime.utcnow().isoformat()
            },
            headers={
                'X-Device-Certificate': device_cert,
                'Content-Type': 'application/json'
            },
            timeout=30
        )
        
        if response.status_code != 200:
            raise Exception(f"DNS registration failed: {response.text}")
        
        return response.json()['url']
    
    def configure_cloudflared_service(self, tunnel_id: str, hostname: str) -> None:
        """Configure and start cloudflared service"""
        # Write config file
        config = f"""
tunnel: {tunnel_id}
credentials-file: /home/pi/.cloudflared/{tunnel_id}.json

ingress:
  # Primary hostname
  - hostname: {hostname}
    service: https://localhost:443
    originRequest:
      noTLSVerify: true  # Self-signed cert is OK
      
  # Allow any additional customer domains
  - hostname: "*"
    service: https://localhost:443
    originRequest:
      noTLSVerify: true
      
  # Catch-all
  - service: http_status:404
"""
        
        config_path = '/home/pi/.cloudflared/config.yml'
        os.makedirs(os.path.dirname(config_path), exist_ok=True)
        
        with open(config_path, 'w') as f:
            f.write(config)
        
        # Install as systemd service
        subprocess.run(['sudo', 'cloudflared', 'service', 'install'], check=True)
        subprocess.run(['sudo', 'systemctl', 'enable', 'cloudflared'], check=True)
        subprocess.run(['sudo', 'systemctl', 'restart', 'cloudflared'], check=True)

# Flask Routes
@remote_access_bp.route('/remote-access')
def remote_access_setup():
    """Display remote access setup page"""
    return render_template('remote_access.html', 
                         serial=CloudflareTunnelManager()._get_device_serial())

@remote_access_bp.route('/api/setup-tunnel', methods=['POST'])
def setup_tunnel():
    """API endpoint for tunnel setup"""
    try:
        data = request.json
        cf_token = data.get('cf_token', '').strip()
        email = data.get('email', '').strip()
        
        if not cf_token or not email:
            return jsonify({'success': False, 'error': 'Missing required fields'}), 400
        
        manager = CloudflareTunnelManager()
        
        # Validate token
        valid, error = manager.validate_cf_token(cf_token)
        if not valid:
            return jsonify({'success': False, 'error': error}), 400
        
        # Create tunnel
        tunnel_info = manager.create_tunnel(cf_token)
        
        # Register DNS via Worker
        hostname = manager.register_dns_with_worker(
            tunnel_info['tunnel_id'], 
            email
        ).replace('https://', '').replace('http://', '')
        
        # Setup Access policy (require authentication)
        manager.setup_access_policy(
            cf_token,
            tunnel_info['tunnel_id'],
            email,
            hostname
        )
        
        # Configure local service
        manager.configure_cloudflared_service(
            tunnel_info['tunnel_id'],
            hostname
        )
        
        return jsonify({
            'success': True,
            'url': f'https://{hostname}',
            'tunnel_id': tunnel_info['tunnel_id'],
            'message': f'Tunnel configured successfully. Only {email} can access.'
        })
        
    except Exception as e:
        current_app.logger.error(f"Tunnel setup failed: {str(e)}")
        return jsonify({'success': False, 'error': str(e)}), 500

@remote_access_bp.route('/api/tunnel-status')
def tunnel_status():
    """Check tunnel status"""
    try:
        result = subprocess.run(
            ['systemctl', 'is-active', 'cloudflared'],
            capture_output=True,
            text=True
        )
        
        active = result.stdout.strip() == 'active'
        
        # Get tunnel info if available
        tunnel_info = {}
        if active:
            # Parse config to get hostname
            config_path = '/home/pi/.cloudflared/config.yml'
            if os.path.exists(config_path):
                with open(config_path, 'r') as f:
                    for line in f:
                        if 'hostname:' in line:
                            tunnel_info['url'] = line.split(':')[1].strip()
                            break
        
        return jsonify({
            'active': active,
            'info': tunnel_info
        })
        
    except Exception as e:
        return jsonify({'active': False, 'error': str(e)})
```

### 2. Jinja Template (`/templates/remote_access.html`)

```html
{% extends "base.html" %}

{% block title %}Remote Access Setup{% endblock %}

{% block content %}
<div class="container">
    <h1>🔒 Secure Remote Access Setup</h1>
    
    <div class="setup-card">
        <div class="info-box">
            <p>Enable secure remote access to your Inventory Pi from anywhere in the world.</p>
            <p><strong>Device Serial:</strong> <code>{{ serial }}</code></p>
        </div>
        
        <div class="setup-steps">
            <h2>Setup Steps:</h2>
            
            <div class="step">
                <span class="step-number">1</span>
                <div class="step-content">
                    <h3>Create a FREE Cloudflare Account</h3>
                    <p>Click the button below to sign up (opens in new tab)</p>
                    <a href="https://dash.cloudflare.com/sign-up" 
                       target="_blank" 
                       class="btn btn-primary">
                        Sign Up for Cloudflare →
                    </a>
                </div>
            </div>
            
            <div class="step">
                <span class="step-number">2</span>
                <div class="step-content">
                    <h3>Generate Your API Token</h3>
                    <p>After signing up, create an API token with these permissions:</p>
                    <ul>
                        <li>Account → Cloudflare Tunnel: Edit</li>
                        <li>Account → Access: Apps and Policies: Edit</li>
                    </ul>
                    <a href="https://dash.cloudflare.com/profile/api-tokens" 
                       target="_blank"
                       class="btn btn-secondary">
                        Create API Token →
                    </a>
                </div>
            </div>
            
            <div class="step">
                <span class="step-number">3</span>
                <div class="step-content">
                    <h3>Complete Setup</h3>
                    <form id="tunnel-setup-form">
                        <div class="form-group">
                            <label for="cf_token">Cloudflare API Token:</label>
                            <input type="password" 
                                   id="cf_token" 
                                   name="cf_token"
                                   class="form-control" 
                                   placeholder="Paste your token here..."
                                   required>
                            <small class="form-text">Your token is never stored and only used for setup</small>
                        </div>
                        
                        <div class="form-group">
                            <label for="email">Your Email Address:</label>
                            <input type="email" 
                                   id="email" 
                                   name="email"
                                   class="form-control" 
                                   placeholder="you@example.com"
                                   required>
                            <small class="form-text">Only this email will be able to access remotely</small>
                        </div>
                        
                        <button type="submit" 
                                class="btn btn-success btn-lg"
                                id="setup-btn">
                            🚀 Enable Remote Access
                        </button>
                    </form>
                </div>
            </div>
        </div>
        
        <div id="setup-result" style="display: none;">
            <div class="alert alert-success">
                <h3>✅ Setup Complete!</h3>
                <p>Your device is now accessible at:</p>
                <div class="url-display">
                    <code id="device-url"></code>
                    <button onclick="copyUrl()" class="btn btn-sm">Copy</button>
                </div>
                <p class="mt-3">
                    <strong>Note:</strong> You'll need to authenticate with your email 
                    when accessing remotely.
                </p>
            </div>
        </div>
        
        <div id="setup-error" style="display: none;">
            <div class="alert alert-danger">
                <h3>❌ Setup Failed</h3>
                <p id="error-message"></p>
                <button onclick="resetForm()" class="btn btn-warning">Try Again</button>
            </div>
        </div>
        
        <!-- Advanced users section -->
        <details class="advanced-section">
            <summary>Advanced: Use Your Own Domain</summary>
            <div class="advanced-content">
                <p>After setup completes, you can point your own domain to this device:</p>
                <div class="dns-instructions">
                    <table class="table">
                        <tr>
                            <td><strong>Type:</strong></td>
                            <td><code>CNAME</code></td>
                        </tr>
                        <tr>
                            <td><strong>Name:</strong></td>
                            <td><code>inventory</code> (or your preferred subdomain)</td>
                        </tr>
                        <tr>
                            <td><strong>Value:</strong></td>
                            <td><code id="tunnel-endpoint">[Tunnel ID].cfargotunnel.com</code></td>
                        </tr>
                    </table>
                    <p class="text-info">
                        <i class="fas fa-info-circle"></i>
                        Your access restrictions will apply to all domains automatically.
                    </p>
                </div>
            </div>
        </details>
        
        <!-- Security notice -->
        <div class="security-notice">
            <h4>🔐 Security Information</h4>
            <ul>
                <li>Remote access requires email authentication (enforced by Cloudflare)</li>
                <li>Your API token is used only for setup and never stored</li>
                <li>Local access via <code>https://inventory.local</code> always works</li>
                <li>You can revoke access anytime from your Cloudflare dashboard</li>
            </ul>
        </div>
    </div>
</div>

<script>
document.getElementById('tunnel-setup-form').addEventListener('submit', async (e) => {
    e.preventDefault();
    
    const setupBtn = document.getElementById('setup-btn');
    const originalText = setupBtn.innerHTML;
    
    // Show loading state
    setupBtn.disabled = true;
    setupBtn.innerHTML = '<span class="spinner-border spinner-border-sm"></span> Setting up...';
    
    const formData = {
        cf_token: document.getElementById('cf_token').value,
        email: document.getElementById('email').value
    };
    
    try {
        const response = await fetch('/api/setup-tunnel', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify(formData)
        });
        
        const result = await response.json();
        
        if (result.success) {
            // Show success
            document.getElementById('device-url').textContent = result.url;
            document.getElementById('tunnel-endpoint').textContent = 
                `${result.tunnel_id}.cfargotunnel.com`;
            document.getElementById('setup-result').style.display = 'block';
            document.getElementById('tunnel-setup-form').style.display = 'none';
        } else {
            // Show error
            document.getElementById('error-message').textContent = result.error;
            document.getElementById('setup-error').style.display = 'block';
        }
    } catch (error) {
        document.getElementById('error-message').textContent = 
            'Network error. Please check your connection.';
        document.getElementById('setup-error').style.display = 'block';
    } finally {
        setupBtn.disabled = false;
        setupBtn.innerHTML = originalText;
    }
});

function copyUrl() {
    const url = document.getElementById('device-url').textContent;
    navigator.clipboard.writeText(url);
    // Show feedback
    event.target.textContent = 'Copied!';
    setTimeout(() => {
        event.target.textContent = 'Copy';
    }, 2000);
}

function resetForm() {
    document.getElementById('setup-error').style.display = 'none';
    document.getElementById('tunnel-setup-form').reset();
}
</script>

<style>
.setup-card {
    background: white;
    border-radius: 8px;
    padding: 2rem;
    box-shadow: 0 2px 4px rgba(0,0,0,0.1);
}

.step {
    display: flex;
    margin: 2rem 0;
    align-items: flex-start;
}

.step-number {
    background: #0066cc;
    color: white;
    width: 32px;
    height: 32px;
    border-radius: 50%;
    display: flex;
    align-items: center;
    justify-content: center;
    font-weight: bold;
    margin-right: 1rem;
    flex-shrink: 0;
}

.url-display {
    background: #f5f5f5;
    padding: 1rem;
    border-radius: 4px;
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin: 1rem 0;
}

.url-display code {
    font-size: 1.1rem;
    color: #0066cc;
}

.advanced-section {
    margin-top: 3rem;
    padding: 1rem;
    background: #f9f9f9;
    border-radius: 4px;
}

.security-notice {
    margin-top: 2rem;
    padding: 1rem;
    background: #e3f2fd;
    border-left: 4px solid #2196f3;
    border-radius: 4px;
}

.dns-instructions {
    background: white;
    padding: 1rem;
    border-radius: 4px;
    margin-top: 1rem;
}
</style>
{% endblock %}
```

### 3. Cloudflare Worker (`worker.js`)

```javascript
/**
 * Cloudflare Worker for DNS Registration
 * Deployed to your Cloudflare account
 */

// Environment variables (set via wrangler or dashboard):
// CF_API_TOKEN - Your Cloudflare API token
// ZONE_ID - Zone ID for inv.esoup.net
// LEAF_CERT_HASH - SHA256 hash of device certificate

addEventListener('fetch', event => {
  event.respondWith(handleRequest(event.request))
})

/**
 * Rate limiting using Cloudflare KV
 */
async function checkRateLimit(serial) {
  if (typeof RATE_LIMIT_KV === 'undefined') {
    return true; // KV not configured, skip rate limiting
  }
  
  const key = `rate:${serial}`;
  const lastRequest = await RATE_LIMIT_KV.get(key);
  
  if (lastRequest) {
    const timeSince = Date.now() - parseInt(lastRequest);
    if (timeSince < 3600000) { // 1 hour
      return false;
    }
  }
  
  await RATE_LIMIT_KV.put(key, Date.now().toString(), {
    expirationTtl: 3600
  });
  
  return true;
}

/**
 * Verify device certificate
 */
async function verifyCertificate(certHeader) {
  if (!certHeader) {
    return false;
  }
  
  // Simple verification: check certificate hash
  const encoder = new TextEncoder();
  const data = encoder.encode(certHeader);
  const hashBuffer = await crypto.subtle.digest('SHA-256', data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  const hashHex = hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
  
  return hashHex === LEAF_CERT_HASH;
}

/**
 * Main request handler
 */
async function handleRequest(request) {
  // Only accept POST requests
  if (request.method !== 'POST') {
    return new Response('Method not allowed', { 
      status: 405,
      headers: { 'Content-Type': 'text/plain' }
    });
  }
  
  try {
    // Verify certificate
    const certHeader = request.headers.get('X-Device-Certificate');
    if (!await verifyCertificate(certHeader)) {
      return new Response(JSON.stringify({
        success: false,
        error: 'Invalid certificate'
      }), { 
        status: 401,
        headers: { 'Content-Type': 'application/json' }
      });
    }
    
    // Parse request body
    const data = await request.json();
    const { serial, tunnel_id, email, timestamp } = data;
    
    // Validate input
    if (!serial || !tunnel_id || !email) {
      return new Response(JSON.stringify({
        success: false,
        error: 'Missing required fields'
      }), { 
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }
    
    // Check rate limit
    if (!await checkRateLimit(serial)) {
      return new Response(JSON.stringify({
        success: false,
        error: 'Rate limited. Please wait before retrying.'
      }), { 
        status: 429,
        headers: { 'Content-Type': 'application/json' }
      });
    }
    
    // Sanitize serial for DNS
    const cleanSerial = serial.replace(/[^a-zA-Z0-9-]/g, '').toLowerCase();
    const hostname = `pi-${cleanSerial}`.substring(0, 63); // DNS label limit
    
    // Check if record already exists
    const existingCheck = await fetch(
      `https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?name=${hostname}.inv.esoup.net`,
      {
        headers: {
          'Authorization': `Bearer ${CF_API_TOKEN}`,
          'Content-Type': 'application/json'
        }
      }
    );
    
    const existing = await existingCheck.json();
    
    if (existing.result && existing.result.length > 0) {
      // Update existing record
      const recordId = existing.result[0].id;
      const updateResponse = await fetch(
        `https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${recordId}`,
        {
          method: 'PUT',
          headers: {
            'Authorization': `Bearer ${CF_API_TOKEN}`,
            'Content-Type': 'application/json'
          },
          body: JSON.stringify({
            type: 'CNAME',
            name: hostname,
            content: `${tunnel_id}.cfargotunnel.com`,
            ttl: 300,
            proxied: false
          })
        }
      );
      
      if (!updateResponse.ok) {
        throw new Error('Failed to update DNS record');
      }
    } else {
      // Create new record
      const createResponse = await fetch(
        `https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records`,
        {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${CF_API_TOKEN}`,
            'Content-Type': 'application/json'
          },
          body: JSON.stringify({
            type: 'CNAME',
            name: hostname,
            content: `${tunnel_id}.cfargotunnel.com`,
            ttl: 300,
            proxied: false
          })
        }
      );
      
      if (!createResponse.ok) {
        const error = await createResponse.text();
        throw new Error(`Failed to create DNS record: ${error}`);
      }
    }
    
    // Log registration (optional)
    if (typeof REGISTRATIONS_KV !== 'undefined') {
      await REGISTRATIONS_KV.put(
        `device:${cleanSerial}`,
        JSON.stringify({
          tunnel_id,
          email,
          registered_at: timestamp || new Date().toISOString()
        })
      );
    }
    
    // Return success response
    return new Response(JSON.stringify({
      success: true,
      url: `https://${hostname}.inv.esoup.net`,
      tunnel_id: tunnel_id
    }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    });
    
  } catch (error) {
    console.error('Worker error:', error);
    
    return new Response(JSON.stringify({
      success: false,
      error: error.message || 'Internal server error'
    }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
}
```

### 4. Worker Deployment (`wrangler.toml`)

```toml
name = "inventory-pi-registration"
main = "worker.js"
compatibility_date = "2023-10-01"

[vars]
ZONE_ID = "your-zone-id-for-inv-esoup-net"
LEAF_CERT_HASH = "sha256-hash-of-your-device-certificate"

# KV Namespaces (optional)
[[kv_namespaces]]
binding = "RATE_LIMIT_KV"
id = "your-kv-namespace-id"

[[kv_namespaces]]
binding = "REGISTRATIONS_KV"
id = "your-registrations-kv-id"

# Custom domain (optional)
routes = [
  { pattern = "register.inv.esoup.net", zone_id = "your-zone-id" }
]

# Secrets (add via CLI)
# wrangler secret put CF_API_TOKEN
```

## Self-Signed Certificate Handling

The self-signed certificate on Nginx is **not a problem**. The Cloudflare tunnel configuration includes `noTLSVerify: true` which allows the tunnel to connect to your self-signed HTTPS endpoint. Users never see this certificate - they only see Cloudflare's valid certificate.

## User Documentation

### For Basic Users

```markdown
# Enabling Remote Access

Remote access allows you to connect to your Inventory Pi from anywhere in the world, securely.

## Quick Setup (2 minutes)

1. **Create a FREE Cloudflare account**
   - Visit: https://dash.cloudflare.com/sign-up
   - Sign up with your email

2. **Generate an API token**
   - Visit: https://dash.cloudflare.com/profile/api-tokens
   - Click "Create Token" → "Get started"
   - Add these permissions:
     * Account → Cloudflare Tunnel: Edit
     * Account → Access: Apps and Policies: Edit
   - Click "Continue to summary" → "Create Token"
   - Copy the token

3. **Complete setup on your Pi**
   - Go to your Pi's web interface
   - Navigate to Settings → Remote Access
   - Paste your token and email
   - Click "Enable Remote Access"

That's it! You'll receive a secure URL like:
`https://pi-abc123.inv.esoup.net`

When you visit this URL, you'll be asked to verify your email (one-time PIN sent to your inbox).
```

### For Technical Users

```markdown
# Advanced Configuration

## Using Your Own Domain

After completing the basic setup, you can point your own domain to your Pi:

1. Your tunnel ID is shown after setup (or in the Cloudflare dashboard)
2. Add a CNAME record in your DNS:
   ```
   Type: CNAME
   Name: inventory.yourdomain.com
   Value: [tunnel-id].cfargotunnel.com
   TTL: 300
   ```

## Security Configuration

Access rules are configured by default to require email authentication. 
To modify:

1. Log into your Cloudflare dashboard
2. Navigate to Zero Trust → Access → Applications
3. Find your "Inventory Pi" application
4. Modify policies as needed

⚠️ **Warning**: Removing authentication exposes your device to the internet.
Only do this if you understand the security implications.

## Multiple Domains

You can point multiple domains to the same tunnel. All domains will share
the same access rules.

## Removing Remote Access

To disable remote access:
1. Stop the tunnel: `sudo systemctl stop cloudflared`
2. Disable auto-start: `sudo systemctl disable cloudflared`
3. Delete the tunnel in your Cloudflare dashboard (optional)
```

## Monetization Options

### Option 1: One-Time Setup Fee
```python
class SetupFeeModel:
    """
    Charge for the convenience of automation
    """
    pricing = {
        "basic": {
            "price": "$9.99",
            "includes": [
                "Automated tunnel setup",
                "DNS configuration",
                "Security configuration",
                "Basic email support"
            ]
        },
        "pro": {
            "price": "$19.99",
            "includes": [
                "Everything in Basic",
                "Custom domain setup assistance",
                "Priority support",
                "Video walkthrough"
            ]
        }
    }
```

### Option 2: Donation/Tip Model
```python
class DonationModel:
    """
    Optional contributions
    """
    options = {
        "coffee": "$3 - Buy us a coffee",
        "pizza": "$10 - Buy us a pizza",
        "support": "$25 - Support development",
        "amazon_wishlist": "Link to project wishlist"
    }
    
    implementation = """
    After successful setup:
    'Enjoy your secure remote access! 
     If this saved you time, consider [supporting the project]'
    """
```

### Option 3: Support Subscription
```python
class SupportSubscription:
    """
    Optional support tier
    """
    pricing = {
        "community": {
            "price": "$0/month",
            "support": "Community forum",
            "updates": "Quarterly"
        },
        "supporter": {
            "price": "$2.99/month",
            "support": "Email support",
            "updates": "Monthly",
            "perks": [
                "Early access to features",
                "Support badge",
                "Priority bug fixes"
            ]
        }
    }
```

### Option 4: Professional Services
```python
class ProfessionalServices:
    """
    For business customers
    """
    services = {
        "bulk_provisioning": {
            "price": "$100",
            "description": "Pre-configure 10+ devices"
        },
        "white_label": {
            "price": "$500",
            "description": "Custom domain, branding"
        },
        "training": {
            "price": "$200/hour",
            "description": "Team training session"
        }
    }
```

## Testing Checklist

- [ ] Token validation handles invalid tokens gracefully
- [ ] Tunnel creation works with free CF accounts
- [ ] Access policy correctly restricts to specified email
- [ ] DNS record creates successfully via Worker
- [ ] Self-signed cert doesn't break tunnel
- [ ] Service starts automatically on boot
- [ ] Error messages are user-friendly
- [ ] Rate limiting prevents abuse
- [ ] Certificate authentication works
- [ ] Advanced users can add custom domains

## Security Considerations

1. **API Token Handling**: Token is never stored, only used during setup
2. **Access Enforcement**: Cloudflare Access ensures authentication
3. **Certificate Validation**: Worker validates device certificate
4. **Rate Limiting**: Prevents abuse of Worker endpoint
5. **Self-Signed Cert**: Only used between tunnel and local Nginx, not exposed to users

## Deployment Steps

1. Deploy Worker to your Cloudflare account
2. Add Flask blueprint to your application
3. Create Jinja template
4. Install cloudflared on Pi image
5. Include device certificate in Pi image
6. Test end-to-end flow

---

## New information

Here’s a first draft of the document you’re describing. I’ve kept it focused on **your system with Ed25519**, no compare-and-contrast with other curves except a small appendix where I cover deterministic derivation.

---

# 🔐 Ed25519 Certificate & Key Use in IoT Patch Signing System

## 1. System Overview

The system consists of three main actors:

1. **Development System (Build Environment)**

   * Holds the **Ed25519 private key**.
   * Signs software patches and update bundles before they are distributed.
   * Private key **never leaves this system**.

2. **Raspberry Pi Fleet (Deployed IoT Devices)**

   * Each Pi contains the **same Ed25519 leaf certificate** (public key only).
   * Uses this certificate to verify signatures on update bundles and payloads from the development system.
   * No private key is stored on the Pis.
   * Certificate chain (root + intermediate + leaf) is embedded in the image.

3. **Cloudflare Worker Node (Verification & Coordination)**

   * Receives signed payloads from Pis.
   * Uses the **Ed25519 public key** (from the leaf certificate) to verify Pi-generated signatures.
   * May also need to verify update package signatures before approving or distributing them.
   * Never holds a private key; verification only.

---

## 2. Key & Certificate Placement

* **Root Certificate (self-controlled):**

  * Stays offline in cold storage.
  * Used only to sign an intermediate certificate.

* **Intermediate Certificate (Ed25519):**

  * Held securely in the development system.
  * Used to sign the leaf certificate.
  * Private key never leaves the development environment.

* **Leaf Certificate (Ed25519):**

  * Public key only, embedded in every Pi image.
  * Trusted by Worker nodes for verification.
  * No uniqueness per Pi (all share the same leaf).

* **Leaf Private Key:**

  * Stored only in the development system and (optionally) in Cloudflare Workers Secrets.
  * Used for signing patch bundles and payloads.

---

## 3. Cloudflare Worker Considerations

Cloudflare Workers run in a sandboxed JS environment with the Web Crypto API, which **does not currently support Ed25519 natively**.
Therefore, a small external JavaScript library is required for signature verification.

### Recommended Library

* **[tweetnacl-js](https://github.com/dchest/tweetnacl-js)**

  * \~25 KB minified.
  * Pure JavaScript (no WASM required).
  * Implements Ed25519 signature verify and sign.
  * Actively maintained and widely trusted.

**Usage Example (Worker side):**

```js
import nacl from "tweetnacl";

export default {
  async fetch(request, env) {
    const body = await request.arrayBuffer();
    const signature = new Uint8Array([...]); // from request
    const message = new Uint8Array(body);
    const publicKey = new Uint8Array(env.ED25519_PUBKEY); // stored as secret

    const valid = nacl.sign.detached.verify(message, signature, publicKey);
    return new Response(valid ? "Signature OK" : "Signature INVALID");
  }
};
```

---

## 4. Development Workflow

1. Developer compiles and packages a new patch.
2. Patch is hashed and signed with the **Ed25519 private key**.
3. Patch + signature are distributed.
4. Pis verify the patch with their embedded **leaf public key**.
5. Worker nodes verify any payloads received from Pis using the same public key.

At no point do Pis or Workers require the private key. Only the development system (and optionally Workers if they need to sign responses) ever holds it.

---

## 5. Security Properties

* **Confidentiality:** Private keys never leave the development system.
* **Integrity:** Every update is verifiable against the embedded certificate chain.
* **Uniform Trust:** All Pis share the same leaf cert, simplifying fleet management.
* **Resilience:** Even if a Pi is compromised, the attacker cannot sign valid patches (no private key present).

---

## Appendix A: Deterministic Keys (Future Consideration)

In future versions, you may want per-device keys derived deterministically.
Ed25519 lends itself well to this because the private key seed is just 32 bytes.

### Possible Approach:

* Take the Pi’s **serial number** as the seed input.
* Apply a Key Derivation Function (e.g., HKDF with a secret salt).
* Output → 32-byte seed → Ed25519 private key.

This ensures:

* Same Pi serial number always regenerates the same key.
* No key database required.
* Still cryptographically valid (though serial numbers are weak entropy).

⚠️ Note: Since Pi serials are not secret, you’d want to combine them with an additional secret (salt) stored only in your build system, to avoid brute force risks.

---

## Summary

For your application:

* Use **Ed25519** for compact, fast signatures.
* Store private keys only in your development system.
* Deploy the public leaf cert across all Pis.
* Verify signatures in Cloudflare Workers using **tweetnacl-js** (small, pure JS library).
* Optionally, consider deterministic key derivation later if you want per-device uniqueness.

---



*This implementation provides a secure, user-friendly remote access solution with zero ongoing costs for most deployments.*