#!/bin/bash
# Verifica que cada respaldo sea reciente; avisa por Telegram si alguno no lo es.
set -uo pipefail
now=$(date +%s); fails=(); oks=()
age_h() { echo $(( (now - $1) / 3600 )); }
chk() { # nombre, epoch, max_horas
  local a; a=$(age_h "$2")
  if [ "${2:-0}" -le 0 ]; then fails+=("$1: nunca"); elif [ "$a" -gt "$3" ]; then fails+=("$1: ${a}h (máx $3h)"); else oks+=("$1: ${a}h"); fi; }
newest_file() { find "$1" -maxdepth 1 -type f -name "$2" -printf "%T@\n" 2>/dev/null | sort -n | tail -1 | cut -d. -f1; }
newest_snap() { zfs list -H -p -t snapshot -o creation -s creation "$1" 2>/dev/null | tail -1; }

chk "dump Postgres (immich)" "$(newest_file /nvme/k8s/backups/postgres "immich-*.dump")" 26
chk "snapshot etcd"          "$(newest_file /nvme/k8s/backups/etcd "etcd-snapshot-*")" 14
for d in immich minecraft pingvin backups webs; do
  chk "sanoid nvme/k8s/$d"   "$(newest_snap nvme/k8s/$d)" 2
  chk "réplica respaldo/$d"  "$(newest_snap respaldo/k8s/$d)" 26
done
set -a; . /root/.secrets/restic-r2.env; set +a
r=$(restic snapshots --host pve --tag k8s --latest 1 --json 2>/dev/null | python3 -c "import json,sys,datetime;s=json.load(sys.stdin);print(int(datetime.datetime.fromisoformat(s[-1][\"time\"][:19]).replace(tzinfo=datetime.timezone.utc).timestamp()) if s else 0)" 2>/dev/null || echo 0)
chk "offsite R2 (restic)" "${r:-0}" 26
for p in $(zpool list -H -o name); do h=$(zpool list -H -o health "$p"); [ "$h" = ONLINE ] || fails+=("pool $p: $h"); done

if [ ${#fails[@]} -gt 0 ]; then
  notify-telegram "$(printf "🚨 Respaldos con problemas:\n"; printf "• %s\n" "${fails[@]}")"; exit 1
elif [ "$(date +%u)" = 1 ]; then
  notify-telegram "$(printf "✅ Resumen semanal de respaldos:\n"; printf "• %s\n" "${oks[@]}")"
fi
printf "%s\n" "${oks[@]}"
