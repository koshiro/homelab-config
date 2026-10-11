#!/usr/bin/env python3
"""CLI compacto para la suite arr + qBittorrent del cluster (ver SKILL.md).

Todo va por `kubectl exec`: las API keys se leen dentro de cada pod (config.xml) y qBittorrent
responde sin login en localhost, así que no hace falta sops, port-forward ni secretos locales.
Las acciones que borran o reinician son dry-run salvo que se pase --apply.
"""
import argparse, calendar, html, json, re, subprocess, sys, time
from collections import Counter

ARRS = {"sonarr": (8989, "v3"), "radarr": (7878, "v3"), "prowlarr": (9696, "v1")}
NAMESPACES = ["sonarr", "radarr", "prowlarr", "bazarr", "qbittorrent", "flaresolverr", "plex", "overseerr"]
# Recreate o streaming: reiniciarlos corta descargas o reproducciones.
DISRUPTIVOS = {"qbittorrent", "plex"}
ARR_SH = r'''K=$(sed -n "s:.*<ApiKey>\(.*\)</ApiKey>.*:\1:p" /config/config.xml)
if [ "$3" = 1 ]; then B="--data-binary @-"; else B=""; fi
curl -sS -X "$1" -H "X-Api-Key: $K" -H "Content-Type: application/json" $B -w "\n%{http_code}" "http://localhost:$4/api/$5/$2"'''


TRANSITORIO = re.compile(r"connection reset|i/o timeout|EOF|TLS handshake|connection refused", re.I)


def sh(cmd, inp=None, check=True, reintentos=0):
    """reintentos solo para lecturas: el enlace Tailscale al API server se corta a veces."""
    for i in range(reintentos + 1):
        r = subprocess.run(cmd, input=inp, capture_output=True, text=True)
        if not (r.returncode and TRANSITORIO.search(r.stderr)) or i == reintentos:
            break
        time.sleep(3)
    if check and r.returncode:
        sys.exit(f"ERROR {' '.join(cmd[:6])}…: {r.stderr.strip()[:400]}")
    return r.stdout


def arr(app, path, method="GET", body=None):
    port, ver = ARRS[app]
    data = json.dumps(body) if body is not None and not isinstance(body, str) else body
    out = sh(["kubectl", "exec", "-i", "-n", app, f"deploy/{app}", "-c", app, "--", "sh", "-c", ARR_SH, "_",
              method, path.lstrip("/"), "1" if data else "0", str(port), ver], inp=data or "",
             reintentos=2 if method == "GET" else 0)
    txt, _, code = out.rpartition("\n")
    if not code.startswith("2"):
        sys.exit(f"ERROR {app} {method} {path}: HTTP {code} {txt[:300]}")
    return json.loads(txt) if txt.strip() else None


def qb(path, form=None):
    """API v2 de qBittorrent desde su propio pod (localhost sin auth). form → POST."""
    cmd = ["kubectl", "exec", "-i", "-n", "qbittorrent", "deploy/qbittorrent", "-c", "qbittorrent", "--",
           "curl", "-sS", "-w", "\n%{http_code}", f"http://localhost:8080/api/v2/{path.lstrip('/')}"]
    if form is not None:
        cmd[-1:-1] = ["--data-binary", "@-"]
    out = sh(cmd, inp=form or "", reintentos=2 if form is None else 0)
    txt, _, code = out.rpartition("\n")
    if not code.startswith("2"):
        sys.exit(f"ERROR qbittorrent {path}: HTTP {code} {txt[:300]}")
    try:
        return json.loads(txt)
    except ValueError:
        return txt


def gb(n): return f"{n / 1e9:.1f}G"
def horas(ts): return (time.time() - ts) / 3600
def cut(s, n=60): return s if len(s) <= n else s[: n - 1] + "…"
def utc(s): return calendar.timegm(time.strptime(s[:19], "%Y-%m-%dT%H:%M:%S"))
def nombre(t, n=60): return cut(html.unescape(t["name"]), n)


