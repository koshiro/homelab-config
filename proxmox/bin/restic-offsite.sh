#!/bin/bash
# Respaldo offsite cifrado a Cloudflare R2 (docs/ARQUITECTURA.md). Lee desde un snapshot ZFS temporal
# montado explícitamente en solo lectura (NO vía .zfs/snapshot: el automount dispara un PANIC
# en avl_add con OpenZFS 2.3.3, visto el 2026-10-01).
set -euo pipefail
set -a; . /root/.secrets/restic-r2.env; set +a
SNAP=restic-offsite
MNT=/run/restic-offsite
DATASETS=(nvme/k8s/immich nvme/k8s/minecraft nvme/k8s/backups nvme/k8s/webs)
cleanup() {
  for d in "${DATASETS[@]}"; do
    mountpoint -q "$MNT/$d" && umount "$MNT/$d"
    zfs destroy "$d@$SNAP" 2>/dev/null || true
  done
}
trap cleanup EXIT
cleanup
PATHS=()
for d in "${DATASETS[@]}"; do
  zfs snapshot "$d@$SNAP"
  mkdir -p "$MNT/$d"
  mount -t zfs -o ro "$d@$SNAP" "$MNT/$d"
  PATHS+=("$MNT/$d")
done
restic backup --host pve --tag k8s --exclude "**/thumbs/**" --exclude "**/encoded-video/**" "${PATHS[@]}"
restic forget --host pve --tag k8s --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune
# Domingo: verificar 5% de los datos
if [ "$(date +%u)" = 7 ]; then restic check --read-data-subset=5%; fi
restic snapshots --latest 1 --compact
