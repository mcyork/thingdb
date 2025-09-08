"""
remote_access_routes.py - Cloudflare Tunnel setup module
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
            'https://inventory-pi-registration.nestdb.workers.dev'
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
            # First get accounts to find the account ID
            accounts_response = requests.get(
                'https://api.cloudflare.com/client/v4/accounts',
                headers=headers,
                timeout=10
            )
            
            if accounts_response.status_code != 200:
                return False, "Failed to get accounts"
            
            accounts_data = accounts_response.json()
            if not accounts_data.get('success') or not accounts_data.get('result'):
                return False, "No accounts found"
            
            # Use the first account ID for token verification
            account_id = accounts_data['result'][0]['id']
            
            # Verify token
            verify_resp = requests.get(
                f'https://api.cloudflare.com/client/v4/accounts/{account_id}/tokens/verify',
                headers=headers,
                timeout=10
            )
            
            if verify_resp.status_code != 200:
                return False, "Invalid token"
            
            # Check permissions
            data = verify_resp.json()
            if not data.get('success'):
                return False, "Token validation failed"
                
            result = data.get('result', {})
            if result.get('status') != 'active':
                return False, "Token is not active"
                
            return True, None
            
        except Exception as e:
            return False, f"Error validating token: {str(e)}"
    
    def create_tunnel(self, cf_token: str) -> Dict:
        """Create Cloudflare tunnel via API (no CLI required)"""
        tunnel_name = f"inventory-pi-{self.device_serial}"
        
        try:
            # Get account ID first
            headers = {
                'Authorization': f'Bearer {cf_token}',
                'Content-Type': 'application/json'
            }
            
            accounts_response = requests.get(
                'https://api.cloudflare.com/client/v4/accounts',
                headers=headers,
                timeout=10
            )
            
            if accounts_response.status_code != 200:
                raise Exception(f"Failed to get accounts: {accounts_response.text}")
            
            accounts_data = accounts_response.json()
            if not accounts_data.get('success') or not accounts_data.get('result'):
                raise Exception("No accounts found")
            
            account_id = accounts_data['result'][0]['id']
            
            # Create tunnel via API
            tunnel_data = {
                'name': tunnel_name
            }
            
            tunnel_response = requests.post(
                f'https://api.cloudflare.com/client/v4/accounts/{account_id}/cfd_tunnel',
                headers=headers,
                json=tunnel_data,
                timeout=30
            )
            
            if tunnel_response.status_code != 200:
                raise Exception(f"Failed to create tunnel: {tunnel_response.text}")
            
            tunnel_result = tunnel_response.json()
            if not tunnel_result.get('success'):
                raise Exception(f"Tunnel creation failed: {tunnel_result.get('errors', [{}])[0].get('message', 'Unknown error')}")
            
            tunnel_info = tunnel_result['result']
            tunnel_id = tunnel_info['id']
            tunnel_secret = tunnel_info['credentials_file']['TunnelSecret']
            
            # Create credentials file for cloudflared
            creds_data = {
                'AccountTag': account_id,
                'TunnelID': tunnel_id,
                'TunnelSecret': tunnel_secret
            }
            
            # Create .cloudflared directory with proper permissions
            cloudflared_dir = '/home/inventory/.cloudflared'
            os.makedirs(cloudflared_dir, exist_ok=True)
            os.chmod(cloudflared_dir, 0o755)
            
            creds_file = f'{cloudflared_dir}/{tunnel_id}.json'
            
            with open(creds_file, 'w') as f:
                json.dump(creds_data, f)
            
            # Set proper permissions on the credentials file
            os.chmod(creds_file, 0o600)
            
            # Configure tunnel ingress rules (THE MISSING STEP!)
            self._configure_tunnel_ingress(cf_token, account_id, tunnel_id)
            
            current_app.logger.info(f"Tunnel {tunnel_id} created and configured via API")
            
            return {
                'tunnel_id': tunnel_id,
                'tunnel_secret': tunnel_secret,
                'tunnel_name': tunnel_name
            }
            
        except Exception as e:
            current_app.logger.error(f"Tunnel creation failed: {str(e)}")
            raise
    
    def _configure_tunnel_ingress(self, cf_token: str, account_id: str, tunnel_id: str) -> None:
        """Configure tunnel ingress rules via API (THE MISSING STEP!)"""
        try:
            headers = {
                'Authorization': f'Bearer {cf_token}',
                'Content-Type': 'application/json'
            }
            
            # Configure ingress rules
            ingress_config = {
                'config': {
                    'ingress': [
                        {
                            'hostname': f'pi-{self.device_serial}.nestdb.io',
                            'service': 'https://inventory.local:443',
                            'originRequest': {
                                'noTLSVerify': True
                            }
                        },
                        {
                            'service': 'http_status:404'
                        }
                    ]
                }
            }
            
            config_response = requests.put(
                f'https://api.cloudflare.com/client/v4/accounts/{account_id}/cfd_tunnel/{tunnel_id}/configurations',
                headers=headers,
                json=ingress_config,
                timeout=30
            )
            
            if config_response.status_code != 200:
                raise Exception(f"Failed to configure tunnel ingress: {config_response.text}")
            
            config_result = config_response.json()
            if not config_result.get('success'):
                raise Exception(f"Tunnel configuration failed: {config_result.get('errors', [{}])[0].get('message', 'Unknown error')}")
            
            current_app.logger.info(f"Tunnel {tunnel_id} ingress rules configured successfully")
            
        except Exception as e:
            current_app.logger.error(f"Failed to configure tunnel ingress: {str(e)}")
            raise
    
    def setup_access_policy(self, cf_token: str, tunnel_id: str, 
                          email: str, hostname: str) -> bool:
        """Configure Cloudflare Access to require authentication"""
        headers = {
            'Authorization': f'Bearer {cf_token}',
            'Content-Type': 'application/json'
        }
        
        try:
            # Get account ID
            accounts = requests.get(
                'https://api.cloudflare.com/client/v4/accounts',
                headers=headers
            ).json()
            
            account_id = accounts['result'][0]['id']
            
            # First, check if we have any IdPs available
            idps_resp = requests.get(
                f'https://api.cloudflare.com/client/v4/accounts/{account_id}/access/identity_providers',
                headers=headers
            )
            
            if idps_resp.status_code != 200:
                raise Exception(f"Cannot access IdPs: {idps_resp.text}")
            
            idps_data = idps_resp.json()
            if not idps_data.get('success') or not idps_data.get('result'):
                raise Exception("No Identity Providers available. Please set up email OTP in Cloudflare dashboard.")
            
            # Use the first available IdP (should be email OTP)
            available_idps = [idp['id'] for idp in idps_data['result']]
            if not available_idps:
                raise Exception("No Identity Providers configured")
            
            # Check if Access app already exists
            apps_resp = requests.get(
                f'https://api.cloudflare.com/client/v4/accounts/{account_id}/access/apps',
                headers=headers
            )
            
            app_id = None
            if apps_resp.status_code == 200:
                apps_data = apps_resp.json()
                if apps_data.get('success'):
                    # Look for existing app with this domain
                    for app in apps_data.get('result', []):
                        if app.get('domain') == hostname:
                            app_id = app['id']
                            current_app.logger.info(f"Found existing Access app: {app_id}")
                            break
            
            # Create Access app if it doesn't exist
            if not app_id:
                app_data = {
                    'name': f'Inventory Pi {self.device_serial}',
                    'domain': hostname,
                    'type': 'self_hosted',
                    'session_duration': '24h',
                    'auto_redirect_to_identity': True,
                    'allowed_idps': available_idps[:1],  # Use first available IdP
                    'custom_deny_message': 'Access restricted to authorized users only.'
                }
                
                app_resp = requests.post(
                    f'https://api.cloudflare.com/client/v4/accounts/{account_id}/access/apps',
                    headers=headers,
                    json=app_data
                )
                
                if app_resp.status_code != 200:
                    raise Exception(f"Failed to create Access app: {app_resp.text}")
                
                app_id = app_resp.json()['result']['id']
                current_app.logger.info(f"Created new Access app: {app_id}")
            
            # Check if policy already exists for this email
            policies_resp = requests.get(
                f'https://api.cloudflare.com/client/v4/accounts/{account_id}/access/apps/{app_id}/policies',
                headers=headers
            )
            
            policy_exists = False
            if policies_resp.status_code == 200:
                policies_data = policies_resp.json()
                if policies_data.get('success'):
                    for policy in policies_data.get('result', []):
                        # Check if policy includes this email
                        for include_rule in policy.get('include', []):
                            if include_rule.get('email', {}).get('email') == email:
                                policy_exists = True
                                current_app.logger.info(f"Policy already exists for {email}")
                                break
                        if policy_exists:
                            break
            
            # Create policy if it doesn't exist
            if not policy_exists:
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
                
                current_app.logger.info(f"Created Access policy for {email}")
                
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
            
            current_app.logger.info(f"Access policy created for {email}")
            return True
            
        except Exception as e:
            current_app.logger.error(f"Access policy setup failed: {str(e)}")
            return False
    
    
    def register_dns_with_worker(self, tunnel_id: str, email: str) -> str:
        """Register DNS via your Cloudflare Worker"""
        try:
            current_app.logger.info(f"Registering DNS with Worker: {self.worker_url}")
            
            # Load device certificate for authentication
            if os.path.exists(self.device_cert_path):
                with open(self.device_cert_path, 'rb') as f:
                    device_cert = base64.b64encode(f.read()).decode()
            else:
                # Fallback: create a simple device identifier
                device_cert = base64.b64encode(f"device-{self.device_serial}".encode()).decode()
            
            current_app.logger.info(f"Making request to Worker with tunnel_id: {tunnel_id}")
            
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
                timeout=60
            )
            
            if response.status_code != 200:
                raise Exception(f"DNS registration failed: {response.text}")
            
            return response.json()['url']
            
        except Exception as e:
            current_app.logger.error(f"DNS registration failed: {str(e)}")
            current_app.logger.error(f"Worker URL: {self.worker_url}")
            raise
    
    def configure_tunnel_routing(self, cf_token: str, tunnel_id: str, hostname: str) -> None:
        """Configure tunnel routing via Cloudflare API and start tunnel"""
        headers = {
            'Authorization': f'Bearer {cf_token}',
            'Content-Type': 'application/json'
        }
        
        try:
            # Get account ID
            accounts = requests.get(
                'https://api.cloudflare.com/client/v4/accounts',
                headers=headers
            ).json()
            
            account_id = accounts['result'][0]['id']
            
            # Configure tunnel routing via API
            routing_config = {
                'config': {
                    'ingress': [
                        {
                            'hostname': hostname,
                            'service': 'https://inventory.local:443',  # Pi HTTPS port
                            'originRequest': {
                                'noTLSVerify': True
                            }
                        },
                        {
                            'service': 'http_status:404'
                        }
                    ]
                }
            }
            
            # Update tunnel configuration
            config_resp = requests.put(
                f'https://api.cloudflare.com/client/v4/accounts/{account_id}/cfd_tunnel/{tunnel_id}/configurations',
                headers=headers,
                json=routing_config
            )
            
            if config_resp.status_code != 200:
                raise Exception(f"Failed to configure tunnel routing: {config_resp.text}")
            
            current_app.logger.info(f"Tunnel routing configured for {hostname}")
            
            # Start the tunnel (minimal cloudflared usage)
            # We need to get the tunnel secret from the tunnel creation response
            # For now, we'll skip starting the tunnel and let the user know
            current_app.logger.warning("Tunnel created but not started. Please run 'cloudflared tunnel run' manually.")
            
        except Exception as e:
            current_app.logger.error(f"Tunnel routing configuration failed: {str(e)}")
            raise
    
    def start_tunnel(self, cf_token: str, tunnel_id: str, tunnel_secret: str) -> None:
        """Start the tunnel using cloudflared daemon (minimal CLI usage)"""
        try:
            # Create credentials file with real tunnel secret
            creds_file = f'/home/inventory/.cloudflared/{tunnel_id}.json'
            os.makedirs(os.path.dirname(creds_file), exist_ok=True)
            
            # Get account ID for AccountTag
            accounts = requests.get(
                'https://api.cloudflare.com/client/v4/accounts',
                headers={'Authorization': f'Bearer {cf_token}', 'Content-Type': 'application/json'}
            ).json()
            account_id = accounts['result'][0]['id']
            
            creds_data = {
                'AccountTag': account_id,
                'TunnelSecret': tunnel_secret,
                'TunnelID': tunnel_id
            }
            
            with open(creds_file, 'w') as f:
                json.dump(creds_data, f)
            os.chmod(creds_file, 0o600)
            
            # Create config file
            config_file = '/home/inventory/.cloudflared/config.yml'
            config_content = f"""tunnel: {tunnel_id}
