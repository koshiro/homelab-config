#!/usr/bin/env python3
"""Genera cluster/resumen.json: «Homelab — resumen», una pantalla con el estado de todo.

Uso: python3 cluster/03-monitoring/monitoring/dashboards/resumen.py
Es el home de Grafana. Editarlo aquí (no en la UI) y volver a generar.
"""
import json
from pathlib import Path

DS = {"type": "prometheus", "uid": "victoriametrics"}
panels = []
pid = 0


def panel(kind, title, targets, x, y, w, h, unit=None, **extra):
    global pid
    pid += 1
    p = {
        "id": pid,
        "type": kind,
        "title": title,
        "datasource": DS,
        "gridPos": {"x": x, "y": y, "w": w, "h": h},
        "targets": [
            {"refId": chr(65 + i), "datasource": DS, "expr": e, "legendFormat": lf, "instant": kind != "timeseries"}
            for i, (e, lf) in enumerate(targets)
        ],
        "fieldConfig": {"defaults": {"unit": unit} if unit else {}, "overrides": []},
        "options": {},
    }
    for k, v in extra.items():
        if k == "defaults":
            p["fieldConfig"]["defaults"].update(v)
        else:
            p["options"].update(v) if k == "options" else p.update({k: v})
    panels.append(p)


def th(*steps):
    """Umbrales de estado: (valor, color) en orden ascendente; el primero es la base."""
    return {"mode": "absolute", "steps": [{"value": v, "color": c} for v, c in steps]}


GOOD, WARN, CRIT = "green", "orange", "red"
stat = {"reduceOptions": {"calcs": ["lastNotNull"]}, "colorMode": "background", "graphMode": "none", "textMode": "value_and_name"}
line = {"defaults": {"custom": {"lineWidth": 2, "fillOpacity": 0, "showPoints": "never"}, "min": 0}}
legend = {"legend": {"displayMode": "table", "placement": "right", "calcs": ["lastNotNull", "max"]}, "tooltip": {"mode": "multi", "sort": "desc"}}
bars = {"reduceOptions": {"calcs": ["lastNotNull"]}, "displayMode": "basic", "orientation": "horizontal", "showUnfilled": True, "minVizHeight": 14, "maxVizHeight": 22}

# Fila 1: titulares
panel("stat", "Nodos arriba", [('sum(up{job=~"node-exporter|pve-host"})', "")], 0, 0, 4, 4,
      options=stat, defaults={"thresholds": th((None, CRIT), (5, GOOD)), "decimals": 0, "noValue": "0"},
      description="De 5: pibot, k3s-node-1..3 y el host Proxmox.")
panel("stat", "Alertas activas", [('count(ALERTS{alertstate="firing"}) or vector(0)', "")], 4, 0, 4, 4,
      options=stat, defaults={"thresholds": th((None, GOOD), (1, WARN)), "decimals": 0},
      links=[{"title": "Detalle en Alerting", "url": "/alerting/list"}])
panel("stat", "Pools ZFS sanos", [('sum(zfs_pool_healthy)', "")], 8, 0, 4, 4,
      options=stat, defaults={"thresholds": th((None, CRIT), (3, GOOD)), "decimals": 0},
      description="De 3: nvme, respaldo, homelab-storage.")
panel("stat", "Pods sin correr", [('sum(kube_pod_status_phase{phase=~"Pending|Failed|Unknown"})', "")], 12, 0, 4, 4,
      options=stat, defaults={"thresholds": th((None, GOOD), (1, WARN)), "decimals": 0})
panel("stat", "pibot", [('max(node_thermal_zone_temp{instance="pibot"})', "")], 16, 0, 4, 4, unit="celsius",
      options=stat, defaults={"thresholds": th((None, GOOD), (70, WARN), (80, CRIT)), "decimals": 1},
      description="Temperatura de la Raspberry master (throttling desde 80 °C).")
panel("stat", "Internet (bajada)", [('last_over_time(speedtest_download_bits_per_second[2h])', "")], 20, 0, 4, 4, unit="bps",
      options=stat, defaults={"thresholds": th((None, CRIT), (50e6, WARN), (200e6, GOOD)), "decimals": 0},
      description="Último speedtest (1 por hora).")

