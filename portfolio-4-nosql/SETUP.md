# Portfolio 4 NoSQL — Setup

This folder runs two NoSQL services for the ThreadHaus case study using Docker Compose.

## Services

**MongoDB 7.0** (`threadhaus-mongo`)
A document database. I use it in portfolio 4 to store product catalogue and order documents. The image pulled is `mongo:7.0` (server version 7.0.45). The container uses a named Docker volume (`mongo_data`) so data survives restarts.

**Redis 7.4** (`threadhaus-redis`)
A key-value store. I use it for session cache and stock counters. The image pulled is `redis:7.4` (server version 7.4.12). Started with `--appendonly yes` for persistence and `--requirepass` for authentication. Data stored in a named volume (`redis_data`).

Both ports are published to `127.0.0.1` only, so neither service is reachable from outside the machine.

## Credentials

Credentials are stored in `.env`. That file is not committed to the repo — it is listed in `.gitignore`. Copy `.env.example` to `.env` and fill in strong passwords before starting the containers.

```bash
cp .env.example .env
# edit .env and set real passwords
```

## Start and stop

```bash
cd portfolio-4-nosql/

# Start both containers in the background
docker compose up -d

# Check status
docker ps --filter name=threadhaus

# Stop and remove containers (volumes are kept)
docker compose down

# Stop and remove containers AND volumes (deletes all data)
docker compose down -v
```

## Connect

**MongoDB:**
```bash
docker exec -it threadhaus-mongo mongosh \
  --username threadhaus_admin \
  --password "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin
```

**Redis:**
```bash
docker exec -it threadhaus-redis redis-cli -a "$REDIS_PASSWORD"
```

Or connect from the host (both ports are on localhost):
```bash
mongosh "mongodb://threadhaus_admin:<password>@127.0.0.1:27017/admin"
redis-cli -h 127.0.0.1 -p 6379 -a <password>
```

## Versions pulled

| Service | Image | Server version |
|---|---|---|
| MongoDB | mongo:7.0 | 7.0.45 |
| Redis | redis:7.4 | 7.4.12 |

Recorded from `docker image ls` and verified by querying the running servers (see `evidence/environment-check.txt`).

## Note on .env

`.env` holds the real credentials and is excluded from git via `.gitignore`. It must exist before running `docker compose up`. Use `.env.example` as a template. Never commit `.env`.
