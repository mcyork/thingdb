#!/usr/bin/env python3
"""
Cloudflare Worker Testing Tool
Tests the Worker endpoint for DNS registration
"""

import requests
import json
import sys
import base64
from typing import Dict, Any

class WorkerTester:
    def __init__(self, worker_url: str, device_cert_path: str = None):
        self.worker_url = worker_url
        self.device_cert = None
        
        if device_cert_path:
            with open(device_cert_path, 'rb') as f:
                self.device_cert = base64.b64encode(f.read()).decode()
    
    def test_worker_health(self) -> Dict[str, Any]:
        """Test if the worker is responding"""
        print("🔍 Testing worker health...")
        
        try:
            # Test with GET request (should return 405)
            response = requests.get(self.worker_url, timeout=10)
            
            if response.status_code == 405:
                print("✅ Worker is responding (405 for GET as expected)")
                return {'success': True}
            else:
                print(f"⚠️  Unexpected response: {response.status_code}")
                return {'success': False, 'error': f'Unexpected status: {response.status_code}'}
                
        except Exception as e:
            print(f"❌ Error: {e}")
            return {'success': False, 'error': str(e)}
    
    def test_dns_registration(self, serial: str, tunnel_id: str, email: str) -> Dict[str, Any]:
        """Test DNS registration via worker"""
        print(f"🌐 Testing DNS registration for {serial}...")
        
        try:
            headers = {
                'Content-Type': 'application/json'
            }
            
            if self.device_cert:
                headers['X-Device-Certificate'] = self.device_cert
            
            data = {
                'serial': serial,
                'tunnel_id': tunnel_id,
                'email': email,
                'timestamp': '2024-01-01T00:00:00Z'
            }
            
            response = requests.post(
                self.worker_url,
                headers=headers,
                json=data,
                timeout=30
            )
            
            if response.status_code == 200:
                result = response.json()
                if result.get('success'):
                    print(f"✅ DNS registration successful!")
                    print(f"   URL: {result.get('url')}")
                    print(f"   Action: {result.get('action')}")
                    return {'success': True, 'result': result}
                else:
                    print(f"❌ Registration failed: {result.get('error')}")
                    return {'success': False, 'error': result.get('error')}
            else:
                print(f"❌ HTTP {response.status_code}: {response.text}")
                return {'success': False, 'error': f'HTTP {response.status_code}'}
                
        except Exception as e:
            print(f"❌ Error: {e}")
            return {'success': False, 'error': str(e)}
    
    def test_rate_limiting(self, serial: str) -> Dict[str, Any]:
        """Test rate limiting (if configured)"""
        print(f"⏱️  Testing rate limiting for {serial}...")
        
        try:
            headers = {
                'Content-Type': 'application/json'
            }
            
            if self.device_cert:
                headers['X-Device-Certificate'] = self.device_cert
            
            data = {
                'serial': serial,
                'tunnel_id': 'test-tunnel-id',
                'email': 'test@example.com',
                'timestamp': '2024-01-01T00:00:00Z'
            }
            
            # Make multiple rapid requests
            responses = []
            for i in range(3):
                response = requests.post(
                    self.worker_url,
                    headers=headers,
                    json=data,
                    timeout=10
                )
                responses.append(response.status_code)
            
            if 429 in responses:
                print("✅ Rate limiting is working (429 received)")
                return {'success': True, 'rate_limited': True}
            else:
                print("⚠️  Rate limiting may not be configured")
                return {'success': True, 'rate_limited': False}
                
        except Exception as e:
            print(f"❌ Error: {e}")
            return {'success': False, 'error': str(e)}
    
    def test_invalid_certificate(self) -> Dict[str, Any]:
        """Test invalid certificate handling"""
        print("🔐 Testing invalid certificate handling...")
        
        try:
            headers = {
                'Content-Type': 'application/json',
                'X-Device-Certificate': 'invalid-certificate'
            }
            
            data = {
                'serial': 'test123',
                'tunnel_id': 'test-tunnel-id',
                'email': 'test@example.com'
            }
            
            response = requests.post(
                self.worker_url,
                headers=headers,
                json=data,
                timeout=10
            )
            
            if response.status_code == 401:
                print("✅ Invalid certificate properly rejected (401)")
                return {'success': True}
            else:
                print(f"⚠️  Unexpected response to invalid cert: {response.status_code}")
                return {'success': False, 'error': f'Unexpected status: {response.status_code}'}
                
        except Exception as e:
            print(f"❌ Error: {e}")
            return {'success': False, 'error': str(e)}

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 test_worker.py <worker_url> [device_cert_path]")
        print("\nExample:")
        print("  python3 test_worker.py https://register.inv.esoup.net")
        print("  python3 test_worker.py https://register.inv.esoup.net /path/to/device.crt")
        sys.exit(1)
    
    worker_url = sys.argv[1]
    device_cert_path = sys.argv[2] if len(sys.argv) > 2 else None
    
    tester = WorkerTester(worker_url, device_cert_path)
    
    print("🧪 Cloudflare Worker Testing Tool")
    print("=" * 40)
    
    # Test worker health
    health_result = tester.test_worker_health()
    if not health_result['success']:
        print("❌ Worker health check failed")
        sys.exit(1)
    
    # Test DNS registration
    dns_result = tester.test_dns_registration(
        serial="test123",
        tunnel_id="test-tunnel-123",
        email="test@example.com"
    )
    
    # Test rate limiting
    rate_result = tester.test_rate_limiting("test123")
    
    # Test invalid certificate (if cert verification is enabled)
    if device_cert_path:
        cert_result = tester.test_invalid_certificate()
    else:
        cert_result = {'success': True, 'skipped': True}
    
    # Summary
    print("\n" + "=" * 40)
    print("📊 Test Summary:")
    print(f"   Worker Health: {'✅' if health_result['success'] else '❌'}")
    print(f"   DNS Registration: {'✅' if dns_result['success'] else '❌'}")
    print(f"   Rate Limiting: {'✅' if rate_result['success'] else '❌'}")
    print(f"   Cert Verification: {'✅' if cert_result['success'] else '❌'}")
    
    if all([health_result['success'], dns_result['success'], 
            rate_result['success'], cert_result['success']]):
        print("\n🎉 All tests passed! Your Worker is ready for production.")
    else:
        print("\n⚠️  Some tests failed. Please check your Worker configuration.")

if __name__ == "__main__":
    main()
