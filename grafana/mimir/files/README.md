# Grafana Mimir — Single Instance, Local Storage

One Mimir container. Everything lives on a local Docker volume
(`mimir-data`). No object store, no extra services.

## Quick start

```bash
docker compose up -d
docker compose logs -f mimir
```

Wait for the ready endpoint:

```bash
curl http://localhost:9009/ready
```

## Connect your Grafana

Add a **Prometheus** data source:

- **URL**: `http://<host>:9009/prometheus`
- **Custom HTTP Header**: `X-Scope-OrgID: <tenant>` (e.g. `anonymous`)

## Sending data

```yaml
# prometheus.yml
remote_write:
  - url: http://<host>:9009/api/v1/push
    headers:
      X-Scope-OrgID: my-tenant
```

OTLP push: `POST http://<host>:9009/otlp/v1/metrics` with the same header.

## Storage layout

Inside the container, everything is under `/data` (the `mimir-data` volume):

| Path                          | Contents                              |
|-------------------------------|---------------------------------------|
| `/data/tsdb`                  | Ingester TSDB head + WAL              |
| `/data/blocks`                | Long-term TSDB blocks (the main store)|
| `/data/tsdb-sync`             | Store-gateway local sync of blocks    |
| `/data/compactor`             | Compactor working area                |
| `/data/ruler-storage`         | Recording / alerting rule definitions |
| `/data/ruler`                 | Ruler runtime state                   |
| `/data/alertmanager-storage`  | Per-tenant alertmanager configs       |
| `/data/alertmanager`          | Alertmanager nflog + silences         |

To find the volume on the host:

```bash
docker volume inspect mimir-local_mimir-data
```

## Caveats of filesystem storage

The filesystem backend is officially supported but designed for
single-instance / dev / small deployments. Specifically:

- **No replication** — if the disk dies, you lose everything.
  Back up the `mimir-data` volume regularly.
- **No HA** — only one Mimir replica can read/write the directory at a time.
- **Disk fills up** — keep an eye on `compactor_blocks_retention_period`
  in `config/mimir.yaml` (default 90d) and your disk free space.

If you outgrow this, switch the `backend: filesystem` blocks to
`backend: s3` (or `gcs`/`azure`) and add the credentials. No other
config changes needed.

## Per-tenant overrides

Edit `config/runtime.yaml`:

```yaml
overrides:
  team-a:
    ingestion_rate: 200000
    max_global_series_per_user: 3000000
  team-b:
    compactor_blocks_retention_period: 30d
```

Hot-reloaded every 10s.

## Backups

Easiest approach — stop Mimir, copy the volume, start it again:

```bash
docker compose stop mimir
docker run --rm -v mimir-local_mimir-data:/data -v $(pwd):/backup alpine \
  tar czf /backup/mimir-backup-$(date +%F).tar.gz -C /data .
docker compose start mimir
```

For backups without downtime, snapshot the underlying filesystem
(LVM, ZFS, btrfs, EBS snapshot, etc.) instead.

## Troubleshooting

- **`/ready` returns 503** — give it 60s on first start, then check
  `docker compose logs mimir`.
- **429 on writes** — hitting `ingestion_rate` or `max_global_series_per_user`.
  Bump in `config/mimir.yaml` under `limits` or per-tenant in `runtime.yaml`.
- **Grafana shows "no data"** — verify the `X-Scope-OrgID` header matches
  what you used in `remote_write`.
- **Disk filling up** — lower `compactor_blocks_retention_period` and wait
  for the next compactor cleanup cycle (every 15m).
