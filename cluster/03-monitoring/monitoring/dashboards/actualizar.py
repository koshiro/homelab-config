#!/usr/bin/env python3
"""Descarga los dashboards de grafana.com y los deja listos para el provisioning de Grafana.

Uso: python3 cluster/03-monitoring/monitoring/dashboards/actualizar.py
(El dashboard propio «Homelab — resumen» se genera aparte con resumen.py.)
Luego revisar el diff y abrir un PR: al mergear, Flux aplica los ConfigMaps (Kustomization monitoring).

- ${DS_PROMETHEUS} → uid fijo "victoriametrics" (grafana-provisioning/datasources.yml).
- Minificados y sin campos de la UI: cada ConfigMap debe quedar bajo los 256 KiB de la anotación
  last-applied de kubectl apply (Node Exporter Full queda en ~207 KiB).
- Un dashboard nuevo: añadirlo aquí, en el configMapGenerator de kustomization.yml y en el
  volumen proyectado de su carpeta en grafana.yml.
"""
import json
import re
import urllib.request
from pathlib import Path

DIR = Path(__file__).resolve().parent
DASH = {
    # id grafana.com: (archivo, refresh)
    1860: ("cluster/node-exporter-full.json", "15s"),
    15757: ("cluster/k8s-global.json", "15s"),
    15758: ("cluster/k8s-namespaces.json", "30s"),
    15759: ("cluster/k8s-nodes.json", "15s"),
    15760: ("cluster/k8s-pods.json", "15s"),
    10347: ("infra/proxmox.json", "1m"),
    13665: ("infra/speedtest.json", None),
    10229: ("infra/victoriametrics.json", "1m"),
}


def strip(o):
    """Quita campos que la UI rellena sola y no cambian el render."""
    if isinstance(o, dict):
        o.pop("editorMode", None)
        o.pop("pluginVersion", None)
        if o.get("hideFrom") == {"legend": False, "tooltip": False, "viz": False}:
            o.pop("hideFrom")
        for v in o.values():
            strip(v)
    elif isinstance(o, list):
        for v in o:
            strip(v)


for gid, (name, refresh) in DASH.items():
    url = f"https://grafana.com/api/dashboards/{gid}/revisions/latest/download"
    raw = urllib.request.urlopen(url, timeout=30).read().decode()
    raw = re.sub(r"\$\{DS_[A-Z_]+\}", "victoriametrics", raw)
    d = json.loads(raw)
    for k in ("__inputs", "__requires", "__elements"):
        d.pop(k, None)
    strip(d)
    d["id"] = None
    d["uid"] = f"gnet-{gid}"
    if refresh:
        d["refresh"] = refresh
    js = json.dumps(d, separators=(",", ":"), ensure_ascii=False)
    (DIR / name).write_text(js + "\n")
    print(f"{name}: {len(js) // 1024} KiB")
