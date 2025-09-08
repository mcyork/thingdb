# Cloudflare Integration Prototype

This directory contains prototypes and testing tools for integrating Cloudflare Tunnels with the Inventory Pi system.

## API Key Setup Guide

### 1. DNS Management API Key (for Worker)

You need an API key that can manage DNS records in your domain. Here's how to create it:

1. Go to [Cloudflare Dashboard](https://dash.cloudflare.com/profile/api-tokens)
2. Click "Create Token" → "Custom token"
3. Configure permissions:
   - **Account**: `Zone:Read` (to list zones)
   - **Zone**: `Zone:Read`, `DNS:Edit` (for your specific domain)
4. Zone Resources: Include your domain (e.g., `inv.esoup.net`)
5. Click "Continue to summary" → "Create Token"
6. Copy the token - you'll need it for the Worker

### 2. Tunnel Management API Key (for Pi setup)

This is the key users will provide to set up their tunnels:

1. Go to [Cloudflare Dashboard](https://dash.cloudflare.com/profile/api-tokens)
2. Click "Create Token" → "Custom token"
3. Configure permissions:
   - **Account**: `Cloudflare Tunnel:Edit`
   - **Account**: `Access: Apps and Policies:Edit`
4. Account Resources: Include your account
5. Click "Continue to summary" → "Create Token"
6. This is what users will paste into the Pi setup form

## Testing Tools

- `test_api.py` - Test Cloudflare API connectivity
- `test_tunnel.py` - Test tunnel creation and management
- `test_worker.py` - Test Worker functionality
- `worker.js` - Cloudflare Worker code

## Next Steps

1. Set up your API keys
2. Test basic API connectivity
3. Create a test tunnel
4. Deploy the Worker
5. Test end-to-end flow
