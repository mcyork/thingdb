"""
Flask Integration Prototype for Cloudflare Tunnels
This is a simplified version of the remote_access.py from CF.md
"""

from flask import Blueprint, render_template, request, jsonify, current_app
import subprocess
import requests
import json
import base64
import os
import uuid
from datetime import datetime
from typing import Dict, Tuple, Optional

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
        
        try:
            # Verify token
            verify_resp = requests.get(
                'https://api.cloudflare.com/client/v4/user/tokens/verify',
                headers=headers,
                timeout=10
            )
            
            if verify_resp.status_code != 200:
                return False, "Invalid token"
            
            # Check permissions (simplified check)
            perms = verify_resp.json().get('result', {}).get('status')
            if perms != 'active':
                return False, "Token is not active"
                
            return True, None
            
        except Exception as e:
            return False, f"Token validation error: {str(e)}"
    
    def create_tunnel(self, cf_token: str) -> Dict:
        """Create Cloudflare tunnel in customer's account"""
        tunnel_name = f"inventory-pi-{self.device_serial}"
        
        # For testing, we'll simulate tunnel creation
        # In production, you'd use the cloudflared CLI or API
        tunnel_id = f"test-tunnel-{uuid.uuid4().hex[:8]}"
        tunnel_secret = f"test-secret-{uuid.uuid4().hex[:16]}"
        
        return {
            'tunnel_id': tunnel_id,
            'tunnel_secret': tunnel_secret,
            'tunnel_name': tunnel_name
        }
    
    def register_dns_with_worker(self, tunnel_id: str, email: str) -> str:
        """Register DNS via your Cloudflare Worker"""
        # Load device certificate for authentication
        device_cert = None
        if os.path.exists(self.device_cert_path):
            with open(self.device_cert_path, 'rb') as f:
                device_cert = base64.b64encode(f.read()).decode()
        
        headers = {
            'Content-Type': 'application/json'
        }
        
        if device_cert:
            headers['X-Device-Certificate'] = device_cert
        
        response = requests.post(
            self.worker_url,
            json={
                'serial': self.device_serial,
                'tunnel_id': tunnel_id,
                'email': email,
                'timestamp': datetime.utcnow().isoformat()
            },
            headers=headers,
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
        
        # In production, you'd install and start the service
        print(f"Cloudflared config written to: {config_path}")

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
        # In production, check systemctl status
        # For now, return mock status
        return jsonify({
            'active': True,
            'info': {
                'url': 'https://pi-test123.inv.esoup.net'
            }
        })
        
    except Exception as e:
        return jsonify({'active': False, 'error': str(e)})

# Test route for development
@remote_access_bp.route('/api/test-cf-integration')
def test_cf_integration():
    """Test route to verify Cloudflare integration is working"""
    try:
        manager = CloudflareTunnelManager()
        
        return jsonify({
            'success': True,
            'device_serial': manager.device_serial,
            'worker_url': manager.worker_url,
            'cert_exists': os.path.exists(manager.device_cert_path),
            'message': 'Cloudflare integration is ready for testing'
        })
        
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        })
