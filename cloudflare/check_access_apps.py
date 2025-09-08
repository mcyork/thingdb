#!/usr/bin/env python3
"""
Check Cloudflare Access applications
"""

import requests
import json
import sys

def check_access_apps(cf_token):
    """Check existing Access applications"""
    
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
        
        # List Access applications
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
        
        print(f"\n🔍 Found {len(apps)} Access application(s):")
        print("=" * 60)
        
        for app in apps:
            app_id = app['id']
            app_name = app['name']
            app_domain = app.get('domain', 'N/A')
            created_at = app.get('created_at', 'N/A')
            
            print(f"\n📱 App: {app_name}")
            print(f"   ID: {app_id}")
            print(f"   Domain: {app_domain}")
            print(f"   Created: {created_at}")
            
            # Check policies
            policies_response = requests.get(
                f'https://api.cloudflare.com/client/v4/accounts/{account_id}/access/apps/{app_id}/policies',
                headers=headers,
                timeout=10
            )
            
            if policies_response.status_code == 200:
                policies_data = policies_response.json()
                policies = policies_data.get('result', [])
                print(f"   Policies: {len(policies)}")
                
                for policy in policies:
                    policy_name = policy.get('name', 'Unnamed')
                    policy_decision = policy.get('decision', 'N/A')
                    print(f"     - {policy_name} ({policy_decision})")
            else:
                print(f"   Policies: ❌ Failed to get policies")
            
            print("-" * 40)
        
    except Exception as e:
        print(f"❌ Error: {str(e)}")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python3 check_access_apps.py <CF_TOKEN>")
        sys.exit(1)
    
    cf_token = sys.argv[1]
    check_access_apps(cf_token)