def colas():
    """{hash_minúsculas: [(arr, item)]} de las colas de Sonarr y Radarr."""
    res = {}
    for app, unk in (("sonarr", "includeUnknownSeriesItems"), ("radarr", "includeUnknownMovieItems")):
        for it in arr(app, f"queue?pageSize=2000&{unk}=true")["records"]:
            if it.get("downloadId"):
                res.setdefault(it["downloadId"].lower(), []).append((app, it))
    return res


# ---------------------------------------------------------------- comandos

def c_status(a):
    print("PODS (ns fase reinicios edad nodo)")
    for p in json.loads(sh(["kubectl", "get", "pods", "-A", "-o", "json"]))["items"]:
        m, st = p["metadata"], p["status"]
        if m["namespace"] not in NAMESPACES or st.get("phase") == "Succeeded":
            continue
        cs = st.get("containerStatuses", [])
        listo = all(c.get("ready") for c in cs)
        edad = horas(utc(st.get("startTime", m["creationTimestamp"])))
        print(f"  {m['namespace']:<13} {st.get('phase')}{'' if listo else '/NO-READY'} "
              f"r={sum(c.get('restartCount', 0) for c in cs)} {edad:.0f}h {p['spec'].get('nodeName')}")
    print("VERSIONES / SALUD")
    for app in ARRS:
        v = arr(app, "system/status")["version"]
        upd = arr(app, "update") or []
        nueva = next((u["version"] for u in upd if u.get("latest") and not u.get("installed")), None)
        salud = arr(app, "health")
        print(f"  {app} {v}" + (f" → {nueva} disponible" if nueva else " (última)"))
        for h in salud:
            print(f"    {h['type']}: {cut(h['message'], 110)}")
    t = qb("transfer/info")
    ts = qb("torrents/info")
    print(f"  qbittorrent {qb('app/version')} {t['connection_status']} dht={t['dht_nodes']} "
          f"↓{t['dl_info_speed'] / 1e6:.1f}MB/s ↑{t['up_info_speed'] / 1e3:.0f}kB/s")
    print("  torrents:", len(ts), dict(Counter(x["state"] for x in ts).most_common()))
    df = sh(["kubectl", "exec", "-n", "qbittorrent", "deploy/qbittorrent", "-c", "qbittorrent", "--",
             "df", "-h", "/data", "/incomplete"]).splitlines()[1:]
    for l in df:
        f = l.split()
        print(f"  disco {f[-1]}: {f[2]}/{f[1]} ({f[4]})")
    job = sh(["kubectl", "get", "jobs", "-n", "qbittorrent", "--sort-by=.metadata.creationTimestamp",
              "--no-headers"], check=False).splitlines()
    if job:
        print("  último filtro:", " ".join(job[-1].split()[:3]))


def c_torrents(a):
    ts = qb("torrents/info")
    rx = re.compile(a.state) if a.state else None
    sel = [t for t in ts if (not rx or rx.search(t["state"])) and a.min_age <= horas(t["added_on"]) <= a.max_age
           and (not a.name or a.name.lower() in t["name"].lower())]
    sel.sort(key=lambda t: -horas(t["added_on"]))
    print(f"{len(sel)}/{len(ts)} — estado edad% prog seeds tamaño cat hash nombre")
    for t in sel[: a.limit]:
        print(f"{t['state']:<11} {horas(t['added_on']):5.0f}h {t['progress'] * 100:3.0f}% {t['num_seeds']:>3} "
              f"{gb(t['size']):>6} {t['category'] or '-':<9} {t['hash'][:10]} {nombre(t, a.width)}")


def importados():
    """Hashes (minúsculas) con evento downloadFolderImported en Sonarr o Radarr."""
    res = set()
    for app in ("sonarr", "radarr"):
        for h in arr(app, "history?pageSize=10000&eventType=3&sortKey=date&sortDirection=descending")["records"]:
            if h.get("downloadId"):
                res.add(h["downloadId"].lower())
    return res


