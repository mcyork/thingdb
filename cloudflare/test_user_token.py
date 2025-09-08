#!/usr/bin/env python3
"""
Cloudflare User Token Testing Tool
Tests tunnel access permissions for end users
"""

import requests
import json
import sys
from typing import Dict, Any, Optional

class CloudflareUserTokenTester:
    def __init__(self, api_token: str):
        self.api_token = api_token
        self.base_url = "https://api.cloudflare.com/client/v4"
        self.headers = {
            'Authorization': f'Bearer {api_token}',
            'Content-Type': 'application/json'
        }
    
    def test_token_validation(self) -> Dict[str, Any]:
        """Test if the API token is valid"""
        print("🔍 Testing user token validation...")
        
        try:
            # First get accounts to find the account ID
            accounts_response = requests.get(
                f'{self.base_url}/accounts',
                headers=self.headers,
                timeout=10
            )
            
            if accounts_response.status_code != 200:
                print(f"❌ Failed to get accounts: {accounts_response.text}")
                return {'valid': False, 'error': 'Failed to get accounts'}
            
            accounts_data = accounts_response.json()
            if not accounts_data.get('success') or not accounts_data.get('result'):
                print(f"❌ No accounts found: {accounts_data.get('errors', [{}])[0].get('message', 'Unknown error')}")
                return {'valid': False, 'error': 'No accounts found'}
            
            # Use the first account ID for token verification
            account_id = accounts_data['result'][0]['id']
            
            response = requests.get(
                f'{self.base_url}/accounts/{account_id}/tokens/verify',
                headers=self.headers,
                timeout=10
            )
            
            if response.status_code == 200:
                data = response.json()
                if data.get('success'):
                    result = data.get('result', {})
                    print(f"✅ User token is valid")
                    print(f"   Status: {result.get('status')}")
                    print(f"   ID: {result.get('id')}")
                    return {'valid': True, 'data': result, 'account_id': account_id}
                else:
                    print(f"❌ Token validation failed: {data.get('errors', [{}])[0].get('message', 'Unknown error')}")
                    return {'valid': False, 'error': 'Token validation failed'}
            else:
                print(f"❌ HTTP {response.status_code}: {response.text}")
                return {'valid': False, 'error': f'HTTP {response.status_code}'}
                
        except Exception as e:
            print(f"❌ Error: {e}")
            return {'valid': False, 'error': str(e)}
    
    def test_tunnel_permissions(self, account_id: str) -> Dict[str, Any]:
        """Test tunnel management permissions"""
        print(f"\n🚇 Testing tunnel permissions for account {account_id}...")
        
        try:
            response = requests.get(
                f'{self.base_url}/accounts/{account_id}/cfd_tunnel',
                headers=self.headers,
                timeout=10
            )
            
            if response.status_code == 200:
                data = response.json()
                if data.get('success'):
                    tunnels = data.get('result', [])
                    print(f"✅ Tunnel API accessible - found {len(tunnels)} existing tunnel(s)")
                    for tunnel in tunnels:
                        print(f"   - {tunnel.get('name')} (ID: {tunnel.get('id')})")
                    return {'success': True, 'tunnels': tunnels}
                else:
                    print(f"❌ Tunnel API error: {data.get('errors', [{}])[0].get('message', 'Unknown error')}")
                    return {'success': False, 'error': 'Tunnel API error'}
            elif response.status_code == 403:
                print("❌ Insufficient permissions for tunnel management")
                return {'success': False, 'error': 'Insufficient tunnel permissions'}
            else:
                print(f"❌ HTTP {response.status_code}: {response.text}")
                return {'success': False, 'error': f'HTTP {response.status_code}'}
                
        except Exception as e:
            print(f"❌ Error: {e}")
            return {'success': False, 'error': str(e)}
    
    def test_tunnel_creation(self, account_id: str) -> Dict[str, Any]:
        """Test creating a test tunnel"""
        print(f"\n🔧 Testing tunnel creation...")
        
        try:
            # Create a test tunnel
            tunnel_data = {
                "name": "inventory-pi-test-tunnel",
                "tunnel_secret": "test-secret-key-12345"
            }
            
            response = requests.post(
                f'{self.base_url}/accounts/{account_id}/cfd_tunnel',
                headers=self.headers,
                json=tunnel_data,
                timeout=10
            )
            
            if response.status_code == 200:
                data = response.json()
                if data.get('success'):
                    tunnel = data.get('result', {})
                    print(f"✅ Test tunnel created successfully")
                    print(f"   Name: {tunnel.get('name')}")
                    print(f"   ID: {tunnel.get('id')}")
                    print(f"   Token: {tunnel.get('tunnel_token')}")
                    return {'success': True, 'tunnel': tunnel}
                else:
                    print(f"❌ Tunnel creation failed: {data.get('errors', [{}])[0].get('message', 'Unknown error')}")
                    return {'success': False, 'error': 'Tunnel creation failed'}
            elif response.status_code == 403:
                print("❌ Insufficient permissions for tunnel creation")
                return {'success': False, 'error': 'Insufficient tunnel creation permissions'}
            else:
                print(f"❌ HTTP {response.status_code}: {response.text}")
                return {'success': False, 'error': f'HTTP {response.status_code}'}
                
        except Exception as e:
            print(f"❌ Error: {e}")
            return {'success': False, 'error': str(e)}
    
    def cleanup_test_tunnel(self, account_id: str, tunnel_id: str) -> Dict[str, Any]:
        """Clean up the test tunnel"""
        print(f"\n🧹 Cleaning up test tunnel...")
        
        try:
            response = requests.delete(
                f'{self.base_url}/accounts/{account_id}/cfd_tunnel/{tunnel_id}',
                headers=self.headers,
                timeout=10
            )
            
            if response.status_code == 200:
                print("✅ Test tunnel cleaned up successfully")
                return {'success': True}
            else:
                print(f"⚠️  Failed to clean up test tunnel: {response.text}")
                return {'success': False, 'error': 'Cleanup failed'}
                
        except Exception as e:
            print(f"⚠️  Error during cleanup: {e}")
            return {'success': False, 'error': str(e)}

