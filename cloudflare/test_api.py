#!/usr/bin/env python3
"""
Cloudflare API Testing Tool
Tests basic API connectivity and permissions
"""

import requests
import json
import sys
from typing import Dict, Any, Optional

class CloudflareAPITester:
    def __init__(self, api_token: str):
        self.api_token = api_token
        self.base_url = "https://api.cloudflare.com/client/v4"
        self.headers = {
            'Authorization': f'Bearer {api_token}',
            'Content-Type': 'application/json'
        }
    
    def test_token_validation(self) -> Dict[str, Any]:
        """Test if the API token is valid and get account info"""
        print("🔍 Testing token validation...")
        
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
                    print(f"✅ Token is valid")
                    print(f"   Status: {result.get('status')}")
                    print(f"   ID: {result.get('id')}")
                    return {'valid': True, 'data': result}
                else:
                    print(f"❌ Token validation failed: {data.get('errors', [{}])[0].get('message', 'Unknown error')}")
                    return {'valid': False, 'error': 'Token validation failed'}
            else:
                print(f"❌ HTTP {response.status_code}: {response.text}")
                return {'valid': False, 'error': f'HTTP {response.status_code}'}
                
        except Exception as e:
            print(f"❌ Error: {e}")
            return {'valid': False, 'error': str(e)}
    
    def test_account_access(self) -> Dict[str, Any]:
        """Test account access and list available accounts"""
        print("\n🏢 Testing account access...")
        
        try:
            response = requests.get(
                f'{self.base_url}/accounts',
                headers=self.headers,
                timeout=10
            )
            
            if response.status_code == 200:
                data = response.json()
                if data.get('success'):
                    accounts = data.get('result', [])
                    print(f"✅ Found {len(accounts)} account(s)")
                    for account in accounts:
                        print(f"   - {account.get('name')} (ID: {account.get('id')})")
                    return {'success': True, 'accounts': accounts}
                else:
                    print(f"❌ Failed to get accounts: {data.get('errors', [{}])[0].get('message', 'Unknown error')}")
                    return {'success': False, 'error': 'Failed to get accounts'}
            else:
                print(f"❌ HTTP {response.status_code}: {response.text}")
                return {'success': False, 'error': f'HTTP {response.status_code}'}
                
        except Exception as e:
            print(f"❌ Error: {e}")
            return {'success': False, 'error': str(e)}
    
    def test_zone_access(self, account_id: str) -> Dict[str, Any]:
        """Test zone access for the given account"""
        print(f"\n🌐 Testing zone access for account {account_id}...")
        
        try:
            response = requests.get(
                f'{self.base_url}/zones',
                headers=self.headers,
                timeout=10
            )
            
            if response.status_code == 200:
                data = response.json()
                if data.get('success'):
                    zones = data.get('result', [])
                    print(f"✅ Found {len(zones)} zone(s)")
                    for zone in zones:
                        print(f"   - {zone.get('name')} (ID: {zone.get('id')})")
                    return {'success': True, 'zones': zones}
                else:
                    print(f"❌ Failed to get zones: {data.get('errors', [{}])[0].get('message', 'Unknown error')}")
                    return {'success': False, 'error': 'Failed to get zones'}
            else:
                print(f"❌ HTTP {response.status_code}: {response.text}")
                return {'success': False, 'error': f'HTTP {response.status_code}'}
                
        except Exception as e:
            print(f"❌ Error: {e}")
            return {'success': False, 'error': str(e)}
    
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
    
    def test_access_permissions(self, account_id: str) -> Dict[str, Any]:
        """Test Cloudflare Access permissions"""
        print(f"\n🔐 Testing Access permissions for account {account_id}...")
        
        try:
            response = requests.get(
                f'{self.base_url}/accounts/{account_id}/access/apps',
                headers=self.headers,
                timeout=10
            )
            
            if response.status_code == 200:
                data = response.json()
                if data.get('success'):
                    apps = data.get('result', [])
                    print(f"✅ Access API accessible - found {len(apps)} existing app(s)")
                    return {'success': True, 'apps': apps}
                else:
                    print(f"❌ Access API error: {data.get('errors', [{}])[0].get('message', 'Unknown error')}")
                    return {'success': False, 'error': 'Access API error'}
            elif response.status_code == 403:
                print("❌ Insufficient permissions for Access management")
                return {'success': False, 'error': 'Insufficient Access permissions'}
            else:
                print(f"❌ HTTP {response.status_code}: {response.text}")
                return {'success': False, 'error': f'HTTP {response.status_code}'}
                
        except Exception as e:
            print(f"❌ Error: {e}")
            return {'success': False, 'error': str(e)}