QB_LOGS = "/config/qBittorrent/logs"  # rotan cada pocos minutos por los "Performance alert"


def diagnostico_movimientos():
    """qBittorrent mueve de a un torrent (FIFO). Si el job de cabeza no termina, la cola entera se traba."""
    out = sh(["kubectl", "exec", "-n", "qbittorrent", "deploy/qbittorrent", "-c", "qbittorrent", "--", "sh", "-c",
              f"cd {QB_LOGS} && cat $(ls -tr) | grep -E 'started\\. Process|Enqueued torrent move|Moved torrent|"
              "move canceled|Failed to move'; grep ' /incomplete ' /proc/mounts"], check=False).splitlines()
    montaje = next((l for l in out if " /incomplete " in l), "")
    if "vers=4.2" in montaje:
        print("  AVISO /incomplete montado con NFS 4.2: los movimientos a /data se cuelgan (COPY sin CB_OFFLOAD). "
              "Ver hechos.md; el PV qbittorrent-scratch-pv debe ir con nfsvers=4.1")
    out = [l for l in out if l is not montaje]
    ultimo_ok = next((l for l in reversed(out) if "Moved torrent" in l or "started. Process" in l), None)
    pendientes = out[out.index(ultimo_ok) + 1:] if ultimo_ok else out
    encolados = [l for l in pendientes if "Enqueued" in l]
    if ultimo_ok:
        mins = (time.time() - utc(ultimo_ok[4:23])) / 60  # el pod usa TZ=Etc/UTC
        print(f"último movimiento terminado (o arranque) hace {mins:.0f} min; encolados desde entonces: {len(encolados)}")
        if encolados and mins > 30:
            cabeza = re.search(r'Torrent: "([^"]+)"', encolados[0])
            print(f"  AVISO cola de movimientos trabada; cabeza: {cabeza.group(1) if cabeza else '?'}. "
                  "setLocation no sirve (\"currently moving\"): `update qbittorrent --apply` los reencola al arrancar")


def c_unimported(a):
    """Torrents al 100 % que el *arr no importó: moviéndose, con aviso en la cola o huérfanos."""
    cola, imp = colas(), importados()
    grupos = {}
    for t in qb("torrents/info"):
        if t["progress"] < 1:
            continue
        h = t["hash"].lower()
        items = cola.get(h, [])
        if t["state"] == "moving":
            g = "moving (qBittorrent copiando a save_path; el *arr espera)"
        elif items:
            it = items[0][1]
            g = f"en cola {items[0][0]}: {it.get('trackedDownloadState')}/{it.get('trackedDownloadStatus')}"
        elif h not in imp:
            g = "fuera de cola y sin import en el historial"
        else:
            continue
        grupos.setdefault(g, []).append((t, items))
    if not grupos:
        print("todo lo completo está importado")
    if any(g.startswith("moving") for g in grupos):
        diagnostico_movimientos()
    for g, lst in grupos.items():
        print(f"{g}: {len(lst)}")
        for t, items in lst[: a.limit]:
            msgs = [m for s in (items[0][1].get("statusMessages", []) if items else []) for m in s.get("messages", [])]
            ruta = t.get("content_path", "")
            print(f"  {horas(t['added_on']):4.0f}h {gb(t['size']):>6} {t['category'] or '-':<9} {nombre(t, a.width)}"
                  + (f"\n      {cut(ruta, 90)}" if a.paths else "")
                  + (f"\n      — {cut(msgs[0], 110)}" if msgs else ""))