def main():
    if len(sys.argv) != 2:
        print("Usage: python3 test_user_token.py <user_api_token>")
        print("\nTo get a user API token:")
        print("1. Go to https://dash.cloudflare.com/profile/api-tokens")
        print("2. Create a custom token with these permissions:")
        print("   - Account: Cloudflare Tunnel:Edit")
        print("   - Account: Read (for token validation)")
        print("3. Copy the token and run this script")
        print("\nThis token is for end users who need tunnel access only.")
        sys.exit(1)
    
    api_token = sys.argv[1]
    tester = CloudflareUserTokenTester(api_token)
    
    print("🚀 Cloudflare User Token Testing Tool")
    print("=" * 45)
    print("Testing tunnel access permissions for end users...")
    
    # Test token validation
    token_result = tester.test_token_validation()
    if not token_result['valid']:
        print("\n❌ Token validation failed. Please check your user API token.")
        sys.exit(1)
    
    account_id = token_result['account_id']
    
    # Test tunnel permissions
    tunnel_result = tester.test_tunnel_permissions(account_id)
    if not tunnel_result['success']:
        print("\n❌ Tunnel permissions test failed. Please check your user API token permissions.")
        sys.exit(1)
    
    # Test tunnel creation
    creation_result = tester.test_tunnel_creation(account_id)
    if creation_result['success']:
        tunnel_id = creation_result['tunnel']['id']
        # Clean up the test tunnel
        tester.cleanup_test_tunnel(account_id, tunnel_id)
    
    # Summary
    print("\n" + "=" * 45)
    print("📊 User Token Test Summary:")
    print(f"   Token Valid: {'✅' if token_result['valid'] else '❌'}")
    print(f"   Tunnel Permissions: {'✅' if tunnel_result['success'] else '❌'}")
    print(f"   Tunnel Creation: {'✅' if creation_result['success'] else '❌'}")
    
    if all([token_result['valid'], tunnel_result['success'], creation_result['success']]):
        print("\n🎉 User token is ready for tunnel access!")
        print("   This token can be used by end users to create and manage tunnels.")
    else:
        print("\n⚠️  Some tests failed. Please check the permissions on your user API token.")
        print("\nRequired permissions for user tokens:")
        print("   - Account: Read")
        print("   - Account: Cloudflare Tunnel:Edit")

if __name__ == "__main__":
    main()
