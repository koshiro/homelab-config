#!/bin/bash
# Batería de pruebas de un NVMe sin uso: TRIM, caché SLC, fsync, APST y temperatura (~60 min).
# DESTRUCTIVA para ese disco. Corre en el host, en segundo plano, y deja todo en /root/prueba-ssd-<serie>/:
#   scp scripts/ssd/prueba.sh root@192.168.1.100:/root/
#   ssh root@192.168.1.100 'nohup bash /root/prueba.sh /dev/disk/by-id/nvme-<modelo>_<serie> --destruir >/dev/null 2>&1 &'
#   (al aparecer DONE) scp -r root@192.168.1.100:/root/prueba-ssd-<serie> . && python3 scripts/ssd/analiza.py prueba-ssd-<serie>
# Así se midió nvme1n1 (KingSpec NE-512) el 2026-10-17: proxmox/README.md § Discos y pools.
set -u
D=${1:?uso: prueba.sh /dev/disk/by-id/nvme-... --destruir}
[ "${2:-}" = --destruir ] || { echo "falta --destruir (borra todo el disco)"; exit 1; }
R=$(readlink -f "$D")
DEV=$(basename "$R")
CTRL=$(basename "$(readlink -f "/sys/block/$DEV/device")")
HW=$(ls -d /sys/class/nvme/"$CTRL"/hwmon* | head -1)
QOS=/sys/class/nvme/$CTRL/power/pm_qos_latency_tolerance_us
O=/root/prueba-ssd-$(cat "/sys/class/nvme/$CTRL/serial" | xargs)

# guardas: el disco no puede estar en un pool ni montado
case "$D" in /dev/disk/by-id/*) ;; *) echo "ABORTA: usar la ruta /dev/disk/by-id/"; exit 1 ;; esac
zpool status -LP | grep -q "/dev/$DEV" && { echo "ABORTA: $DEV está en un pool"; exit 1; }
lsblk -no MOUNTPOINT "$R" | grep -q . && { echo "ABORTA: $DEV montado"; exit 1; }
command -v fio >/dev/null || { echo "ABORTA: apt-get install -y fio"; exit 1; }
mkdir -p "$O"; cd "$O" || exit 1
exec >>"$O/run.log" 2>&1
QOS0=$(cat "$QOS")

paso() { echo "$(date -Is) $*"; }
paso "disco $D -> $R ($CTRL, $(cat "/sys/class/nvme/$CTRL/model" | xargs))"
smartctl -a "$R" >smart-pre.txt

# temperaturas cada 2 s: epoch y temp1..N en °C
( while true; do
    printf '%s' "$(date +%s)"
    for t in "$HW"/temp*_input; do printf ',%s' "$(( $(cat "$t") / 1000 ))"; done
    echo
    sleep 2
  done ) >temps.csv &
TL=$!
trap 'kill $TL 2>/dev/null; echo "$QOS0" >"$QOS"' EXIT
for l in "$HW"/temp*_label; do echo "$(basename "$l"): $(cat "$l")"; done >temps-labels.txt

f() { # f <nombre> <opciones fio...>
  local n=$1; shift
  paso "fio $n"
  fio --name="$n" --filename="$R" --direct=1 --ioengine=libaio --group_reporting \
      --output-format=json --output="$n.json" "$@"
}

# A: estado en que llega el disco (sin TRIM)
f A1-randread-4k-qd1      --rw=randread  --bs=4k   --iodepth=1 --runtime=30 --time_based
f A2-randwrite-4k-fsync   --rw=randwrite --bs=4k   --iodepth=1 --fsync=1 --runtime=60 --time_based
f A3-randwrite-4k-qd1     --rw=randwrite --bs=4k   --iodepth=1 --runtime=60 --time_based
f A4-write-128k-qd4       --rw=write     --bs=128k --iodepth=4 --runtime=60 --time_based
f A5-esporadica-apst-on   --rw=randwrite --bs=4k   --iodepth=1 --thinktime=200000 --thinktime_blocks=1 --runtime=40 --time_based
echo 0 >"$QOS"
f A6-esporadica-apst-off  --rw=randwrite --bs=4k   --iodepth=1 --thinktime=200000 --thinktime_blocks=1 --runtime=40 --time_based
echo "$QOS0" >"$QOS"

# B: tras TRIM completo
paso "blkdiscard"; blkdiscard -f "$R"
f B2-randwrite-4k-fsync   --rw=randwrite --bs=4k   --iodepth=1 --fsync=1 --runtime=60 --time_based
f B3-randwrite-4k-qd1     --rw=randwrite --bs=4k   --iodepth=1 --runtime=60 --time_based
f B4-write-128k-qd4       --rw=write     --bs=128k --iodepth=4 --runtime=60 --time_based

# C: escritura secuencial larga (caché SLC y temperatura), MB/s cada 1 s; corta a los 45 min
f C-llenado-1m-qd8        --rw=write --bs=1M --iodepth=8 --size=90% --runtime=2700 \
                          --write_bw_log=C --log_avg_msec=1000
paso "reposo 300 s"; sleep 300
f D-tras-reposo-1m-qd8    --rw=write --bs=1M --iodepth=8 --offset=0 --runtime=60 --time_based

paso "blkdiscard final"; blkdiscard -f "$R"
smartctl -a "$R" >smart-post.txt
paso "LISTO"
touch "$O/DONE"