def c_queue(a):
    for app in a.apps:
        unk = "includeUnknownSeriesItems" if app == "sonarr" else "includeUnknownMovieItems"
        rec = arr(app, f"queue?pageSize=2000&{unk}=true")["records"]
        print(f"{app}: {len(rec)} en cola", dict(Counter(r.get("trackedDownloadState", "?") for r in rec)))
        for r in rec:
            malo = r.get("trackedDownloadStatus") != "ok" or r.get("trackedDownloadState") not in ("downloading",)
            if a.all or malo:
                msgs = [m for s in r.get("statusMessages", []) for m in s.get("messages", [])]
                print(f"  {r['id']} {r.get('trackedDownloadState')}/{r.get('trackedDownloadStatus')} "
                      f"{cut(r['title'], 55)} [{(r.get('indexer') or '').replace(' (Prowlarr)', '')}]"
                      + (f" — {cut(msgs[0], 80)}" if msgs else ""))


def quitar_de_cola(app, ids, blocklist=True):
    q = f"queue/bulk?removeFromClient=true&blocklist={str(blocklist).lower()}&skipRedownload=false"
    arr(app, q, "DELETE", {"ids": ids})


def c_stuck(a):
    """Torrents atascados (metaDL/stalledDL…) más viejos que N h: se sacan vía su *arr con blocklist."""
    estados = set(a.states.split(","))
    ts = [t for t in qb("torrents/info") if t["state"] in estados and horas(t["added_on"]) >= a.hours]
    cola = colas()
    por_arr, huerfanos = {}, []
    for t in ts:
        items = cola.get(t["hash"].lower())
        if items:
            for app, it in items:
                por_arr.setdefault(app, []).append(it["id"])
        else:
            huerfanos.append(t)
        idx = (items[0][1].get("indexer") or "").replace(" (Prowlarr)", "") if items else "SIN *arr"
        print(f"{t['state']:<9} {horas(t['added_on']):5.0f}h {t['num_seeds']:>2}s {idx:<15} {nombre(t, a.width)}")
    print(f"→ {len(ts)} atascados; en cola *arr: { {k: len(v) for k, v in por_arr.items()} }; huérfanos: {len(huerfanos)}")
    idxs = Counter((it[1].get("indexer") or "?") for t in ts for it in cola.get(t["hash"].lower(), []))
    if idxs:
        print("  por indexer:", dict(idxs.most_common()))
    if not a.apply:
        print("dry-run: --apply los quita del *arr con blocklist (busca otro release); "
              "--apply --orphans además borra los huérfanos de qBittorrent")
        return
    for app, ids in por_arr.items():
        quitar_de_cola(app, ids)
        print(f"  {app}: {len(ids)} quitados con blocklist")
    if a.orphans and huerfanos:
        qb("torrents/delete", f"hashes={'|'.join(t['hash'] for t in huerfanos)}&deleteFiles=true")
        print(f"  qbittorrent: {len(huerfanos)} huérfanos borrados")


def c_requeue(a):
    """Quita de la cola *arr (con blocklist) los ítems que matcheen indexer/título, y el *arr busca otro release."""
    rx_i = re.compile(a.indexer, re.I) if a.indexer else None
    rx_t = re.compile(a.title, re.I) if a.title else None
    if not (rx_i or rx_t):
        sys.exit("indicar --indexer y/o --title")
    for app, unk in (("sonarr", "includeUnknownSeriesItems"), ("radarr", "includeUnknownMovieItems")):
        rec = [r for r in arr(app, f"queue?pageSize=2000&{unk}=true")["records"]
               if (not rx_i or rx_i.search(r.get("indexer") or "")) and (not rx_t or rx_t.search(r["title"]))]
        for r in rec[: a.limit]:
            print(f"  {app} {r.get('trackedDownloadState')} {cut(html.unescape(r['title']), 60)} [{r.get('indexer')}]")
        if rec and a.apply:
            quitar_de_cola(app, [r["id"] for r in rec], blocklist=not a.no_blocklist)
        print(f"{app}: {len(rec)} {'quitados (búsqueda lanzada)' if a.apply else 'coinciden'}")
    if not a.apply:
        print("dry-run: --apply los quita (removeFromClient + blocklist) y el *arr busca otro; luego `wait-search`")