def main():
    if len(sys.argv) != 2:
        print("Usage: python3 test_api.py <api_token>")
        print("\nTo get an API token:")
        print("1. Go to https://dash.cloudflare.com/profile/api-tokens")
        print("2. Create a custom token with appropriate permissions")
        print("3. Copy the token and run this script")
        print("\nToken Types:")
        print("  - Owner/Admin Token: DNS management, zone control")
        print("  - User Token: Tunnel access permissions only")
        sys.exit(1)
    
    api_token = sys.argv[1]
    tester = CloudflareAPITester(api_token)
    
    print("🚀 Cloudflare Owner/Admin API Testing Tool")
    print("=" * 50)
    print("Testing DNS management and zone control permissions...")
    
    # Test token validation
    token_result = tester.test_token_validation()
    if not token_result['valid']:
        print("\n❌ Token validation failed. Please check your API token.")
        sys.exit(1)
    
    # Test account access
    account_result = tester.test_account_access()
    if not account_result['success']:
        print("\n❌ Account access failed. Please check your API token permissions.")
        sys.exit(1)
    
    # Get the first account ID for further testing
    accounts = account_result['accounts']
    if not accounts:
        print("\n❌ No accounts found. Please check your API token permissions.")
        sys.exit(1)
    
    account_id = accounts[0]['id']
    print(f"\n📋 Using account: {accounts[0]['name']} ({account_id})")
    
    # Test zone access
    zone_result = tester.test_zone_access(account_id)
    
    # Test tunnel permissions (optional for owner token)
    tunnel_result = tester.test_tunnel_permissions(account_id)
    
    # Test access permissions (optional for owner token)
    access_result = tester.test_access_permissions(account_id)
    
    # Summary
    print("\n" + "=" * 50)
    print("📊 Owner/Admin Token Test Summary:")
    print(f"   Token Valid: {'✅' if token_result['valid'] else '❌'}")
    print(f"   Account Access: {'✅' if account_result['success'] else '❌'}")
    print(f"   Zone Access: {'✅' if zone_result['success'] else '❌'}")
    print(f"   Tunnel Permissions: {'✅' if tunnel_result['success'] else '❌'}")
    print(f"   Access Permissions: {'✅' if access_result['success'] else '❌'}")
    
    # Core requirements for owner token
    core_requirements = [token_result['valid'], account_result['success'], zone_result['success']]
    
    if all(core_requirements):
        print("\n🎉 Owner/Admin token is ready for DNS management!")
        print("   This token can be used for:")
        print("   - DNS record management")
        print("   - Zone configuration")
        print("   - Worker deployment")
        
        if tunnel_result['success'] and access_result['success']:
            print("   - Full tunnel and access management")
        else:
            print("\n💡 For tunnel management, users will need separate user tokens.")
            print("   Run: python3 test_user_token.py <user_token>")
    else:
        print("\n⚠️  Core requirements failed. Please check the permissions on your API token.")
        print("\nRequired permissions for owner/admin tokens:")
        print("   - Account: Read")
        print("   - Zone: Read, DNS:Edit")
        print("   - (Optional) Account: Cloudflare Tunnel:Edit")
        print("   - (Optional) Account: Access: Apps and Policies:Edit")

if __name__ == "__main__":
    main()
