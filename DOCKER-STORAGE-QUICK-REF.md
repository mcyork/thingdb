# Docker Storage Testing - Quick Reference

## 🚀 Essential Commands

```bash
# Start both configurations
./scripts/manage-docker-storage.sh start

# Test both configurations  
./scripts/manage-docker-storage.sh test

# Stop everything
./scripts/manage-docker-storage.sh stop

# Check status
./scripts/manage-docker-storage.sh status
```

## 🌐 Access URLs

- **Database Storage**: https://localhost:8444 (images in PostgreSQL BLOB)
- **Filesystem Storage**: https://localhost:8443 (images on local filesystem)
- **Local Images**: `/tmp/inventory-images`

## 🔄 Development Workflow

1. **Make code changes** in `src/` directory
2. **Start testing environment**: `./scripts/manage-docker-storage.sh start`
3. **Test changes**: `./scripts/manage-docker-storage.sh test`
4. **Stop when done**: `./scripts/manage-docker-storage.sh stop`

## 🧹 Clean Restart

```bash
# Stop everything
./scripts/manage-docker-storage.sh stop

# Start fresh
./scripts/manage-docker-storage.sh start

# Or restart in one command
./scripts/manage-docker-storage.sh restart
```

## 🔍 Troubleshooting

- **Port conflicts**: Check if ports 8443/8444 are in use
- **Container issues**: Use `./scripts/manage-docker-storage.sh clean` to remove everything
- **Slow startup**: Normal for first run, subsequent starts are faster
- **Test failures**: Check that both services are responding with `./scripts/manage-docker-storage.sh status`

## 💡 Why This Setup

- **Consistent Testing**: Both storage methods tested simultaneously
- **Latest Code**: Always tests current `src/` directory changes
- **No Conflicts**: Isolated containers and volumes
- **Production Ready**: Same code that will run on Pi and production