YA_IMPORTADO = re.compile(r"already imported|Not an upgrade|Existing file", re.I)
NUM_EP = r"(?:\b[Ss]\d{1,2}[Ee]|\s-\s)(\d{1,4})(?:v\d+)?\b"  # S03E07 o anime " - 07"; no el CRC


def c_manual(a):
    """Importación manual de lo bloqueado en la cola de Sonarr: propone, --apply importa, --clean quita lo ya importado.

    Sonarr propone serie/episodios por archivo. Si no reconoce la serie ("Unknown Series", típico en anime con
    título alternativo), --series/--season/--offset fijan el destino: episodio = número del archivo + offset.
    """
    rx = re.compile(a.title, re.I) if a.title else None
    rec = [r for r in arr("sonarr", "queue?pageSize=2000&includeUnknownSeriesItems=true")["records"]
           if r.get("trackedDownloadState") in ("importBlocked", "importPending", "importFailed")
           and (not rx or rx.search(r["title"]))]
    descargas = {}
    for r in rec:
        descargas.setdefault(r["downloadId"], []).append(r)
    serie, eps = None, {}
    if a.series:
        ss = [s for s in arr("sonarr", "series") if re.search(a.series, s["title"], re.I)]
        if len(ss) != 1:
            sys.exit(f"--series debe identificar una serie: {[s['title'] for s in ss]}")
        serie = ss[0]
        eps = {(e["seasonNumber"], e["episodeNumber"]): e for e in arr("sonarr", f"episode?seriesId={serie['id']}")}
    importar, limpiar, sin_destino = [], [], 0
    for did, items in descargas.items():
        print(f"{cut(items[0]['title'], 85)}")
        archivos = arr("sonarr", f"manualimport?downloadId={did}&filterExistingFiles=false")
        for f in archivos:
            rej = [x["reason"] for x in f.get("rejections", [])]
            sid = f.get("series", {}).get("id")
            ids = [e["id"] for e in f.get("episodes", [])]
            dest = f"S{f.get('seasonNumber')}E" + ",".join(str(e["episodeNumber"]) for e in f.get("episodes", []))
            if serie and (sid in (None, serie["id"])):
                m = re.findall(NUM_EP, f["relativePath"])
                e = eps.get((a.season, int(m[0]) + a.offset)) if m and a.season is not None else None
                if e:
                    sid, ids = serie["id"], [e["id"]]
                    dest = f"S{a.season}E{e['episodeNumber']} {cut(e.get('title') or '', 30)}"
                    rej = [x for x in rej if x not in ("Unknown Series",) and not x.startswith("Unable to")]
            if rej and all(YA_IMPORTADO.search(x) for x in rej):
                estado = "ya importado"
            elif sid and ids and not rej:
                estado = "importable"
                importar.append({"path": f["path"], "seriesId": sid, "episodeIds": ids, "quality": f["quality"],
                                 "languages": f.get("languages", []), "releaseGroup": f.get("releaseGroup"),
                                 "downloadId": did, "indexerFlags": f.get("indexerFlags", 0),
                                 "releaseType": f.get("releaseType", "unknown")})
            else:
                estado, sin_destino = "SIN DESTINO", sin_destino + 1
            print(f"  {estado:<12} {cut(f['relativePath'], 72):<72} → {dest if ids else '?'}"
                  + (f"  ({cut('; '.join(rej), 60)})" if rej and estado != "ya importado" else ""))
        if archivos and all(any(YA_IMPORTADO.search(x["reason"]) for x in f.get("rejections", [])) for f in archivos):
            limpiar.append(items)
    print(f"→ {len(importar)} importables, {len(limpiar)} descargas sin nada que importar, {sin_destino} sin destino")
    if sin_destino:
        print("  sin destino: fijarlo con --series RE --season N [--offset K] (episodio = número del archivo + K)")
    if a.apply and importar:
        cmd = arr("sonarr", "command", "POST", {"name": "ManualImport", "files": importar, "importMode": "auto"})
        print(f"  ManualImport lanzado (comando {cmd['id']}); revisar con `grabs --imported --minutes 10 -v`")
    if a.clean and limpiar:
        quitar_de_cola("sonarr", [r["id"] for items in limpiar for r in items], blocklist=True)
        print(f"  {len(limpiar)} descargas quitadas de cola y de qBittorrent con blocklist (la biblioteca queda intacta)")
    if not (a.apply or a.clean):
        print("dry-run: --apply importa lo importable; --clean quita (con blocklist) lo que no tiene nada que importar")


