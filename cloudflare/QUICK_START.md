# Quick Start Guide - Cloudflare Integration

## 🚀 Getting Started

### 1. Get Your Cloudflare API Token

1. Go to [Cloudflare Dashboard](https://dash.cloudflare.com/profile/api-tokens)
2. Click "Create Token" → "Custom token"
3. Configure permissions:
   - **Account**: `Read`
   - **Zone**: `Read`, `DNS:Edit` (for your domain)
   - **Account**: `Cloudflare Tunnel:Edit`
   - **Account**: `Access: Apps and Policies:Edit`
4. Zone Resources: Include your domain (e.g., `inv.esoup.net`)
5. Click "Continue to summary" → "Create Token"
6. Copy the token

### 2. Test Your API Token

```bash
python3 test_api.py <your_api_token>
```

This will show you:
- ✅ Token validation
- ✅ Account access
- ✅ Zone access
- ✅ Tunnel permissions
- ✅ Access permissions

### 3. Deploy the Worker

```bash
# Login to Cloudflare
wrangler login

# Set your secrets
wrangler secret put CF_API_TOKEN
wrangler secret put ZONE_ID

# Deploy the worker
wrangler deploy
```

### 4. Test the Worker

```bash
python3 test_worker.py https://your-worker.your-domain.com
```

### 5. Test Tunnel Creation

```bash
# List existing tunnels
python3 test_tunnel.py <api_token> <account_id> list

# Create a test tunnel
python3 test_tunnel.py <api_token> <account_id> create test-tunnel

# Run full test (creates tunnel + DNS + Access)
python3 test_tunnel.py <api_token> <account_id> full-test <zone_id> test.example.com test@example.com
```

## 🔧 Integration with Flask App

To integrate this with your Flask app:

1. Copy `flask_integration.py` to your Flask app
2. Register the blueprint in your main app
3. Copy `remote_access.html` to your templates directory
4. Test the integration

```python
# In your main Flask app
from cloudflare.flask_integration import remote_access_bp

app.register_blueprint(remote_access_bp)
```

## 🧪 Testing Checklist

- [ ] API token works for all required permissions
- [ ] Worker deploys successfully
- [ ] Worker responds to test requests
- [ ] Tunnel creation works
- [ ] DNS record creation works
- [ ] Access app creation works
- [ ] Flask integration works

## 🚨 Common Issues

### "Insufficient permissions"
- Check your API token has all required permissions
- Make sure Zone Resources includes your domain

### "Worker deployment failed"
- Make sure you're logged in: `wrangler login`
- Check your secrets are set: `wrangler secret list`

### "Tunnel creation failed"
- Check your account has Cloudflare Tunnel enabled
- Verify your API token has tunnel permissions

## 📚 Next Steps

Once you're comfortable with the API:

1. **Integrate with your Pi image** - Add the Flask blueprint to your deployment
2. **Add device certificates** - Implement the certificate-based authentication
3. **Add rate limiting** - Configure KV namespaces for production
4. **Add monitoring** - Set up logging and analytics
5. **Add custom domains** - Allow users to use their own domains

## 🎯 Production Considerations

- Use KV namespaces for rate limiting and logging
- Implement proper error handling and logging
- Add monitoring and alerting
- Consider adding a management dashboard
- Add support for multiple domains per user
- Implement proper certificate management
