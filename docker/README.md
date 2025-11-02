# ThingDB Docker Deployment

All-in-one Docker container with PostgreSQL and ThingDB application.

## 🚀 Quick Start

```bash
# Start ThingDB
docker-compose -f docker/docker-compose.yml up -d

# View startup logs (first run downloads ML models ~500MB)
docker-compose -f docker/docker-compose.yml logs -f

# Access ThingDB
open http://localhost:5000
```

That's it! The container automatically:
- Initializes PostgreSQL
- Creates database and user
- Initializes ThingDB schema
- Downloads ML models (first run only)
- Starts the web interface

## 📦 What's Included

**Single container with:**
- PostgreSQL 17
- ThingDB web application
- Sentence transformers for semantic search
- All dependencies

**Persistent volumes:**
- Database data
- ML model cache
- User uploads

## 🏗️ Architecture

```
┌────────────────────────────────────┐
│      ThingDB Container             │
│                                    │
│  ┌──────────┐    ┌──────────┐    │
│  │PostgreSQL│◄───┤ ThingDB  │    │
│  │(internal)│    │  (5000)  │    │
│  └──────────┘    └──────────┘    │
│                                    │
│  Volumes:                          │
│  • postgres_data                   │
│  • ml_cache                        │
│  • uploads                         │
└────────────────────────────────────┘
```

## 🔧 Configuration

Edit environment variables in `docker-compose.yml`:

```yaml
environment:
  POSTGRES_PASSWORD: your_secure_password
  SECRET_KEY: your_secure_secret_key
  FLASK_ENV: production
```

**⚠️ Change secrets before production deployment!**

## 📋 Common Commands

```bash
# Start
docker-compose -f docker/docker-compose.yml up -d

# View logs
docker-compose -f docker/docker-compose.yml logs -f

# Stop
docker-compose -f docker/docker-compose.yml down

# Rebuild after code changes
docker-compose -f docker/docker-compose.yml up -d --build

# Access container shell
docker exec -it thingdb bash

# Run ThingDB CLI commands
docker exec -it thingdb thingdb --help
```

## 🗄️ Data Persistence

All data persists in Docker volumes:
- `postgres_data` - Database files (survives restarts)
- `ml_cache` - ML models (~500MB, downloaded once)
- `uploads` - User uploaded images
- `thingdb_data` - Application state

**Remove all data (⚠️ destructive):**
```bash
docker-compose -f docker/docker-compose.yml down -v
```

## 🐛 Troubleshooting

### First startup is slow
ML models are downloaded on first run (~500MB). Watch logs:
```bash
docker logs -f thingdb
```

### Container won't start
Check logs for errors:
```bash
docker logs thingdb
```

### Database connection errors
PostgreSQL starts inside the container. Wait 30 seconds after startup:
```bash
docker exec thingdb ps aux | grep postgres
```

### Reset everything
```bash
# Stop and remove all data
docker-compose -f docker/docker-compose.yml down -v

# Start fresh
docker-compose -f docker/docker-compose.yml up -d
```

## 📊 Resource Requirements

**Minimum:**
- CPU: 2 cores
- RAM: 2GB
- Disk: 5GB

**Recommended:**
- CPU: 4 cores
- RAM: 4GB
- Disk: 10GB

## 🔒 Production Deployment

1. **Change secrets** in `docker-compose.yml` or use `.env` file:
   ```bash
   echo "POSTGRES_PASSWORD=$(openssl rand -base64 32)" > docker/.env
   echo "SECRET_KEY=$(openssl rand -base64 32)" >> docker/.env
   ```

2. **Add reverse proxy** (nginx/traefik) for HTTPS:
   ```nginx
   location / {
       proxy_pass http://localhost:5000;
       proxy_set_header Host $host;
       proxy_set_header X-Real-IP $remote_addr;
   }
   ```

3. **Enable firewall** to restrict port 5000 access

## 🆚 Docker vs Raspberry Pi

| Feature | Docker | Raspberry Pi |
|---------|--------|--------------|
| Setup | One command | One command |
| Installation | `docker-compose up` | `./install.sh` |
| Service | Docker managed | Systemd |
| Updates | Rebuild image | `git pull && pip install` |
| Best for | Development, cloud | Production appliance |

## 🔗 Links

- [Main README](../README.md)
- [Installation Guide](../INSTALL.md)
- [ThingDB Documentation](../docs/)