def c_wait_search(a):
    """Espera a que terminen los comandos de búsqueda de Sonarr/Radarr."""
    fin = time.time() + a.timeout
    while True:
        pend = {app: sum(1 for c in arr(app, "command") if "Search" in c["name"] and c["status"] in ("queued", "started"))
                for app in ("sonarr", "radarr")}
        if not any(pend.values()) or time.time() > fin:
            break
        time.sleep(15)
    print("búsquedas terminadas" if not any(pend.values()) else f"pendientes {pend}")


def c_grabs(a):
    """Releases tomados por los *arr en los últimos N minutos, por indexer."""
    desde = time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(time.time() - a.minutes * 60))
    ev, txt = (3, "importados") if a.imported else (1, "grabs")
    for app in ("sonarr", "radarr"):
        rec = [r for r in arr(app, f"history?pageSize=500&eventType={ev}&sortKey=date&sortDirection=descending")["records"]
               if r["date"] >= desde]
        print(f"{app}: {len(rec)} {txt} en {a.minutes} min",
              "" if a.imported else dict(Counter(r["data"].get("indexer") for r in rec)))
        if a.verbose:
            for r in rec:
                idx = r["data"].get("indexer")
                print(f"  {r['date'][11:16]} {cut(r['sourceTitle'], 70)}" + (f" [{idx}]" if idx else ""))


def c_imported(a):
    """Torrents completos, fuera de la cola de los *arr y ya importados (hardlink en la biblioteca)."""
    cola, imp = colas(), importados()
    ts = [t for t in qb("torrents/info") if t["progress"] >= 1 and t["hash"].lower() not in cola
          and t["hash"].lower() in imp]
    print(f"{len(ts)} torrents importados y fuera de cola, {gb(sum(t['size'] for t in ts))} en downloads/",
          dict(Counter(t["state"] for t in ts)))
    for t in ts[: a.limit]:
        print(f"  {t['state']:<10} {gb(t['size']):>6} {nombre(t, a.width)}")
    if not a.apply:
        print("dry-run: --apply los borra con deleteFiles=true (la biblioteca conserva su hardlink). "
              "Borrado masivo: confirmar con el usuario antes.")
        return
    for i in range(0, len(ts), 100):
        qb("torrents/delete", f"hashes={'|'.join(t['hash'] for t in ts[i:i + 100])}&deleteFiles=true")
    print(f"borrados {len(ts)}")


def c_prefs(a):
    p = qb("app/preferences")
    rx = re.compile(a.regex or r"^(max_active_\w+|max_ratio\w*|max_(inactive_)?seeding_time\w*|queueing_enabled|"
                    r"dont_count_slow_torrents|(dl|up)_limit|temp_path\w*|save_path|excluded_file_names_enabled|"
                    r"listen_port|bypass_auth_subnet_whitelist\w*)$")
    for k in sorted(p):
        if rx.search(k):
            print(f"{k}={json.dumps(p[k], ensure_ascii=False)}")


