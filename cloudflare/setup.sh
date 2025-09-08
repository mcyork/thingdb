#!/bin/bash
# Cloudflare Integration Setup Script

set -e

echo "🚀 Cloudflare Integration Setup"
echo "================================"

# Check if wrangler is installed
if ! command -v wrangler &> /dev/null; then
    echo "❌ Wrangler CLI not found. Installing..."
    npm install -g wrangler
    echo "✅ Wrangler installed"
else
    echo "✅ Wrangler CLI found"
fi

# Check if Python dependencies are available
echo "🐍 Checking Python dependencies..."
python3 -c "import requests" 2>/dev/null || {
    echo "❌ Python requests not found. Installing..."
    pip3 install requests
    echo "✅ Python requests installed"
}

echo "✅ Python dependencies ready"

# Make scripts executable
chmod +x test_api.py test_tunnel.py test_worker.py

echo ""
echo "📋 Next Steps:"
echo "1. Get your Cloudflare API token:"
echo "   https://dash.cloudflare.com/profile/api-tokens"
echo ""
echo "2. Test your API token:"
echo "   python3 test_api.py <your_api_token>"
echo ""
echo "3. Deploy the Worker:"
echo "   wrangler login"
echo "   wrangler secret put CF_API_TOKEN"
echo "   wrangler secret put ZONE_ID"
echo "   wrangler deploy"
echo ""
echo "4. Test the Worker:"
echo "   python3 test_worker.py <worker_url>"
echo ""
echo "5. Test tunnel creation:"
echo "   python3 test_tunnel.py <api_token> <account_id> list"
echo ""
echo "🎉 Setup complete! Check the README.md for detailed instructions."
