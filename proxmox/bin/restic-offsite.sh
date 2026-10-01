#!/bin/bash
# Respaldo offsite cifrado a Cloudflare R2 (docs/ARQUITECTURA.md). Lee desde un snapshot ZFS temporal.
set -euo pipefail
set -a; . /root/.secrets/restic-r2.env; set +a
SNAP=restic-offsite
DATASETS=(nvme/k8s/immich nvme/k8s/minecraft nvme/k8s/backups)
cleanup() { for d in "${DATASETS[@]}"; do zfs destroy "$d@$SNAP" 2>/dev/null || true; done; }
trap cleanup EXIT
cleanup
PATHS=()
for d in "${DATASETS[@]}"; do zfs snapshot "$d@$SNAP"; PATHS+=("/$d/.zfs/snapshot/$SNAP"); done
restic backup --host pve --tag k8s --exclude "**/thumbs/**" --exclude "**/encoded-video/**" "${PATHS[@]}"
restic forget --host pve --tag k8s --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune
# Domingo: verificar 5% de los datos
[ "$(date +%u)" = 7 ] && restic check --read-data-subset=5%
restic snapshots --latest 1 --compact