def c_profiles(a):
    app = a.app
    qp = arr(app, "qualityprofile")
    medias = arr(app, "movie" if app == "radarr" else "series")
    uso = Counter(m["qualityProfileId"] for m in medias)
    for p in qp:
        ok = [s["quality"]["name"] for it in p["items"] for s in (it.get("items") or [it]) if it["allowed"]]
        cf = [f"{f['name']}:{f['score']}" for f in p.get("formatItems", []) if f["score"]]
        print(f"{p['id']} «{p['name']}» usos={uso[p['id']]} upgrade={p['upgradeAllowed']} cutoff={p['cutoff']} "
              f"minCF={p.get('minFormatScore')}\n   {', '.join(ok)}" + (f"\n   CF {', '.join(cf)}" if cf else ""))
    ix = arr(app, "config/indexer")
    print(f"indexer: maximumSize={ix.get('maximumSize')}MB minimumAge={ix.get('minimumAge')} retention={ix.get('retention')}")
    if a.sizes:
        for d in arr(app, "qualitydefinition"):
            print(f"  {d['quality']['name']:<14} min={d['minSize']} pref={d.get('preferredSize')} max={d.get('maxSize')} MB/min")


def c_logs(a):
    pat = re.compile(a.grep or r"\b(warn|error|fatal|exception|fail)", re.I)
    out = sh(["kubectl", "logs", "-n", a.app, f"deploy/{a.app}", "-c", a.app, f"--since={a.since}"], check=False)
    vistos = Counter()
    for l in out.splitlines():
        if pat.search(l):
            clave = re.sub(r"\d+", "#", l)[-120:]
            vistos[clave] += 1
            if vistos[clave] == 1:
                print(cut(l.strip(), 200))
    rep = {k: v for k, v in vistos.items() if v > 1}
    if rep:
        print(f"({sum(rep.values())} líneas repetidas en {len(rep)} patrones omitidas)")


def c_update(a):
    apps = NAMESPACES if a.apps == ["all"] else a.apps
    antes = {app: arr(app, "system/status")["version"] for app in apps if app in ARRS}
    for app in apps:
        img = sh(["kubectl", "get", "deploy", "-n", app, app, "-o",
                  "jsonpath={.spec.template.spec.containers[0].image} {.spec.template.spec.containers[0].imagePullPolicy}"])
        aviso = " (corta descargas/streams)" if app in DISRUPTIVOS else ""
        print(f"{app}: {img} {antes.get(app, '')}{aviso}")
    if not a.apply:
        print("dry-run: --apply hace rollout restart (las imágenes :latest con pullPolicy Always bajan la nueva)")
        return
    for app in apps:
        sh(["kubectl", "rollout", "restart", "-n", app, f"deploy/{app}"])
    for app in apps:
        sh(["kubectl", "rollout", "status", "-n", app, f"deploy/{app}", "--timeout=600s"])
        print(f"{app}: listo" + (f" {antes[app]} → {arr(app, 'system/status')['version']}" if app in ARRS else ""))


def c_api(a):
    body = None
    if a.data:
        body = open(a.data[1:]).read() if a.data.startswith("@") else a.data
    r = arr(a.app, a.path, a.method, body)
    print(json.dumps(r, ensure_ascii=False, separators=(",", ":")))


