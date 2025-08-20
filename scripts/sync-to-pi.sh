#!/bin/bash

# Continuous rsync script for syncing local src/ to Pi
# This makes development and testing much easier

PI_IP="192.168.43.204"
PI_USER="pi"
PI_PATH="/var/lib/inventory/app"
LOCAL_SRC="/Users/ianmccutcheon/projects/inv2-dev/src"

echo "🔄 Setting up continuous rsync sync to Pi..."
echo "   Local: $LOCAL_SRC"
echo "   Remote: $PI_USER@$PI_IP:$PI_PATH"
echo "   Press Ctrl+C to stop"
echo ""

# Initial sync
echo "📤 Initial sync..."
rsync -avz --delete "$LOCAL_SRC/" "$PI_USER@$PI_IP:$PI_PATH/"

# Continuous sync every 2 seconds
echo "🔄 Starting continuous sync (every 2 seconds)..."
while true; do
    rsync -avz --delete "$LOCAL_SRC/" "$PI_USER@$PI_IP:$PI_PATH/" > /dev/null 2>&1
    sleep 2
done
