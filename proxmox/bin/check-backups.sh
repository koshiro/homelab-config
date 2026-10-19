#!/bin/bash
# Verifica que cada respaldo sea reciente; avisa por Telegram si alguno no lo es (resumen los lunes).
# DRY_RUN=1 check-backups.sh  -> solo muestra el resultado, sin enviar a Telegram.
set -uo pipefail
now=$(date +%s); fails=(); oks=()

chk() { # nombre, epoch, max_horas
  local e="${2:-0}" a
  [[ "$e" =~ ^[0-9]+$ ]] || e=0
  if [ "$e" -le 0 ]; then fails+=("$1: nunca"); return; fi
  a=$(( (now - e) / 3600 ))
  if [ "$a" -gt "$3" ]; then fails+=("$1: ${a}h (máx $3h)"); else oks+=("$1: ${a}h"); fi
}
newest_file() { find "$1" -maxdepth 1 -type f -name "$2" -printf "%T@\n" 2>/dev/null | sort -n | tail -1 | cut -d. -f1; }
newest_snap() { zfs list -H -p -t snapshot -o creation -s creation "$1" 2>/dev/null | tail -1; }
notify() { if [ -n "${DRY_RUN:-}" ]; then printf "%s\n" "$1"; else notify-telegram "$1"; fi; }

chk "dump Postgres (immich)" "$(newest_file /nvme/k8s/backups/postgres "immich-*.dump")" 26
chk "snapshot etcd"          "$(newest_file /nvme/k8s/backups/etcd "etcd-snapshot-*")" 14
# CNPG → Garage: con la base ociosa sale ~1 WAL cada 45 min (archive_timeout solo corta si hubo escrituras).
chk "WAL Postgres en Garage" "$(find /nvme/k8s/garage/data -type f -printf "%T@\n" 2>/dev/null | sort -n | tail -1 | cut -d. -f1)" 6
# CronJobs config-backup-* (cluster/00-infrastructure/backups/app-config-backup.yaml y
# webs-estaticas-backup.yaml)
for a in plex sonarr radarr prowlarr bazarr overseerr pingvin open-webui \
         minecraft-spiral2 minecraft-spiral3 webodm-db josekast noledigasanadie cyano grafana \
         qbittorrent comfyui canon-mp250-cups meshmonitor; do
  chk "config $a"          "$(newest_file /nvme/k8s/backups/apps/$a ".last-backup")" 26
done
chk "réplica respaldo/comfyui" "$(newest_snap respaldo/comfyui)" 26
for d in immich minecraft minecraft-spiral2 minecraft-spiral3 pingvin backups webs claude-remote garage; do
  chk "sanoid nvme/k8s/$d"   "$(newest_snap "nvme/k8s/$d")" 2
  chk "réplica respaldo/$d"  "$(newest_snap "respaldo/k8s/$d")" 26
  chk "réplica horaria $d"   "$(newest_snap "replica/k8s/$d")" 3
done
# Réplica horaria en nvme1n1 (syncoid-replica.timer): discos de las VMs y root del LXC nas
for v in vm-102-disk-0 vm-103-disk-0 vm-104-disk-0 subvol-110-disk-0; do
  chk "réplica horaria $v"   "$(newest_snap "replica/$v")" 3
done

set -a; . /root/.secrets/restic-r2.env; set +a
export RESTIC_CACHE_DIR=/var/cache/restic
rt=$(restic snapshots --host pve --tag k8s --latest 1 --json 2>/dev/null \
  | python3 -c 'import json,sys; s=json.load(sys.stdin); print(s[-1]["time"] if s else "")' 2>/dev/null)
r=0; [ -n "$rt" ] && r=$(date -d "$rt" +%s 2>/dev/null || echo 0)
chk "offsite R2 (restic)" "$r" 26

for p in $(zpool list -H -o name); do
  h=$(zpool list -H -o health "$p"); [ "$h" = ONLINE ] || fails+=("pool $p: $h")
done
for p in nvme respaldo replica; do zpool list "$p" >/dev/null 2>&1 || fails+=("pool $p: no importado"); done

# Dead-man's switch del monitor externo (cloudflare/monitor): avisa si este script deja de correr
if [ -z "${DRY_RUN:-}" ] && [ -r /root/.secrets/monitor.env ]; then
  ( . /root/.secrets/monitor.env
    curl -fsS -m 15 -X POST -H "Authorization: Bearer $HEARTBEAT_TOKEN" "$MONITOR_URL/ping/check-backups" >/dev/null ) \
    || echo "aviso: no se pudo hacer ping al monitor externo" >&2
fi

if [ ${#fails[@]} -gt 0 ]; then
  notify "$(printf "🚨 Respaldos con problemas:\n"; printf "• %s\n" "${fails[@]}")"; exit 1
elif [ "$(date +%u)" = 1 ]; then
  notify "$(printf "✅ Resumen semanal de respaldos:\n"; printf "• %s\n" "${oks[@]}")"
fi
printf "%s\n" "${oks[@]}"