def c_qb(a):
    r = qb(a.path, a.data)
    print(r if isinstance(r, str) else json.dumps(r, ensure_ascii=False, separators=(",", ":")))


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    s = p.add_subparsers(dest="cmd", required=True)
    s.add_parser("status", help="pods, versiones, salud, qBittorrent, discos").set_defaults(f=c_status)
    x = s.add_parser("torrents", help="lista compacta de torrents")
    x.add_argument("--state", help="regex de estado (metaDL|stalledDL…)")
    x.add_argument("--name", help="subcadena del nombre")
    x.add_argument("--min-age", type=float, default=0, help="horas desde que se agregó")
    x.add_argument("--max-age", type=float, default=1e9, help="horas desde que se agregó")
    x.add_argument("--limit", type=int, default=40); x.add_argument("--width", type=int, default=60)
    x.set_defaults(f=c_torrents)
    x = s.add_parser("queue", help="cola de sonarr/radarr (solo problemas salvo --all)")
    x.add_argument("apps", nargs="*", default=["sonarr", "radarr"]); x.add_argument("--all", action="store_true")
    x.set_defaults(f=c_queue)
    x = s.add_parser("stuck", help="torrents atascados → quitar vía *arr con blocklist")
    x.add_argument("--hours", type=float, default=2); x.add_argument("--states", default="metaDL,stalledDL")
    x.add_argument("--apply", action="store_true"); x.add_argument("--orphans", action="store_true")
    x.add_argument("--width", type=int, default=55)
    x.set_defaults(f=c_stuck)
    x = s.add_parser("unimported", help="torrents al 100 %% sin importar (moving, aviso en cola, huérfanos)")
    x.add_argument("--limit", type=int, default=20); x.add_argument("--width", type=int, default=60)
    x.add_argument("--paths", action="store_true", help="muestra content_path")
    x.set_defaults(f=c_unimported)
    x = s.add_parser("requeue", help="quitar de la cola *arr por indexer/título con blocklist → nueva búsqueda")
    x.add_argument("--indexer"); x.add_argument("--title"); x.add_argument("--apply", action="store_true")
    x.add_argument("--no-blocklist", action="store_true"); x.add_argument("--limit", type=int, default=30)
    x.set_defaults(f=c_requeue)
    x = s.add_parser("manual", help="importación manual de lo bloqueado en Sonarr (propone; --apply / --clean)")
    x.add_argument("--title", help="regex sobre el título del release")
    x.add_argument("--series", help="regex de la serie destino cuando Sonarr no la reconoce")
    x.add_argument("--season", type=int); x.add_argument("--offset", type=int, default=0)
    x.add_argument("--apply", action="store_true"); x.add_argument("--clean", action="store_true")
    x.set_defaults(f=c_manual)
    x = s.add_parser("wait-search", help="esperar a que terminen las búsquedas de los *arr")
    x.add_argument("--timeout", type=int, default=540); x.set_defaults(f=c_wait_search)
    x = s.add_parser("grabs", help="releases tomados en los últimos N min, por indexer")
    x.add_argument("--minutes", type=int, default=60); x.add_argument("-v", "--verbose", action="store_true")
    x.add_argument("--imported", action="store_true", help="importaciones en vez de grabs")
    x.set_defaults(f=c_grabs)
    x = s.add_parser("imported", help="torrents ya importados y fuera de cola → borrar")
    x.add_argument("--apply", action="store_true"); x.add_argument("--limit", type=int, default=15)
    x.add_argument("--width", type=int, default=70)
    x.set_defaults(f=c_imported)
    x = s.add_parser("prefs", help="preferencias de qBittorrent filtradas")
    x.add_argument("regex", nargs="?"); x.set_defaults(f=c_prefs)
    x = s.add_parser("profiles", help="perfiles de calidad, CF con puntaje y tope de tamaño")
    x.add_argument("app", choices=["sonarr", "radarr"]); x.add_argument("--sizes", action="store_true")
    x.set_defaults(f=c_profiles)
    x = s.add_parser("logs", help="warn/error deduplicados")
    x.add_argument("app", choices=NAMESPACES); x.add_argument("--since", default="6h"); x.add_argument("--grep")
    x.set_defaults(f=c_logs)
    x = s.add_parser("update", help="rollout restart para tomar la imagen nueva")
    x.add_argument("apps", nargs="+", help="apps o 'all'"); x.add_argument("--apply", action="store_true")
    x.set_defaults(f=c_update)
    x = s.add_parser("api", help="llamada cruda a un *arr (JSON compacto; pipear a jq)")
    x.add_argument("app", choices=list(ARRS)); x.add_argument("path")
    x.add_argument("-X", "--method", default="GET"); x.add_argument("-d", "--data", help="JSON o @archivo")
    x.set_defaults(f=c_api)
    x = s.add_parser("qb", help="llamada cruda a qBittorrent API v2 (-d form → POST)")
    x.add_argument("path"); x.add_argument("-d", "--data"); x.set_defaults(f=c_qb)
    a = p.parse_args()
    a.f(a)


if __name__ == "__main__":
    main()
