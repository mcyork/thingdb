#!/usr/bin/env python3
"""
Fix Cloudflare Access policy by adding email allowlist
"""

import requests
import json
import sys

def fix_access_policy(cf_token, email):
    """Add email policy to existing Access application"""
    
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
        
        # Find the Access application
        apps_response = requests.get(
            f'https://api.cloudflare.com/client/v4/accounts/{account_id}/access/apps',
            headers=headers,
            timeout=10
        )
        
        if apps_response.status_code != 200:
            print(f"❌ Failed to get Access apps: {apps_response.text}")
            return
        
        apps_data = apps_response.json()
        apps = apps_data.get('result', [])
        
        # Find the Pi app
        pi_app = None
        for app in apps:
            if 'pi-6462ab0a.nestdb.io' in app.get('domain', ''):
                pi_app = app
                break
        
        if not pi_app:
            print("❌ No Pi Access application found")
            return
        
        app_id = pi_app['id']
        app_name = pi_app['name']
        app_domain = pi_app['domain']
        
        print(f"✅ Found Access app: {app_name} ({app_domain})")
        print(f"   App ID: {app_id}")
        
        # Create allow policy for the email
        allow_policy = {
            'name': f'Allow {email}',
            'precedence': 1,
            'decision': 'allow',
            'include': [
                {
                    'email': {
                        'email': email
                    }
                }
            ],
            'exclude': [],
            'require': []
        }
        
        print(f"\n🔧 Creating allow policy for {email}...")
        
        policy_response = requests.post(
            f'https://api.cloudflare.com/client/v4/accounts/{account_id}/access/apps/{app_id}/policies',
            headers=headers,
            json=allow_policy,
            timeout=30
        )
        
        if policy_response.status_code != 200:
            print(f"❌ Failed to create allow policy: {policy_response.text}")
            return
        
        policy_result = policy_response.json()
        if not policy_result.get('success'):
            print(f"❌ Allow policy creation failed: {policy_result.get('errors', [{}])[0].get('message', 'Unknown error')}")
            return
        
        print(f"✅ Created allow policy for {email}")
        
        # Create deny-all policy
        deny_policy = {
            'name': 'Deny All Others',
            'precedence': 2,
            'decision': 'deny',
            'include': [
                {
                    'everyone': {}
                }
            ]
        }
        
        print(f"\n🔧 Creating deny-all policy...")
        
        deny_response = requests.post(
            f'https://api.cloudflare.com/client/v4/accounts/{account_id}/access/apps/{app_id}/policies',
            headers=headers,
            json=deny_policy,
            timeout=30
        )
        
        if deny_response.status_code != 200:
            print(f"❌ Failed to create deny policy: {deny_response.text}")
            return
        
        deny_result = deny_response.json()
        if not deny_result.get('success'):
            print(f"❌ Deny policy creation failed: {deny_result.get('errors', [{}])[0].get('message', 'Unknown error')}")
            return
        
        print(f"✅ Created deny-all policy")
        
        print(f"\n🎉 Access policies configured successfully!")
        print(f"   You should now be able to access {app_domain}")
        print(f"   Enter your email: {email}")
        print(f"   You should receive an OTP code")
        
    except Exception as e:
        print(f"❌ Error: {str(e)}")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python3 fix_access_policy.py <CF_TOKEN> <EMAIL>")
        print("Example: python3 fix_access_policy.py U0t_FRwlz90YygAzckgS8MQ_7AFqYlErP_x8t6-Y ian@mcyork.com")
        sys.exit(1)
    
    cf_token = sys.argv[1]
    email = sys.argv[2]
    fix_access_policy(cf_token, email)
