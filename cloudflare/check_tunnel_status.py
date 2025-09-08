#!/usr/bin/env python3
"""
Check Cloudflare Tunnel Status and Edge Registration
"""

import requests
import json
import sys
import time

def check_tunnel_status(cf_token, tunnel_id=None):
    """Check tunnel status and edge registration"""
    
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
        
        print(f"\n🔍 Found {len(tunnels)} tunnel(s):")
        print("=" * 60)
        
        for tunnel in tunnels:
            tunnel_id = tunnel['id']
            tunnel_name = tunnel['name']
            created_at = tunnel['created_at']
            
            print(f"\n📡 Tunnel: {tunnel_name}")
            print(f"   ID: {tunnel_id}")
            print(f"   Created: {created_at}")
            
            # Check tunnel status
            status_response = requests.get(
                f'https://api.cloudflare.com/client/v4/accounts/{account_id}/cfd_tunnel/{tunnel_id}/status',
                headers=headers,
                timeout=10
            )
            
            if status_response.status_code == 200:
                status_data = status_response.json()
                if status_data.get('success'):
                    status_info = status_data['result']
                    print(f"   Status: {status_info.get('status', 'Unknown')}")
                    print(f"   Connectors: {status_info.get('connectors', [])}")
                else:
                    print(f"   Status: ❌ Error - {status_data.get('errors', [{}])[0].get('message', 'Unknown')}")
            else:
                print(f"   Status: ❌ Failed to get status - {status_response.text}")
            
            # Check if tunnel has DNS records
            dns_response = requests.get(
                f'https://api.cloudflare.com/client/v4/zones',
                headers=headers,
                timeout=10
            )
            
            if dns_response.status_code == 200:
                zones_data = dns_response.json()
                for zone in zones_data.get('result', []):
                    zone_id = zone['id']
                    zone_name = zone['name']
                    
                    # Look for CNAME records pointing to this tunnel
                    dns_records_response = requests.get(
                        f'https://api.cloudflare.com/client/v4/zones/{zone_id}/dns_records',
                        headers=headers,
                        timeout=10
                    )
                    
                    if dns_records_response.status_code == 200:
                        records_data = dns_records_response.json()
                        for record in records_data.get('result', []):
                            if record['type'] == 'CNAME' and tunnel_id in record['content']:
                                print(f"   DNS: ✅ {record['name']} -> {record['content']}")
                                break
                        else:
                            print(f"   DNS: ❌ No CNAME records found in {zone_name}")
                    else:
                        print(f"   DNS: ❌ Failed to check DNS in {zone_name}")
            else:
                print(f"   DNS: ❌ Failed to get zones")
            
            print("-" * 40)
        
        # Check edge connectivity
        print(f"\n🌐 Edge Connectivity Test:")
        print("=" * 30)
        
        # Test a few common tunnel endpoints
        test_hostnames = [
            f"{tunnel_id}.cfargotunnel.com",
            f"{tunnel_id}.nestdb.io"
        ]
        
        for hostname in test_hostnames:
            try:
                import socket
                result = socket.getaddrinfo(hostname, 443, socket.AF_INET)
                if result:
                    print(f"✅ {hostname} resolves to IPv4")
                else:
                    print(f"❌ {hostname} does not resolve to IPv4")
            except Exception as e:
                print(f"❌ {hostname} resolution failed: {e}")
        
    except Exception as e:
        print(f"❌ Error: {str(e)}")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python3 check_tunnel_status.py <CF_TOKEN>")
        print("Example: python3 check_tunnel_status.py fLqPRBsBHg6rbiqgtAoGLLXfzDtN9_03rVzfLmTZ")
        sys.exit(1)
    
    cf_token = sys.argv[1]
    check_tunnel_status(cf_token)
