#!/usr/bin/env python3
"""
Clean up old Cloudflare tunnels
"""

import requests
import json
import sys

def cleanup_tunnels(cf_token, keep_latest=1):
    """Clean up old tunnels, keeping only the latest ones"""
    
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
        
        # List all tunnels
        tunnels_response = requests.get(
            f'https://api.cloudflare.com/client/v4/accounts/{account_id}/cfd_tunnel',
            headers=headers,
            timeout=10
        )
        
        if tunnels_response.status_code != 200:
            print(f"❌ Failed to get tunnels: {tunnels_response.text}")
            return
        
        tunnels_data = tunnels_response.json()
        tunnels = tunnels_data.get('result', [])
        
        print(f"\n🔍 Found {len(tunnels)} tunnel(s)")
        
        # Group tunnels by name
        tunnel_groups = {}
        for tunnel in tunnels:
            name = tunnel['name']
            if name not in tunnel_groups:
                tunnel_groups[name] = []
            tunnel_groups[name].append(tunnel)
        
        # Clean up each group
        for name, group in tunnel_groups.items():
            print(f"\n📡 Processing group: {name}")
            print(f"   Found {len(group)} tunnel(s)")
            
            # Sort by creation date (newest first)
            group.sort(key=lambda x: x['created_at'], reverse=True)
            
            # Keep the latest ones, delete the rest
            to_delete = group[keep_latest:]
            
            for tunnel in to_delete:
                tunnel_id = tunnel['id']
                created_at = tunnel['created_at']
                
                print(f"   🗑️  Deleting tunnel {tunnel_id} (created: {created_at})")
                
                delete_response = requests.delete(
                    f'https://api.cloudflare.com/client/v4/accounts/{account_id}/cfd_tunnel/{tunnel_id}',
                    headers=headers,
                    timeout=30
                )
                
                if delete_response.status_code == 200:
                    print(f"   ✅ Deleted successfully")
                else:
                    print(f"   ❌ Failed to delete: {delete_response.text}")
            
            print(f"   ✅ Kept {min(keep_latest, len(group))} tunnel(s)")
        
        print(f"\n🎉 Cleanup complete!")
        
    except Exception as e:
        print(f"❌ Error: {str(e)}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 cleanup_tunnels.py <CF_TOKEN> [keep_count]")
        print("Example: python3 cleanup_tunnels.py U0t_FRwlz90YygAzckgS8MQ_7AFqYlErP_x8t6-Y 1")
        sys.exit(1)
    
    cf_token = sys.argv[1]
    keep_count = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    
    cleanup_tunnels(cf_token, keep_count)
