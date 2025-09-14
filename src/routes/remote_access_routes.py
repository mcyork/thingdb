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
        # Tunnel configuration storage
        self.config_file = '/var/lib/inventory/tunnel_config.json'
        
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
    
    def _save_tunnel_config(self, tunnel_data: Dict) -> None:
        """Save tunnel configuration to persistent storage"""
        try:
            os.makedirs(os.path.dirname(self.config_file), exist_ok=True)
            with open(self.config_file, 'w') as f:
                json.dump(tunnel_data, f, indent=2)
            os.chmod(self.config_file, 0o600)  # Secure permissions
            current_app.logger.info(f"Tunnel configuration saved to {self.config_file}")
        except Exception as e:
            current_app.logger.error(f"Failed to save tunnel config: {str(e)}")
    
    def _load_tunnel_config(self) -> Optional[Dict]:
        """Load tunnel configuration from persistent storage"""
        try:
            if os.path.exists(self.config_file):
                with open(self.config_file, 'r') as f:
                    return json.load(f)
        except Exception as e:
            current_app.logger.error(f"Failed to load tunnel config: {str(e)}")
        return None
    
    def get_tunnel_status(self) -> Dict:
        """Get current tunnel status and configuration"""
        config = self._load_tunnel_config()
        if not config:
            return {
                'configured': False,
                'status': 'Not configured',
                'url': None,
                'tunnel_id': None,
                'email': None,
                'emails': [],
                'created_at': None
            }
        
        # Check if tunnel is actually running
        try:
            # Check if cloudflared service is running
            result = subprocess.run(['/usr/bin/sudo', 'systemctl', 'is-active', 'cloudflared.service'], 
                                  capture_output=True, text=True, timeout=5)
            service_running = result.returncode == 0 and 'active' in result.stdout
            
            # Check if config file exists and matches
            config_exists = os.path.exists('/etc/cloudflared/config.yml')
            config_matches = False
            if config_exists:
                with open('/etc/cloudflared/config.yml', 'r') as f:
                    config_content = f.read()
                    config_matches = config.get('tunnel_id') in config_content
            
            if service_running and config_matches:
                status = 'Active'
            elif service_running:
                status = 'Running (config mismatch)'
            else:
                status = 'Inactive'
                
        except Exception as e:
            current_app.logger.error(f"Failed to check tunnel status: {str(e)}")
            status = 'Unknown'
        
        return {
            'configured': True,
            'status': status,
            'url': config.get('url'),
            'tunnel_id': config.get('tunnel_id'),
            'email': config.get('email'),
            'emails': config.get('emails', [config.get('email')] if config.get('email') else []),
            'created_at': config.get('created_at'),
            'service_running': service_running if 'service_running' in locals() else False
        }
    
    def add_email_to_access_policy(self, cf_token: str, email: str) -> bool:
        """Add an email address to the Access policy"""
        try:
            config = self._load_tunnel_config()
            if not config or not config.get('tunnel_id'):
                return False
            
            # Get account ID
            headers = {
                'Authorization': f'Bearer {cf_token}',
                'Content-Type': 'application/json'
            }
            
            accounts_response = requests.get('https://api.cloudflare.com/client/v4/accounts', headers=headers, timeout=10)
            accounts_response.raise_for_status()
            account_id = accounts_response.json()['result'][0]['id']
            
            # Find the Access app for this tunnel
            hostname = config.get('url', '').replace('https://', '')
            apps_response = requests.get(f'https://api.cloudflare.com/client/v4/accounts/{account_id}/access/apps', headers=headers)
            apps_response.raise_for_status()
            
            app_id = None
            for app in apps_response.json().get('result', []):
                if app.get('domain') == hostname:
                    app_id = app['id']
                    break
            
            if not app_id:
                current_app.logger.error(f"No Access app found for hostname: {hostname}")
                return False
            
            # Check if email already has access
            policies_response = requests.get(f'https://api.cloudflare.com/client/v4/accounts/{account_id}/access/apps/{app_id}/policies', headers=headers)
            policies_response.raise_for_status()
            
            for policy in policies_response.json().get('result', []):
                for include_rule in policy.get('include', []):
                    if include_rule.get('email', {}).get('email') == email:
                        current_app.logger.info(f"Email {email} already has access")
                        return True
            
            # Add email to existing policy or create new one
            policy_data = {
                'name': f'Access for {email}',
                'precedence': 1,
                'decision': 'allow',
                'include': [{'email': {'email': email}}],
                'exclude': [],
                'require': []
            }
            
            policy_response = requests.post(f'https://api.cloudflare.com/client/v4/accounts/{account_id}/access/apps/{app_id}/policies', 
                                         headers=headers, json=policy_data)
            policy_response.raise_for_status()
            
            # Update local config
            emails = config.get('emails', [])
            if email not in emails:
                emails.append(email)
                config['emails'] = emails
                self._save_tunnel_config(config)
            
            current_app.logger.info(f"Added email {email} to Access policy")
            return True
            
        except Exception as e:
            current_app.logger.error(f"Failed to add email to Access policy: {str(e)}")
            return False
    
    def remove_email_from_access_policy(self, cf_token: str, email: str) -> bool:
        """Remove an email address from the Access policy"""
        try:
            config = self._load_tunnel_config()
            if not config or not config.get('tunnel_id'):
                return False
            
            # Get account ID
            headers = {
                'Authorization': f'Bearer {cf_token}',
                'Content-Type': 'application/json'
            }
            
            accounts_response = requests.get('https://api.cloudflare.com/client/v4/accounts', headers=headers, timeout=10)
            accounts_response.raise_for_status()
            account_id = accounts_response.json()['result'][0]['id']
            
            # Find the Access app for this tunnel
            hostname = config.get('url', '').replace('https://', '')
            apps_response = requests.get(f'https://api.cloudflare.com/client/v4/accounts/{account_id}/access/apps', headers=headers)
            apps_response.raise_for_status()
            
            app_id = None
            for app in apps_response.json().get('result', []):
                if app.get('domain') == hostname:
                    app_id = app['id']
                    break
            
            if not app_id:
                current_app.logger.error(f"No Access app found for hostname: {hostname}")
                return False
            
            # Find and delete policies for this email
            policies_response = requests.get(f'https://api.cloudflare.com/client/v4/accounts/{account_id}/access/apps/{app_id}/policies', headers=headers)
            policies_response.raise_for_status()
            
            for policy in policies_response.json().get('result', []):
                for include_rule in policy.get('include', []):
                    if include_rule.get('email', {}).get('email') == email:
                        # Delete this policy
                        delete_response = requests.delete(f'https://api.cloudflare.com/client/v4/accounts/{account_id}/access/apps/{app_id}/policies/{policy["id"]}', headers=headers)
                        delete_response.raise_for_status()
                        current_app.logger.info(f"Removed policy for email {email}")
            
            # Update local config
            emails = config.get('emails', [])
            if email in emails:
                emails.remove(email)
                config['emails'] = emails
                self._save_tunnel_config(config)
            
            current_app.logger.info(f"Removed email {email} from Access policy")
            return True
            
        except Exception as e:
            current_app.logger.error(f"Failed to remove email from Access policy: {str(e)}")
            return False
    
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
        """Create Cloudflare tunnel via API, or retrieve/recreate it if it already exists."""
        tunnel_name_prefix = f"inventory-pi-{self.device_serial}"
        
        try:
            headers = {
                'Authorization': f'Bearer {cf_token}',
                'Content-Type': 'application/json'
            }
            
            accounts_response = requests.get('https://api.cloudflare.com/client/v4/accounts', headers=headers, timeout=10)
            accounts_response.raise_for_status()
            account_id = accounts_response.json()['result'][0]['id']

            tunnels_response = requests.get(f'https://api.cloudflare.com/client/v4/accounts/{account_id}/cfd_tunnel', headers=headers, timeout=10)
            tunnels_response.raise_for_status()
            tunnels = tunnels_response.json()['result']
            
            # Find any existing tunnel for this device
            existing_tunnel = next((t for t in tunnels if t['name'].startswith(tunnel_name_prefix)), None)

            if existing_tunnel:
                tunnel_id = existing_tunnel['id']
                tunnel_name = existing_tunnel['name']
                creds_file_path = f'/home/inventory/.cloudflared/{tunnel_id}.json'
                
                if not os.path.exists(creds_file_path):
                    current_app.logger.warning(f"Orphaned tunnel found (ID: {tunnel_id}). Deleting and recreating.")
                    delete_resp = requests.delete(f'https://api.cloudflare.com/client/v4/accounts/{account_id}/cfd_tunnel/{tunnel_id}', headers=headers, timeout=10)
                    delete_resp.raise_for_status()
                    current_app.logger.info(f"Orphaned tunnel {tunnel_id} deleted.")
                    # Fall through to create a new one
                else:
                    current_app.logger.info(f"Found existing tunnel and credentials for: {tunnel_name}")
                    with open(creds_file_path, 'r') as f:
                        creds_data = json.load(f)
                    return {
                        'tunnel_id': tunnel_id,
                        'tunnel_secret': creds_data['TunnelSecret'],
                        'tunnel_name': tunnel_name
                    }

            # Create a new tunnel with a unique name
            unique_suffix = uuid.uuid4().hex[:6]
            tunnel_name = f"{tunnel_name_prefix}-{unique_suffix}"
            current_app.logger.info(f"Creating new tunnel: {tunnel_name}")
            
            tunnel_data = {'name': tunnel_name}
            tunnel_response = requests.post(f'https://api.cloudflare.com/client/v4/accounts/{account_id}/cfd_tunnel', headers=headers, json=tunnel_data, timeout=30)
            tunnel_response.raise_for_status()
            tunnel_result = tunnel_response.json()['result']
            
            tunnel_id = tunnel_result['id']
            tunnel_secret = tunnel_result['credentials_file']['TunnelSecret']
            
            creds_data = {
                'AccountTag': account_id,
                'TunnelID': tunnel_id,
                'TunnelSecret': tunnel_secret
            }
            cloudflared_dir = '/home/inventory/.cloudflared'
            os.makedirs(cloudflared_dir, exist_ok=True)
            creds_file = f'{cloudflared_dir}/{tunnel_id}.json'
            with open(creds_file, 'w') as f:
                json.dump(creds_data, f)
            os.chmod(creds_file, 0o600)
            
            # Note: Ingress configuration is now handled in setup_tunnel() after DNS registration
            
            return {
                'tunnel_id': tunnel_id,
                'tunnel_secret': tunnel_secret,
                'tunnel_name': tunnel_name
            }
            
        except Exception as e:
            current_app.logger.error(f"Tunnel creation/retrieval failed: {str(e)}")
            raise
    
    def _configure_tunnel_ingress(self, cf_token: str, account_id: str, tunnel_id: str, hostname: str) -> None:
        """Configure tunnel ingress rules to point to the local service."""
        try:
            headers = {
                'Authorization': f'Bearer {cf_token}',
                'Content-Type': 'application/json'
            }
            
            ingress_config = {
                'config': {
                    'ingress': [
                        {
                            'hostname': hostname,
                            'service': 'https://192.168.43.203:443',
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
            config_response.raise_for_status()
            
            current_app.logger.info(f"Tunnel {tunnel_id} ingress rules configured successfully for {hostname}")
            
        except Exception as e:
            current_app.logger.error(f"Failed to configure tunnel ingress: {str(e)}")
            raise
    
    def setup_access_policy(self, cf_token: str, tunnel_id: str, 
                          email: str, hostname: str) -> bool:
        """Configure Cloudflare Access, retrieving or creating components as needed."""
        headers = {
            'Authorization': f'Bearer {cf_token}',
            'Content-Type': 'application/json'
        }
        
        try:
            accounts_resp = requests.get('https://api.cloudflare.com/client/v4/accounts', headers=headers)
            accounts_resp.raise_for_status()
            account_id = accounts_resp.json()['result'][0]['id']

            # Step 1: Ensure an Identity Provider is available
            idps_resp = requests.get(f'https://api.cloudflare.com/client/v4/accounts/{account_id}/access/identity_providers', headers=headers)
            idps_resp.raise_for_status()
            idps = idps_resp.json()['result']
            if not idps:
                raise Exception("No Identity Providers configured in your Cloudflare account. Please enable the 'One-time PIN' provider in the Access section.")
            
            # Step 2: Find or Create the Access Application
            apps_resp = requests.get(f'https://api.cloudflare.com/client/v4/accounts/{account_id}/access/apps', headers=headers)
            apps_resp.raise_for_status()
            apps = apps_resp.json()['result']
            
            app_id = next((app['id'] for app in apps if app.get('domain') == hostname), None)

            if app_id:
                current_app.logger.info(f"Found existing Access app: {app_id}")
            else:
                current_app.logger.info(f"Creating new Access app for hostname: {hostname}")
                app_data = {
                    'name': f'Inventory Pi {self.device_serial}',
                    'domain': hostname,
                    'type': 'self_hosted',
                    'session_duration': '24h',
                    'auto_redirect_to_identity': True
                }
                create_app_resp = requests.post(f'https://api.cloudflare.com/client/v4/accounts/{account_id}/access/apps', headers=headers, json=app_data)
                create_app_resp.raise_for_status()
                app_id = create_app_resp.json()['result']['id']
                current_app.logger.info(f"Created new Access app: {app_id}")

            # Step 3: Find or Create the 'Owner' Access Policy
            policies_resp = requests.get(f'https://api.cloudflare.com/client/v4/accounts/{account_id}/access/apps/{app_id}/policies', headers=headers)
            policies_resp.raise_for_status()
            policies = policies_resp.json()['result']
            
            owner_policy_name = 'Owner Access Only'
            owner_policy = next((p for p in policies if p['name'] == owner_policy_name), None)

            if owner_policy:
                current_app.logger.info(f"Found existing owner policy for {email}")
                # Optional: Update policy if needed, for now we assume it's correct
            else:
                current_app.logger.info(f"Creating new owner policy for {email}")
                policy_data = {
                    'name': owner_policy_name,
                    'precedence': 1,
                    'decision': 'allow',
                    'include': [
                        {
                            "email": {
                                "email": email
                            }
                        }
                    ]
                }
                create_policy_resp = requests.post(f'https://api.cloudflare.com/client/v4/accounts/{account_id}/access/apps/{app_id}/policies', headers=headers, json=policy_data)
                create_policy_resp.raise_for_status()
                current_app.logger.info(f"Created Access policy for {email}")

            # Step 4: Ensure a 'Deny All' fallback policy exists
            deny_policy_name = 'Deny All Others'
            deny_policy = next((p for p in policies if p['name'] == deny_policy_name), None)

            if deny_policy:
                current_app.logger.info("Deny-all fallback policy already exists.")
            else:
                current_app.logger.info("Creating deny-all fallback policy.")
                deny_policy_data = {
                    'name': deny_policy_name,
                    'precedence': 50, # Give it a lower precedence
                    'decision': 'deny',
                    'include': [{'everyone': {}}]
                }
                deny_policy_resp = requests.post(f'https://api.cloudflare.com/client/v4/accounts/{account_id}/access/apps/{app_id}/policies', headers=headers, json=deny_policy_data)
                deny_policy_resp.raise_for_status()
                current_app.logger.info("Created deny-all policy.")

            return True
            
        except Exception as e:
            current_app.logger.error(f"Access policy setup failed: {str(e)}")
            # Add more detailed error logging
            if 'response' in locals():
                current_app.logger.error(f"Response body: {locals()['response'].text}")
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
                            'service': 'https://192.168.43.203:443',  # Pi HTTPS port (use IP to avoid mDNS issues)
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
    
    def start_tunnel_service(self, tunnel_id: str, hostname: str) -> None:
        """Create config and start the tunnel service."""
        try:
            current_app.logger.info(f"Configuring and starting systemd service for tunnel {tunnel_id}")

            # --- Create cloudflared config.yml ---
            # The /etc/cloudflared directory is owned by the 'inventory' user.
            config_dir = "/etc/cloudflared"
            creds_file_path = f'/home/inventory/.cloudflared/{tunnel_id}.json'
            
            config_content = f"""tunnel: {tunnel_id}
credentials-file: {creds_file_path}
protocol: http2

ingress:
  - hostname: {hostname}
    service: https://127.0.0.1:443
    originRequest:
      noTLSVerify: true
  - service: http_status:404
"""
            with open(f"{config_dir}/config.yml", 'w') as f:
                f.write(config_content)

            # --- Enable and start the service using sudo ---
            # The 'inventory' user has been granted passwordless sudo for this specific command.
            subprocess.run(['/usr/bin/sudo', 'systemctl', 'daemon-reload'], check=True)
            subprocess.run(['/usr/bin/sudo', 'systemctl', 'enable', 'cloudflared.service'], check=True)
            subprocess.run(['/usr/bin/sudo', 'systemctl', 'restart', 'cloudflared.service'], check=True)

            current_app.logger.info(f"Successfully started and enabled cloudflared service for tunnel {tunnel_id}")

        except subprocess.CalledProcessError as e:
            stderr = e.stderr.decode() if e.stderr else "No stderr"
            current_app.logger.error(f"A system command failed during tunnel service setup: {stderr}")
            raise Exception(f"Failed to manage cloudflared service: {stderr}")
        except Exception as e:
            current_app.logger.error(f"Failed to start tunnel daemon: {str(e)}")
            raise

# Flask Routes
@remote_access_bp.route('/remote-access')
def remote_access_setup():
    """Display remote access setup page"""
    manager = CloudflareTunnelManager()
    status = manager.get_tunnel_status()
    return render_template('remote_access.html', 
                         serial=manager.device_serial,
                         tunnel_status=status)

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
        
        # Step 2: Create or retrieve the tunnel
        tunnel_info = manager.create_tunnel(cf_token)
        
        # Step 3: Register DNS via Worker to get the hostname
        hostname = manager.register_dns_with_worker(
            tunnel_info['tunnel_id'], 
            email
        ).replace('https://', '').replace('http://', '')
        
        # Step 4: Configure tunnel ingress rules AFTER DNS is set
        accounts_response = requests.get('https://api.cloudflare.com/client/v4/accounts', headers={'Authorization': f'Bearer {cf_token}','Content-Type': 'application/json'})
        accounts_response.raise_for_status()
        account_id = accounts_response.json()['result'][0]['id']
        manager._configure_tunnel_ingress(cf_token, account_id, tunnel_info['tunnel_id'], hostname)

        # Step 5: Setup Access policy
        manager.setup_access_policy(
            cf_token,
            tunnel_info['tunnel_id'],
            email,
            hostname
        )
        
        # Step 6: Start the tunnel service
        manager.start_tunnel_service(
            tunnel_info['tunnel_id'],
            hostname
        )
        
        # Step 7: Save tunnel configuration
        tunnel_config = {
            'tunnel_id': tunnel_info['tunnel_id'],
            'url': f'https://{hostname}',
            'email': email,
            'emails': [email],  # Initialize with the primary email
            'created_at': datetime.utcnow().isoformat(),
            'device_serial': manager.device_serial
        }
        manager._save_tunnel_config(tunnel_config)
        
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
        manager = CloudflareTunnelManager()
        status = manager.get_tunnel_status()
        return jsonify(status)
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@remote_access_bp.route('/api/restart-tunnel', methods=['POST'])
def restart_tunnel():
    """API endpoint to restart tunnel service"""
    try:
        manager = CloudflareTunnelManager()
        status = manager.get_tunnel_status()
        
        if not status['configured']:
            return jsonify({'success': False, 'error': 'No tunnel configured'}), 400
        
        # Restart cloudflared service
        subprocess.run(['/usr/bin/sudo', 'systemctl', 'restart', 'cloudflared.service'], check=True)
        
        return jsonify({'success': True, 'message': 'Tunnel service restarted'})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

@remote_access_bp.route('/api/add-email', methods=['POST'])
def add_email():
    """API endpoint to add an email address to tunnel access"""
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
        
        # Add email to access policy
        success = manager.add_email_to_access_policy(cf_token, email)
        
        if success:
            return jsonify({'success': True, 'message': f'Email {email} added successfully'})
        else:
            return jsonify({'success': False, 'error': 'Failed to add email to access policy'}), 500
            
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

@remote_access_bp.route('/api/remove-email', methods=['POST'])
def remove_email():
    """API endpoint to remove an email address from tunnel access"""
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
        
        # Remove email from access policy
        success = manager.remove_email_from_access_policy(cf_token, email)
        
        if success:
            return jsonify({'success': True, 'message': f'Email {email} removed successfully'})
        else:
            return jsonify({'success': False, 'error': 'Failed to remove email from access policy'}), 500
            
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500
