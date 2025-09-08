We wanted to go through the Nginx frontend.We want it to use the NGINX frontend.#!/usr/bin/env python3
"""
Check Cloudflare tunnel configuration
"""

import requests
import json
import sys

def check_tunnel_config(cf_token, tunnel_id):
    """Check tunnel configuration in Cloudflare"""
    
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
        
        # Get tunnel configuration
        config_response = requests.get(
            f'https://api.cloudflare.com/client/v4/accounts/{account_id}/cfd_tunnel/{tunnel_id}/configurations',
            headers=headers,
            timeout=10
        )
        
        if config_response.status_code != 200:
            print(f"❌ Failed to get tunnel config: {config_response.text}")
            return
        
        config_data = config_response.json()
        if not config_data.get('success'):
            print(f"❌ Config request failed: {config_data.get('errors', [{}])[0].get('message', 'Unknown error')}")
            return
        
        config = config_data.get('result', {})
        print(f"\n🔍 Tunnel Configuration for {tunnel_id}:")
        print("=" * 60)
        
        # Print the full config
        print(json.dumps(config, indent=2))
        
        # Check ingress rules
        ingress_rules = config.get('config', {}).get('ingress', [])
        print(f"\n📋 Ingress Rules ({len(ingress_rules)}):")
        print("-" * 40)
        
        for i, rule in enumerate(ingress_rules, 1):
            hostname = rule.get('hostname', 'N/A')
            service = rule.get('service', 'N/A')
            print(f"Rule #{i}:")
            print(f"  Hostname: {hostname}")
            print(f"  Service: {service}")
            if 'originRequest' in rule:
                print(f"  Origin Request: {rule['originRequest']}")
            print()
        
    except Exception as e:
        print(f"❌ Error: {str(e)}")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python3 check_tunnel_config.py <CF_TOKEN> <TUNNEL_ID>")
        print("Example: python3 check_tunnel_config.py U0t_FRwlz90YygAzckgS8MQ_7AFqYlErP_x8t6-Y d0feb331-e6c7-48f9-a57f-1ce3c424571f")
        sys.exit(1)
    
    cf_token = sys.argv[1]
    tunnel_id = sys.argv[2]
    check_tunnel_config(cf_token, tunnel_id)
