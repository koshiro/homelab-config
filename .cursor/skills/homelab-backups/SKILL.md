---
name: homelab-backups
description: Sistema de respaldos del homelab. sanoid/syncoid/restic en el host Proxmox (pve) y CronJobs de k8s que dejan config y DB en nvme/k8s/backups. Usar cuando se configure, verifique o corrija respaldos. TrueNAS está retirado.
---

# Sistema de Respaldos del Homelab

Fuente de verdad: `proxmox/README.md` (host) y `cluster/00-infrastructure/backups/` (k8s).
TrueNAS (192.168.1.20) está **retirado**: no usar sus scripts ni su API.

## Acceso

- Proxmox: `ssh root@192.168.1.100` en la LAN; fuera de casa `ssh root@pve` (Tailscale).
- Cluster: `kubectl` local en el Mac.
- Red inestable: lanzar trabajos largos con `nohup` en el host y consultar el log con comandos cortos.

## Cadena de respaldo

```
apps k8s ──CronJobs──► nvme/k8s/* (NVMe, Proxmox) ──sanoid──► snapshots horarios/diarios
                                  │
                                  ├──syncoid 03:30──► respaldo/k8s/* (disco sde, mismo host)
                                  └──restic 04:30───► Cloudflare R2 homelab/restic (offsite, cifrado)
```

| Hora | Tarea | Dónde |
|---|---|---|
| cada 15 min | sanoid: snapshots `nvme/k8s/*` (24 h, 14 d, 4 sem, 6 m) y poda de `respaldo/k8s/*` (30 d, 8 sem, 12 m) | host |
| 00:30 / 12:30 | `etcd-snapshot-copy` → `nvme/k8s/backups/etcd` (7 días) | k8s, ns `backups` |
| 02:40–02:46 | `config-backup-*`: config + DB de apps con PVC local-path → `nvme/k8s/backups/apps/<app>` | k8s, ns de cada app |
| 03:15 | `immich-db-backup` (pg_dump) → `nvme/k8s/backups/postgres` (5 días) | k8s, ns `immich` |
| 03:30 | `syncoid-respaldo` `nvme/k8s` → `respaldo/k8s` | host |
| 04:30 | `restic-offsite`: immich, minecraft, backups, webs → R2; retiene 3 diarios + 2 semanales; domingo `restic check` 5 % | host |
| 08:00 | `check-backups`: frescura de todo; alerta Telegram si falla, resumen los lunes | host |

Apps cubiertas por `config-backup-*`: plex, sonarr, radarr, prowlarr, bazarr, overseerr,
pingvin, open-webui, minecraft-spiral2/3, webodm-db. Las DB SQLite se copian con la API de
backup (consistente con la app corriendo); WebODM con pg_dump. Los proyectos de WebODM no
se respaldan (decisión de Daniel).

Datos que viven en NFS (`nvme/k8s/immich|minecraft|pingvin|webs`) ya están en la cadena sin CronJob.

## Qué NO se respalda (a propósito)

- Lo regenerable o descargable: MediaCover/logs de las *arr, Metadata/Media/Cache de Plex,
  librerías/jars/caché de Minecraft, modelos de Ollama y embeddings de Open WebUI, miniaturas
  y videos transcodificados de Immich.
- `homelab-storage/k8s-media-library` (la media se vuelve a descargar).
- `homelab-storage/media` y `comfyui`: solo snapshots sanoid locales (sin réplica ni offsite).
- VMs (no hay vzdump): los workers se reconstruyen con Ansible.

## R2: mantener bajo 10 GB (nivel gratuito)

- Precio: US$0,015/GB-mes sobre 10 GB; egress gratis; 1 M ops clase A y 10 M clase B gratis al mes.
- Contenido principal: originales de Immich (~4,8 GB), dumps, mundo de Minecraft, config de apps.
- Antes de sumar algo a restic, revisar tamaño y excluir lo regenerable en `proxmox/bin/restic-offsite.sh`.

## Verificar

```bash
# Frescura de todo, sin enviar a Telegram (ojo: es variable, no flag)
ssh root@pve 'DRY_RUN=1 /usr/local/sbin/check-backups.sh'

# Timers y unidades fallidas
ssh root@pve 'systemctl list-timers --all | grep -E "sanoid|syncoid|restic|check-backups"; systemctl --failed'

# Log de una noche (fechas absolutas: journalctl no entiende "yesterday 20:00")
ssh root@pve 'journalctl -u restic-offsite.service --since "2026-10-05 04:00" --no-pager -o cat'

# CronJobs k8s
kubectl get cronjobs -A; kubectl get jobs -A --sort-by=.metadata.creationTimestamp | tail

# Contenido de R2
ssh root@pve 'set -a; . /root/.secrets/restic-r2.env; set +a; restic snapshots --compact; restic stats --mode raw-data'
```

## Ejecutar a mano

```bash
kubectl create job -n plex config-backup-plex-manual --from=cronjob/config-backup-plex
ssh root@pve 'systemctl start syncoid-respaldo.service'
ssh root@pve 'systemctl start restic-offsite.service'
```

## Restaurar

- Config de una app: escalar a 0, copiar `nvme/k8s/backups/apps/<app>/data/` sobre el PVC
  (`chown -R 1000:1000`), escalar a 1. Versiones anteriores: snapshots sanoid de `nvme/k8s/backups`.
- Snapshot ZFS: montar con `mount -t zfs -o ro <dataset>@<snap> /mnt/x`. **No** entrar a
  `.zfs/snapshot` (el automount provoca un PANIC con OpenZFS 2.3.3).
- Desde R2: ver `proxmox/README.md` (`restic restore latest --target /tmp/restore --include ...`).
- Immich DB: `pg_restore` (comando en la cabecera de `cluster/apps/immich/05-backup-postgres.yaml`).
- etcd: `k3s server --cluster-reset --cluster-reset-restore-path=<snapshot>`.

## Archivos

- `proxmox/bin/{restic-offsite.sh,check-backups.sh,notify-telegram}` → `/usr/local/sbin/`
- `proxmox/systemd/*` → `/etc/systemd/system/`; `proxmox/etc/sanoid.conf` → `/etc/sanoid/`
- `cluster/00-infrastructure/backups/{etcd-snapshot-copy,app-config-backup}.yaml`
- `cluster/apps/immich/05-backup-postgres.yaml`
- Secretos en `/root/.secrets/` del host (copia maestra en `ansible/vars/vault.yml`)
