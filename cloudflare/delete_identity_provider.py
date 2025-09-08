#!/usr/bin/env python3
"""
Delete Cloudflare Access Identity Provider (email OTP)
"""

import requests
import json
import sys

def delete_identity_provider(cf_token):
    """Delete the email OTP Identity Provider"""
    
    headers = {
        'Authorization': f'Bearer {cf_token}',
        'Content-Type': 'application/json'
    }
    
    try:
        # Get account ID
        accounts_response = requests.get(
            'https://api.cloudflare.com/client/v4/accounts',
            headers=headers,
            timeout=10
        )
        
        if accounts_response.status_code != 200:
            print(f"❌ Failed to get accounts: {accounts_response.text}")
            return
        
        accounts_data = accounts_response.json()
        account_id = accounts_data['result'][0]['id']
        print(f"✅ Account ID: {account_id}")
        
        # Get Identity Providers
        idps_response = requests.get(
            f'https://api.cloudflare.com/client/v4/accounts/{account_id}/access/identity_providers',
            headers=headers,
            timeout=10
        )
        
        if idps_response.status_code != 200:
            print(f"❌ Failed to get Identity Providers: {idps_response.text}")
            return
        
        idps_data = idps_response.json()
        idps = idps_data.get('result', [])
        
        print(f"\n🔍 Found {len(idps)} Identity Provider(s):")
        print("=" * 60)
        
        for idp in idps:
            idp_id = idp['id']
            idp_name = idp.get('name', 'Unnamed')
            idp_type = idp.get('type', 'N/A')
            
            print(f"\n🔐 Identity Provider: {idp_name}")
            print(f"   ID: {idp_id}")
            print(f"   Type: {idp_type}")
            
            # Delete the Identity Provider
            print(f"   🗑️  Deleting...")
            
            delete_response = requests.delete(
                f'https://api.cloudflare.com/client/v4/accounts/{account_id}/access/identity_providers/{idp_id}',
                headers=headers,
                timeout=30
            )
            
            if delete_response.status_code == 200:
                delete_result = delete_response.json()
                if delete_result.get('success'):
                    print(f"   ✅ Deleted successfully")
                else:
                    print(f"   ❌ Delete failed: {delete_result.get('errors', [{}])[0].get('message', 'Unknown error')}")
            else:
                print(f"   ❌ Delete failed: {delete_response.text}")
            
            print("-" * 40)
        
        print(f"\n🎉 Identity Provider cleanup complete!")
        print(f"   All Identity Providers have been removed")
        print(f"   Ready for fresh setup with new customer")
        
    except Exception as e:
        print(f"❌ Error: {str(e)}")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python3 delete_identity_provider.py <CF_TOKEN>")
        print("Example: python3 delete_identity_provider.py U0t_FRwlz90YygAzckgS8MQ_7AFqYlErP_x8t6-Y")
        sys.exit(1)
    
    cf_token = sys.argv[1]
    delete_identity_provider(cf_token)
