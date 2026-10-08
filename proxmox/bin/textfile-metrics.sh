#!/bin/bash
# Métricas de ZFS y SMART para el textfile collector de node_exporter (VictoriaMetrics las lee en
# 192.168.1.100:9100, job pve-host). Lo corre textfile-metrics.timer cada 5 min.
# smartctl -n standby: nunca despierta un disco dormido (se reporta smart_standby=1 y nada más).
# Prueba: textfile-metrics.sh -   (imprime en pantalla; nunca pasar /dev/stdout: el mv final lo reemplazaría)
set -uo pipefail
out="${1:-/var/lib/prometheus/node-exporter/homelab.prom}"
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

{
  echo "# HELP zfs_pool_size_bytes Tamaño, uso y libre de cada pool (zpool list)."
  echo "# TYPE zfs_pool_size_bytes gauge"
  zpool list -Hp -o name,size,alloc,free,frag,health | while read -r n size alloc free frag health; do
    echo "zfs_pool_size_bytes{pool=\"$n\"} $size"
    echo "zfs_pool_allocated_bytes{pool=\"$n\"} $alloc"
    echo "zfs_pool_free_bytes{pool=\"$n\"} $free"
    echo "zfs_pool_fragmentation_percent{pool=\"$n\"} ${frag//-/0}"
    # 1 = ONLINE; cualquier otro estado (DEGRADED, FAULTED, …) es 0 y lleva el estado en la etiqueta
    echo "zfs_pool_healthy{pool=\"$n\",health=\"$health\"} $([ "$health" = ONLINE ] && echo 1 || echo 0)"
  done
  zpool status -p | awk '
    /^ *pool:/ {p=$2}
    /errors:/ && !/No known data errors/ {e[p]=1}
    /^ *pool:/ {e[p]+=0}
    END {for (p in e) printf "zfs_pool_data_errors{pool=\"%s\"} %d\n", p, e[p]}'

  echo "# HELP zfs_dataset_used_bytes Uso, disponible y quota de los datasets (sin zvols de VMs)."
  echo "# TYPE zfs_dataset_used_bytes gauge"
  zfs list -Hp -t filesystem -d 2 -o name,used,avail,quota | while read -r n used avail quota; do
    echo "zfs_dataset_used_bytes{dataset=\"$n\"} $used"
    echo "zfs_dataset_available_bytes{dataset=\"$n\"} $avail"
    [ "$quota" != 0 ] && echo "zfs_dataset_quota_bytes{dataset=\"$n\"} $quota"
  done

  echo "# HELP smart_healthy Resultado del autodiagnóstico SMART (1 = PASSED)."
  echo "# TYPE smart_healthy gauge"
  smartctl --scan | awk '{print $1}' | while read -r dev; do
    j=$(smartctl -n standby -j -a "$dev" 2>/dev/null)
    d=${dev#/dev/}
    if [ "$(jq -r '.smart_status.passed // "standby"' <<<"$j")" = standby ]; then
      echo "smart_standby{device=\"$d\"} 1"
      continue
    fi
    jq -r --arg d "$d" '
      def m(n; v): if v == null then empty else "\(n){device=\"\($d)\"} \(v)" end;
      "smart_info{device=\"\($d)\",model=\"\(.model_name)\",serial=\"\(.serial_number)\"} 1",
      m("smart_standby"; 0),
      m("smart_healthy"; if .smart_status.passed then 1 else 0 end),
      m("smart_temperature_celsius"; .temperature.current),
      m("smart_power_on_hours"; .power_on_time.hours),
      (.ata_smart_attributes.table[]? | select(.id == 5 or .id == 197 or .id == 198 or .id == 199)
        | "smart_ata_attribute_raw{device=\"\($d)\",id=\"\(.id)\",name=\"\(.name)\"} \(.raw.value)"),
      m("smart_nvme_percentage_used"; .nvme_smart_health_information_log.percentage_used),
      m("smart_nvme_available_spare_percent"; .nvme_smart_health_information_log.available_spare),
      m("smart_nvme_media_errors"; .nvme_smart_health_information_log.media_errors)
    ' <<<"$j"
  done

  echo "textfile_metrics_last_run_timestamp_seconds $(date +%s)"
} > "$tmp"

if [ "$out" = - ]; then cat "$tmp"; exit 0; fi
chmod 644 "$tmp"
mv "$tmp" "$out"
