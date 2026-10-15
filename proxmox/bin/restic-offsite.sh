#!/bin/bash
# Respaldo offsite cifrado a Cloudflare R2 (docs/ARQUITECTURA.md). Lee desde un snapshot ZFS temporal
# montado explícitamente en solo lectura (NO vía .zfs/snapshot: el automount dispara un PANIC
# en avl_add con OpenZFS 2.3.3, visto el 2026-10-01).
set -euo pipefail
set -a; . /root/.secrets/restic-r2.env; set +a
SNAP=restic-offsite
MNT=/run/restic-offsite
# garage = respaldos base + WAL de CNPG (PITR, ~2–3 GB con retención de 30 días).
DATASETS=(nvme/k8s/immich nvme/k8s/minecraft nvme/k8s/backups nvme/k8s/webs nvme/k8s/garage)
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
# Quita solo locks huérfanos (p. ej. tras un reinicio forzado)
restic unlock
# A R2 solo va lo que no se regenera ni se vuelve a descargar (objetivo: < 10 GB del nivel gratuito).
# Fuera: miniaturas/transcodificados de Immich, sus dumps internos (ya está backups/postgres) y
# los binarios/librerías/caché de Minecraft. La historia larga queda en ZFS (nvme y respaldo).
EXCLUDES=(
  "**/thumbs/**" "**/encoded-video/**"
  "$MNT/nvme/k8s/immich/backups"
  "$MNT/nvme/k8s/minecraft/libraries" "$MNT/nvme/k8s/minecraft/versions"
  "$MNT/nvme/k8s/minecraft/cache" "$MNT/nvme/k8s/minecraft/.cache"
  "$MNT/nvme/k8s/minecraft/logs" "$MNT/nvme/k8s/minecraft/*.jar"
)
restic backup --host pve --tag k8s "${EXCLUDES[@]/#/--exclude=}" "${PATHS[@]}"
# Pocas copias: el dedup hace que cada una cueste solo lo que cambió
restic forget --host pve --tag k8s --keep-daily 3 --keep-weekly 2 --prune
# Domingo: verificar 5% de los datos
if [ "$(date +%u)" = 7 ]; then restic check --read-data-subset=5%; fi
restic snapshots --latest 1 --compact
