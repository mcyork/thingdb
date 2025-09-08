#!/usr/bin/env python3
"""
Cloudflare Tunnel Testing Tool
Tests tunnel creation, management, and configuration
"""

import requests
import json
import sys
import subprocess
import os
import tempfile
from typing import Dict, Any, Optional

class CloudflareTunnelTester:
    def __init__(self, api_token: str, account_id: str):
        self.api_token = api_token
        self.account_id = account_id
        self.base_url = "https://api.cloudflare.com/client/v4"
        self.headers = {
            'Authorization': f'Bearer {api_token}',
            'Content-Type': 'application/json'
        }
    
    def list_tunnels(self) -> Dict[str, Any]:
        """List existing tunnels"""
        print("🔍 Listing existing tunnels...")
        
        try:
            response = requests.get(
                f'{self.base_url}/accounts/{self.account_id}/cfd_tunnel',
                headers=self.headers,
                timeout=10
            )
            
            if response.status_code == 200:
                data = response.json()
                if data.get('success'):
                    tunnels = data.get('result', [])
                    print(f"✅ Found {len(tunnels)} tunnel(s)")
                    for tunnel in tunnels:
                        print(f"   - {tunnel.get('name')} (ID: {tunnel.get('id')})")
                        print(f"     Status: {tunnel.get('status')}")
                        print(f"     Created: {tunnel.get('created_at')}")
                    return {'success': True, 'tunnels': tunnels}
                else:
                    print(f"❌ Failed to list tunnels: {data.get('errors', [{}])[0].get('message', 'Unknown error')}")
                    return {'success': False, 'error': 'Failed to list tunnels'}
            else:
                print(f"❌ HTTP {response.status_code}: {response.text}")
                return {'success': False, 'error': f'HTTP {response.status_code}'}
                
        except Exception as e:
            print(f"❌ Error: {e}")
            return {'success': False, 'error': str(e)}
    
    def create_test_tunnel(self, tunnel_name: str = "inventory-pi-test") -> Dict[str, Any]:
        """Create a test tunnel"""
        print(f"🚇 Creating test tunnel: {tunnel_name}")
        
        try:
            # Create tunnel
            tunnel_data = {
                'name': tunnel_name,
                'tunnel_secret': self._generate_tunnel_secret()
            }
            
            response = requests.post(
                f'{self.base_url}/accounts/{self.account_id}/cfd_tunnel',
                headers=self.headers,
                json=tunnel_data,
                timeout=30
            )
            
            if response.status_code == 200:
                data = response.json()
                if data.get('success'):
                    tunnel = data.get('result', {})
                    tunnel_id = tunnel.get('id')
                    tunnel_secret = tunnel.get('tunnel_secret')
                    
                    print(f"✅ Tunnel created successfully!")
                    print(f"   ID: {tunnel_id}")
                    print(f"   Secret: {tunnel_secret[:8]}...")
                    
                    return {
                        'success': True, 
                        'tunnel_id': tunnel_id,
                        'tunnel_secret': tunnel_secret,
                        'tunnel': tunnel
                    }
                else:
                    print(f"❌ Failed to create tunnel: {data.get('errors', [{}])[0].get('message', 'Unknown error')}")
                    return {'success': False, 'error': 'Failed to create tunnel'}
            else:
                print(f"❌ HTTP {response.status_code}: {response.text}")
                return {'success': False, 'error': f'HTTP {response.status_code}'}
                
        except Exception as e:
            print(f"❌ Error: {e}")
            return {'success': False, 'error': str(e)}
    
    def delete_tunnel(self, tunnel_id: str) -> Dict[str, Any]:
        """Delete a tunnel"""
        print(f"🗑️  Deleting tunnel: {tunnel_id}")
        
        try:
            response = requests.delete(
                f'{self.base_url}/accounts/{self.account_id}/cfd_tunnel/{tunnel_id}',
                headers=self.headers,
                timeout=30
            )
            
            if response.status_code == 200:
                data = response.json()
                if data.get('success'):
                    print("✅ Tunnel deleted successfully!")
                    return {'success': True}
                else:
                    print(f"❌ Failed to delete tunnel: {data.get('errors', [{}])[0].get('message', 'Unknown error')}")
                    return {'success': False, 'error': 'Failed to delete tunnel'}
            else:
                print(f"❌ HTTP {response.status_code}: {response.text}")
                return {'success': False, 'error': f'HTTP {response.status_code}'}
                
        except Exception as e:
            print(f"❌ Error: {e}")
            return {'success': False, 'error': str(e)}
    
    def create_dns_record(self, zone_id: str, hostname: str, tunnel_id: str) -> Dict[str, Any]:
        """Create a DNS CNAME record pointing to the tunnel"""
        print(f"🌐 Creating DNS record: {hostname} -> {tunnel_id}.cfargotunnel.com")
        
        try:
            dns_data = {
                'type': 'CNAME',
                'name': hostname,
                'content': f'{tunnel_id}.cfargotunnel.com',
                'ttl': 300,
                'proxied': False
            }
            
            response = requests.post(
                f'{self.base_url}/zones/{zone_id}/dns_records',
                headers=self.headers,
                json=dns_data,
                timeout=30
            )
            
            if response.status_code == 200:
                data = response.json()
                if data.get('success'):
                    record = data.get('result', {})
                    print(f"✅ DNS record created successfully!")
                    print(f"   ID: {record.get('id')}")
                    print(f"   Name: {record.get('name')}")
                    print(f"   Content: {record.get('content')}")
                    return {'success': True, 'record': record}
                else:
                    print(f"❌ Failed to create DNS record: {data.get('errors', [{}])[0].get('message', 'Unknown error')}")
                    return {'success': False, 'error': 'Failed to create DNS record'}
            else:
                print(f"❌ HTTP {response.status_code}: {response.text}")
                return {'success': False, 'error': f'HTTP {response.status_code}'}
                
        except Exception as e:
            print(f"❌ Error: {e}")
            return {'success': False, 'error': str(e)}
    
    def create_access_app(self, zone_id: str, hostname: str, email: str) -> Dict[str, Any]:
        """Create a Cloudflare Access application"""
        print(f"🔐 Creating Access app for: {hostname}")
        
        try:
            # Create Access application
            app_data = {
                'name': f'Inventory Pi Test - {hostname}',
                'domain': f'{hostname}',
                'type': 'self_hosted',
                'session_duration': '24h',
                'auto_redirect_to_identity': True,
                'allowed_idps': ['email'],
                'custom_deny_message': 'Access restricted to authorized users only.'
            }
            
            response = requests.post(
                f'{self.base_url}/accounts/{self.account_id}/access/apps',
                headers=self.headers,
                json=app_data,
                timeout=30
            )
            
            if response.status_code == 200:
                data = response.json()
                if data.get('success'):
                    app = data.get('result', {})
                    app_id = app.get('id')
                    print(f"✅ Access app created successfully!")
                    print(f"   App ID: {app_id}")
                    
                    # Create access policy
                    policy_result = self._create_access_policy(app_id, email)
                    if policy_result['success']:
                        return {'success': True, 'app': app, 'policy': policy_result['policy']}
                    else:
                        return {'success': False, 'error': f"App created but policy failed: {policy_result['error']}"}
                else:
                    print(f"❌ Failed to create Access app: {data.get('errors', [{}])[0].get('message', 'Unknown error')}")
                    return {'success': False, 'error': 'Failed to create Access app'}
            else:
                print(f"❌ HTTP {response.status_code}: {response.text}")
                return {'success': False, 'error': f'HTTP {response.status_code}'}
                
        except Exception as e:
            print(f"❌ Error: {e}")
            return {'success': False, 'error': str(e)}
    
    def _create_access_policy(self, app_id: str, email: str) -> Dict[str, Any]:
        """Create an access policy for the app"""
        print(f"📋 Creating access policy for: {email}")
        
        try:
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
            
            response = requests.post(
                f'{self.base_url}/accounts/{self.account_id}/access/apps/{app_id}/policies',
                headers=self.headers,
                json=policy_data,
                timeout=30
            )
            
            if response.status_code == 200:
                data = response.json()
                if data.get('success'):
                    policy = data.get('result', {})
                    print(f"✅ Access policy created successfully!")
                    return {'success': True, 'policy': policy}
                else:
                    print(f"❌ Failed to create access policy: {data.get('errors', [{}])[0].get('message', 'Unknown error')}")
                    return {'success': False, 'error': 'Failed to create access policy'}
            else:
                print(f"❌ HTTP {response.status_code}: {response.text}")
                return {'success': False, 'error': f'HTTP {response.status_code}'}
                
        except Exception as e:
            print(f"❌ Error: {e}")
            return {'success': False, 'error': str(e)}
    
    def _generate_tunnel_secret(self) -> str:
        """Generate a random tunnel secret"""
        import secrets
        return secrets.token_urlsafe(32)
    
    def generate_cloudflared_config(self, tunnel_id: str, hostname: str) -> str:
        """Generate cloudflared configuration"""
        config = f"""tunnel: {tunnel_id}
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
        return config

def main():
    if len(sys.argv) < 3:
        print("Usage: python3 test_tunnel.py <api_token> <account_id> [command]")
        print("\nCommands:")
        print("  list                    - List existing tunnels")
        print("  create <name>           - Create a test tunnel")
        print("  delete <tunnel_id>      - Delete a tunnel")
        print("  full-test <zone_id> <hostname> <email> - Run full test")
        print("\nTo get account_id, run test_api.py first")
        sys.exit(1)
    
    api_token = sys.argv[1]
    account_id = sys.argv[2]
    command = sys.argv[3] if len(sys.argv) > 3 else "list"
    
    tester = CloudflareTunnelTester(api_token, account_id)
    
    print("🚇 Cloudflare Tunnel Testing Tool")
    print("=" * 40)
    
    if command == "list":
        tester.list_tunnels()
    
    elif command == "create":
        tunnel_name = sys.argv[4] if len(sys.argv) > 4 else "inventory-pi-test"
        result = tester.create_test_tunnel(tunnel_name)
        if result['success']:
            print(f"\n📝 Cloudflared config:")
            print(tester.generate_cloudflared_config(result['tunnel_id'], "test.example.com"))
    
    elif command == "delete":
        if len(sys.argv) < 5:
            print("❌ Tunnel ID required for delete command")
            sys.exit(1)
        tunnel_id = sys.argv[4]
        tester.delete_tunnel(tunnel_id)
    
    elif command == "full-test":
        if len(sys.argv) < 7:
            print("❌ full-test requires: <zone_id> <hostname> <email>")
            sys.exit(1)
        zone_id = sys.argv[4]
        hostname = sys.argv[5]
        email = sys.argv[6]
        
        print(f"🧪 Running full test with:")
        print(f"   Zone ID: {zone_id}")
        print(f"   Hostname: {hostname}")
        print(f"   Email: {email}")
        
        # Create tunnel
        tunnel_result = tester.create_test_tunnel(f"test-{hostname}")
        if not tunnel_result['success']:
            print("❌ Tunnel creation failed")
            sys.exit(1)
        
        tunnel_id = tunnel_result['tunnel_id']
        
        # Create DNS record
        dns_result = tester.create_dns_record(zone_id, hostname, tunnel_id)
        if not dns_result['success']:
            print("❌ DNS record creation failed")
            tester.delete_tunnel(tunnel_id)
            sys.exit(1)
        
        # Create Access app
        access_result = tester.create_access_app(zone_id, hostname, email)
        if not access_result['success']:
            print("❌ Access app creation failed")
            tester.delete_tunnel(tunnel_id)
            sys.exit(1)
        
        print(f"\n🎉 Full test completed successfully!")
        print(f"   Tunnel ID: {tunnel_id}")
        print(f"   URL: https://{hostname}")
        print(f"   Access: Restricted to {email}")
        
        print(f"\n📝 Cloudflared config:")
        print(tester.generate_cloudflared_config(tunnel_id, hostname))
    
    else:
        print(f"❌ Unknown command: {command}")
        sys.exit(1)

if __name__ == "__main__":
    main()
