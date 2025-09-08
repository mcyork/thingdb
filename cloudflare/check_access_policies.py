#!/usr/bin/env python3
"""
Check Cloudflare Access policies and applications
"""

import requests
import json
import sys

def check_access_policies(cf_token):
    """Check existing Access policies and applications"""
    
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
        print("=" * 80)
        
        for app in apps:
            app_id = app['id']
            app_name = app['name']
            app_domain = app.get('domain', 'N/A')
            app_type = app.get('type', 'N/A')
            created_at = app.get('created_at', 'N/A')
            
            print(f"\n📱 Application: {app_name}")
            print(f"   ID: {app_id}")
            print(f"   Domain: {app_domain}")
            print(f"   Type: {app_type}")
            print(f"   Created: {created_at}")
            
            # Get policies for this app
            policies_response = requests.get(
                f'https://api.cloudflare.com/client/v4/accounts/{account_id}/access/apps/{app_id}/policies',
                headers=headers,
                timeout=10
            )
            
            if policies_response.status_code == 200:
                policies_data = policies_response.json()
                policies = policies_data.get('result', [])
                print(f"   Policies: {len(policies)}")
                
                for i, policy in enumerate(policies, 1):
                    policy_name = policy.get('name', 'Unnamed')
                    policy_decision = policy.get('decision', 'N/A')
                    policy_precedence = policy.get('precedence', 'N/A')
                    
                    print(f"\n     Policy #{i}: {policy_name}")
                    print(f"       Decision: {policy_decision}")
                    print(f"       Precedence: {policy_precedence}")
                    
                    # Show include rules
                    include_rules = policy.get('include', [])
                    if include_rules:
                        print(f"       Include Rules:")
                        for rule in include_rules:
                            if 'email' in rule:
                                print(f"         - Email: {rule['email'].get('email', 'N/A')}")
                            elif 'everyone' in rule:
                                print(f"         - Everyone: {rule['everyone']}")
                            else:
                                print(f"         - Other: {rule}")
                    
                    # Show exclude rules
                    exclude_rules = policy.get('exclude', [])
                    if exclude_rules:
                        print(f"       Exclude Rules:")
                        for rule in exclude_rules:
                            print(f"         - {rule}")
                    
                    # Show require rules
                    require_rules = policy.get('require', [])
                    if require_rules:
                        print(f"       Require Rules:")
                        for rule in require_rules:
                            print(f"         - {rule}")
                    
                    print(f"       Policy ID: {policy.get('id', 'N/A')}")
                    print(f"       Created: {policy.get('created_at', 'N/A')}")
                    print(f"       Updated: {policy.get('updated_at', 'N/A')}")
                    
                    print("       " + "-" * 60)
            else:
                print(f"   Policies: ❌ Failed to get policies - {policies_response.text}")
            
            print("   " + "=" * 60)
        
        # Also check Identity Providers
        print(f"\n🔐 Identity Providers:")
        print("=" * 40)
        
        idps_response = requests.get(
            f'https://api.cloudflare.com/client/v4/accounts/{account_id}/access/identity_providers',
            headers=headers,
            timeout=10
        )
        
        if idps_response.status_code == 200:
            idps_data = idps_response.json()
            idps = idps_data.get('result', [])
            
            for idp in idps:
                idp_name = idp.get('name', 'Unnamed')
                idp_type = idp.get('type', 'N/A')
                idp_id = idp.get('id', 'N/A')
                print(f"   - {idp_name} ({idp_type}) - ID: {idp_id}")
        else:
            print(f"   ❌ Failed to get IdPs: {idps_response.text}")
        
    except Exception as e:
        print(f"❌ Error: {str(e)}")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python3 check_access_policies.py <CF_TOKEN>")
        sys.exit(1)
    
    cf_token = sys.argv[1]
    check_access_policies(cf_token)
