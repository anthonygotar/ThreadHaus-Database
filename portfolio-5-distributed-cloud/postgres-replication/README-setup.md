# PostgreSQL primary and replica for ThreadHaus

Two PostgreSQL servers on one private Docker network, set up as a primary
with one streaming replica. This is my portfolio 5 replication setup.

## The two services

- `pg-primary` (container `threadhaus-pg-primary`): the writable server.
  It publishes `127.0.0.1:5440 -> 5432` and owns the `threadhaus` database.
  It runs with `wal_level=replica`, `max_wal_senders=10` and
  `max_replication_slots=10`, all set as command-line flags in
  `docker-compose.yml`. Its data lives in the named volume
  `threadhaus_pg_primary_data`.
- `pg-replica` (container `threadhaus-pg-replica`): a hot standby copy of
  the primary. It publishes `127.0.0.1:5441 -> 5432` and runs with
  `hot_standby=on`, so I can run read queries against it while it
  replays WAL. Its data lives in the named volume
  `threadhaus_pg_replica_data`.

Both use the `postgres:18.6` image, which matches my local server
(`psql --version` reports 18.6, and the containers report
`PostgreSQL 18.6 (Debian 18.6-1.pgdg13+2)`). Docker is 28.1.1 and Docker
Compose is v2.35.1.

## How to start and stop

The `.env` file must exist first (see below). Then, from this folder:

```bash
docker compose up -d      # start both servers
docker compose ps         # check both are up
docker compose stop       # stop both, keep the data
docker compose down       # remove containers and network, keep the data
docker compose down -v    # remove everything including the data volumes
```

After `docker compose up -d` the replica waits for the primary, takes its
base backup and then starts streaming. That takes a few seconds. Both
containers restart automatically unless I stop them.

Ports 5440 and 5441 are bound to 127.0.0.1 only, so nothing outside this
machine can reach either server. The compose network is fixed to
172.25.0.0/24 so the pg_hba rules below stay valid.

## How replication was set up

1. The primary's init phase (first boot with an empty volume) runs
   `primary-init.sh` inside `/docker-entrypoint-initdb.d/`. It creates the
   role `replicator` with `REPLICATION LOGIN` and a password from
   `.env`, and rewrites `pg_hba.conf`: the image's blanket
   `host all all all` TCP rule is removed and replaced with rules that
   only allow the replication role from the compose network
   (172.25.0.0/24) and the `postgres` user from the network gateway
   (172.25.0.1/32, which is where Docker NAT makes host connections
   through the published port come from). Everything else is TCP-blocked;
   connections from inside the containers use the local Unix socket.
2. The replica's entrypoint is `replica-init.sh`. On first boot it waits
   for the primary to accept connections, then runs:
   `pg_basebackup -d "host=pg-primary port=5432 user=replicator application_name=threadhaus_replica" -D $PGDATA --slot=threadhaus_replica --create-slot -R -X stream -c fast`
   The `-R` flag writes `standby.signal` and `primary_conninfo` into the
   data directory, and with `--slot` it also writes `primary_slot_name`,
   so the WAL receiver keeps the physical slot `threadhaus_replica`
   active on the primary. Without that slot the primary would recycle WAL
   the replica still needs.
3. `pg_basebackup -R` never writes the password into `primary_conninfo`,
   so the WAL receiver authenticates through a `.pgpass` file in the
   replica's data volume (`/var/lib/postgresql/.pgpass`). The
   `PGPASSFILE` environment variable points libpq at it. I deliberately
   avoid `PGPASSWORD` for pg_basebackup, because libpq then copies the
   password into `primary_conninfo`. As a safety net `replica-init.sh`
   also strips any `password=` token from `postgresql.auto.conf` after the
   backup.
4. The replica then starts as a standby with `hot_standby=on` and streams
   WAL from the primary. Replication is asynchronous (`sync_state` =
   `async` in `pg_stat_replication`).

## Loading the ThreadHaus data

`load-threadhaus.sh` loads `portfolio-1-database-design/schema.sql` and
`sample-data.sql` into the primary through the published port
`127.0.0.1:5440`. The password is read from `.env` in this folder and
passed to psql through `PGPASSWORD`, so it is never printed.

## Evidence

`collect-evidence.sh` and `replication-lag-test.sh` gather the replication
proofs into `../evidence/` (status views, 14-table row counts, insert on
primary then read on replica, the read-only rejection, and lag under a
200,000-row load). They use `docker exec` with the container-local Unix
socket, so no password is involved.

## .env is not committed

`.env` holds the real `POSTGRES_PASSWORD` and `REPLICATOR_PASSWORD`. It is
listed in the root `.gitignore` and never committed. Only `.env.example`
with placeholder values is in the repository. To set up, copy it:

```bash
cp .env.example .env
# then edit .env and put strong random values in it
```

One note: if I ever need a fully fresh pair, I use
`docker compose down -v && docker compose up -d`. A plain restart reuses
the existing data volumes, and the replica's `--create-slot` would fail on
a fresh replica volume paired with an old primary volume that still has
the slot.
