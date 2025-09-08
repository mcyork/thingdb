#!/usr/bin/env python3
"""
Check Cloudflare Access logs
"""

import requests
import json
import sys
from datetime import datetime, timedelta

def check_access_logs(cf_token, hours_back=24):
    """Check Cloudflare Access logs"""
    
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
        
        # Calculate time range
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(hours=hours_back)
        
        print(f"\n🔍 Checking Access logs from {start_time.isoformat()} to {end_time.isoformat()}")
        print("=" * 80)
        
        # Check Access logs
        logs_response = requests.get(
            f'https://api.cloudflare.com/client/v4/accounts/{account_id}/access/logs',
            headers=headers,
            params={
                'since': start_time.isoformat() + 'Z',
                'until': end_time.isoformat() + 'Z'
            },
            timeout=30
        )
        
        if logs_response.status_code == 200:
            logs_data = logs_response.json()
            if logs_data.get('success'):
                logs = logs_data.get('result', [])
                print(f"📊 Found {len(logs)} Access log entries")
                
                for i, log in enumerate(logs[:10], 1):  # Show first 10
                    timestamp = log.get('timestamp', 'N/A')
                    action = log.get('action', 'N/A')
                    user_email = log.get('user_email', 'N/A')
                    app_name = log.get('app_name', 'N/A')
                    ip_address = log.get('ip_address', 'N/A')
                    user_agent = log.get('user_agent', 'N/A')
                    
                    print(f"\n📝 Log #{i}:")
                    print(f"   Time: {timestamp}")
                    print(f"   Action: {action}")
                    print(f"   User: {user_email}")
                    print(f"   App: {app_name}")
                    print(f"   IP: {ip_address}")
                    print(f"   User Agent: {user_agent[:50]}...")
                    print("-" * 60)
            else:
                print(f"❌ Failed to get logs: {logs_data.get('errors', [{}])[0].get('message', 'Unknown error')}")
        else:
            print(f"❌ Failed to get Access logs: {logs_response.text}")
        
        # Also check if we can get tunnel logs
        print(f"\n🌐 Checking tunnel logs...")
        print("=" * 40)
        
        # Get tunnel list to find the active one
        tunnels_response = requests.get(
            f'https://api.cloudflare.com/client/v4/accounts/{account_id}/cfd_tunnel',
            headers=headers,
            timeout=10
        )
        
        if tunnels_response.status_code == 200:
            tunnels_data = tunnels_response.json()
            if tunnels_data.get('success'):
                tunnels = tunnels_data.get('result', [])
                
                # Find the most recent tunnel
                if tunnels:
                    latest_tunnel = max(tunnels, key=lambda x: x.get('created_at', ''))
                    tunnel_id = latest_tunnel['id']
                    tunnel_name = latest_tunnel['name']
                    
                    print(f"📡 Latest tunnel: {tunnel_name} ({tunnel_id})")
                    
                    # Try to get tunnel logs (this might not be available via API)
                    print(f"   Note: Tunnel logs may not be available via API")
                    print(f"   Check Cloudflare dashboard for tunnel status")
                else:
                    print("   No tunnels found")
            else:
                print(f"   Failed to get tunnels: {tunnels_data.get('errors', [{}])[0].get('message', 'Unknown error')}")
        else:
            print(f"   Failed to get tunnels: {tunnels_response.text}")
        
    except Exception as e:
        print(f"❌ Error: {str(e)}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 check_access_logs.py <CF_TOKEN> [hours_back]")
        print("Example: python3 check_access_logs.py U0t_FRwlz90YygAzckgS8MQ_7AFqYlErP_x8t6-Y 1")
        sys.exit(1)
    
    cf_token = sys.argv[1]
    hours_back = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    
    check_access_logs(cf_token, hours_back)