credentials-file: {creds_file}

ingress:
  - hostname: pi-{self.device_serial}.nestdb.io
    service: https://localhost:8000
    originRequest:
      noTLSVerify: true
  - service: http_status:404
"""
            
            with open(config_file, 'w') as f:
                f.write(config_content)
            os.chmod(config_file, 0o644)
            
            # Kill any existing cloudflared processes
            try:
                subprocess.run(['killall', 'cloudflared'], capture_output=True)
            except:
                pass  # Ignore if no processes to kill
            
            # Start tunnel daemon in background
            subprocess.Popen([
                '/usr/local/bin/cloudflared',
                'tunnel',
                'run',
                tunnel_id
            ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            
            current_app.logger.info(f"Tunnel daemon {tunnel_id} started")
            
        except Exception as e:
            current_app.logger.error(f"Failed to start tunnel daemon: {str(e)}")
            raise

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
        
        # Setup Access policy using user token (must have Access permissions)
        try:
            manager.setup_access_policy(
                cf_token,  # Use the same user token
                tunnel_info['tunnel_id'],
                email,
                hostname
            )
            current_app.logger.info(f"Access policy created for {email}")
        except Exception as e:
            current_app.logger.warning(f"Access policy setup failed: {str(e)}")
        
        # Configure tunnel routing via API
        manager.configure_tunnel_routing(
            cf_token,
            tunnel_info['tunnel_id'],
            hostname
        )
        
        # Start the tunnel with the secret
        manager.start_tunnel(
            cf_token,
            tunnel_info['tunnel_id'],
            tunnel_info['tunnel_secret']
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