# Fila 2: CPU y RAM por máquina
panel("timeseries", "CPU por máquina", [('100 * (1 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[$__rate_interval])))', "{{instance}}")],
      0, 4, 12, 8, unit="percent", options=legend, defaults={**line["defaults"], "max": 100})
panel("timeseries", "RAM usada por máquina", [('100 * (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)', "{{instance}}")],
      12, 4, 12, 8, unit="percent", options=legend, defaults={**line["defaults"], "max": 100})

# Fila 3: almacenamiento
panel("bargauge", "Uso de pools ZFS", [('100 * zfs_pool_allocated_bytes / zfs_pool_size_bytes', "{{pool}}")], 0, 12, 8, 7,
      unit="percent", options=bars, defaults={"min": 0, "max": 100, "thresholds": th((None, GOOD), (80, WARN), (90, CRIT))})
panel("bargauge", "Datasets con quota", [('100 * zfs_dataset_used_bytes / on (dataset) zfs_dataset_quota_bytes', "{{dataset}}")], 8, 12, 8, 7,
      unit="percent", options=bars, defaults={"min": 0, "max": 100, "thresholds": th((None, GOOD), (75, WARN), (90, CRIT))})
panel("bargauge", "Temperatura de discos", [('smart_temperature_celsius * on (device) group_left (model) smart_info', "{{device}} · {{model}}")], 16, 12, 8, 7,
      unit="celsius", options=bars, defaults={"min": 20, "max": 75, "thresholds": th((None, GOOD), (50, WARN), (65, CRIT))})

# Fila 4: quién consume
panel("bargauge", "Top 10 pods por CPU", [('topk(10, sum by (namespace, pod) (rate(container_cpu_usage_seconds_total{container!=""}[5m])))', "{{namespace}}/{{pod}}")],
      0, 19, 12, 9, unit="suffix: núcleos", options=bars, defaults={"min": 0, "decimals": 2, "color": {"mode": "fixed", "fixedColor": "blue"}})
panel("bargauge", "Top 10 pods por RAM", [('topk(10, sum by (namespace, pod) (container_memory_working_set_bytes{container!=""}))', "{{namespace}}/{{pod}}")],
      12, 19, 12, 9, unit="bytes", options=bars, defaults={"min": 0, "color": {"mode": "fixed", "fixedColor": "blue"}})

# Fila 5: red
panel("timeseries", "Red del host Proxmox (vmbr0)", [
    ('rate(node_network_receive_bytes_total{instance="pve",device="vmbr0"}[$__rate_interval]) * 8', "entrada"),
    ('rate(node_network_transmit_bytes_total{instance="pve",device="vmbr0"}[$__rate_interval]) * 8', "salida")],
    0, 28, 12, 8, unit="bps", options=legend, defaults=line["defaults"])
panel("timeseries", "Speedtest", [
    ('speedtest_download_bits_per_second', "bajada"),
    ('speedtest_upload_bits_per_second', "subida")],
    12, 28, 12, 8, unit="bps", options=legend,
    defaults={"custom": {"lineWidth": 2, "fillOpacity": 0, "showPoints": "always", "pointSize": 8, "spanNulls": 7200000}, "min": 0})

dash = {
    "uid": "homelab-resumen",
    "title": "Homelab — resumen",
    "tags": ["homelab"],
    "timezone": "browser",
    "refresh": "15s",
    "time": {"from": "now-6h", "to": "now"},
    "schemaVersion": 39,
    "editable": True,
    "graphTooltip": 1,
    "links": [
        {"title": "Kubernetes", "type": "dashboards", "tags": [], "asDropdown": True, "includeVars": False, "keepTime": True},
    ],
    "panels": panels,
}
out = Path(__file__).resolve().parent / "cluster" / "resumen.json"
out.write_text(json.dumps(dash, ensure_ascii=False, indent=1) + "\n")
print(f"{out.name}: {len(panels)} paneles")
