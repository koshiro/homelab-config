#!/usr/bin/env python3
"""CLI compacto del homelab (ver SKILL.md). Solo stdlib; salida de una línea por ítem.

Reemplaza las secuencias de orientación y los comandos que más fallaban entre sesiones: estado del cluster,
NodePorts libres, resumen de una app, ssh con nombres que resuelven, SOPS sin olvidar la clave, esperas sin
`sleep`, secciones de documentos sin leerlos enteros y la API de Cloudflare con el token del vault.
Lo que escribe en Cloudflare es dry-run salvo --apply.
"""
import argparse, hashlib, json, os, re, shutil, subprocess, sys, time, urllib.error, urllib.parse, urllib.request
from collections import Counter
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]          # funciona también vía el symlink de ~/.claude/skills
VAULT = REPO / "ansible/vars/vault.yml"
VAULT_PASS = Path.home() / ".config/homelab/ansible-vault-pass"
AGE_KEY = Path.home() / ".config/sops/age/keys.txt"
CF_ACCOUNT = "84f8d7966bfc3d39812bebeeeed0cfa4"
# alias → destinos ssh en orden (LAN primero; si no hay LAN, tailnet)
HOSTS = {
    "pibot": ["daniel@k3s-node-0"], "k3s-node-0": ["daniel@k3s-node-0"],
    "pve": ["root@192.168.1.100", "root@pve"], "proxmox": ["root@192.168.1.100", "root@pve"],
    **{f"k3s-node-{i}": [f"daniel@192.168.1.13{i}", f"daniel@k3s-node-{i}-k3s"] for i in (1, 2, 3)},
    **{f"node-{i}": [f"daniel@192.168.1.13{i}", f"daniel@k3s-node-{i}-k3s"] for i in (1, 2, 3)},
}
TRANSITORIO = re.compile(r"TLS handshake|i/o timeout|connection reset|EOF|Unable to connect", re.I)


def sh(cmd, inp=None, check=True, reintentos=1, env=None):
    for i in range(reintentos + 1):
        r = subprocess.run(cmd, input=inp, capture_output=True, text=True, env=env)
        if not (r.returncode and TRANSITORIO.search(r.stderr)) or i == reintentos:
            break
        time.sleep(3)
    if check and r.returncode:
        sys.exit(f"ERROR {' '.join(cmd[:5])}…: {r.stderr.strip()[:400]}")
    return r.stdout


def kj(*args):
    return json.loads(sh(["kubectl", *args, "-o", "json", "--request-timeout=20s"]))


def gib(b):
    return f"{b / 2**30:.0f}G"


# ---------------------------------------------------------------- cluster
def cmd_status(a):
    nodes = kj("get", "nodes")["items"]
    for n in nodes:
        name = n["metadata"]["name"]
        cond = {c["type"]: c["status"] for c in n["status"]["conditions"]}
        bad = [t for t, s in cond.items() if t.endswith(("Pressure", "Unavailable")) and s == "True"]
        flags = ("" if cond.get("Ready") == "True" else " NOTREADY") + (" cordon" if n["spec"].get("unschedulable") else "")
        try:
            fs = json.loads(sh(["kubectl", "get", "--raw", f"/api/v1/nodes/{name}/proxy/stats/summary",
                                "--request-timeout=10s"], check=False) or "{}")["node"]["fs"]
            disco = f"disco {gib(fs['availableBytes'])} libres/{gib(fs['capacityBytes'])}"
        except (KeyError, ValueError):
            disco = "disco ?"
        print(f"{name:11} {n['status']['nodeInfo']['kubeletVersion']} {disco}{flags} {' '.join(bad)}")
    malos, jobs = [], Counter()
    for p in kj("get", "pods", "-A")["items"]:
        fase = p["status"].get("phase")
        cs = p["status"].get("containerStatuses") or []
        espera = [c["state"]["waiting"].get("reason", "") for c in cs if "waiting" in c.get("state", {})]
        noready = fase == "Running" and any(not c.get("ready") for c in cs)
        dueño = (p["metadata"].get("ownerReferences") or [{}])[0]
        if fase == "Failed" and dueño.get("kind") == "Job":    # ejecuciones viejas: se resumen por CronJob
            jobs[f"{p['metadata']['namespace']}/{re.sub(r'-[0-9]+$', '', dueño['name'])}"] += 1
            continue
        if fase not in ("Running", "Succeeded") or espera or noready:
            rs = sum(c.get("restartCount", 0) for c in cs)
            malos.append(f"  {p['metadata']['namespace']}/{p['metadata']['name']} {fase} {','.join(espera) or ('noready' if noready else '')} "
                         f"r={rs} {p['spec'].get('nodeName', '-')}")
    print(f"pods con problema: {len(malos)}", *malos, sep="\n")
    if jobs:
        print("jobs fallidos (pods retenidos):", ", ".join(f"{k}×{v}" for k, v in jobs.most_common()))
    if a.deep:
        print("pibot throttled:", ssh_run("pibot", "vcgencmd get_throttled", quiet=True).strip())
        print("pve:", ssh_run("pve", "uptime | sed 's/.*load/load/'; free -g | awk '/Mem/{print \"RAM libre \" $7 \"G\"}'; "
                              "zpool list -H -o name,cap,health | tr '\\t' ' '", quiet=True).strip().replace("\n", " | "))


def nodeports():
    usados = {}
    for s in kj("get", "svc", "-A")["items"]:
        for p in s["spec"].get("ports", []):
            if p.get("nodePort"):
                usados[p["nodePort"]] = f"{s['metadata']['namespace']}/{s['metadata']['name']}"
    return usados


def cmd_ports(a):
    usados = nodeports()
    if a.serie:
        base = int(a.serie)
        libre = next(p for p in range(base, base + 100) if p not in usados)
        print(f"siguiente libre desde {base}: {libre}")
        return
    for p in sorted(usados):
        print(p, usados[p])


def cmd_app(a):
    ns = a.ns
    pods = kj("get", "pods", "-n", ns)["items"]
    for p in pods:
        cs = p["status"].get("containerStatuses") or []
        imgs = ",".join(sorted({c["image"].split("/")[-1] for c in cs}))
        print(f"pod {p['metadata']['name']} {p['status'].get('phase')} r={sum(c.get('restartCount', 0) for c in cs)} "
              f"{p['spec'].get('nodeName', '-')} {imgs}")
    for s in kj("get", "svc", "-n", ns)["items"]:
        ports = ",".join(f"{p['port']}" + (f"→np{p['nodePort']}" if p.get("nodePort") else "") for p in s["spec"].get("ports", []))
        print(f"svc {s['metadata']['name']} {s['spec']['type']} {ports}")
    for i in kj("get", "ingress", "-n", ns)["items"]:
        print("ingress", " ".join(r.get("host", "*") for r in i["spec"].get("rules", [])))
    for v in kj("get", "pvc", "-n", ns)["items"]:
        print(f"pvc {v['metadata']['name']} {v['spec'].get('storageClassName') or '(static)'} {v['spec'].get('volumeName', '')} "
              f"{v['status'].get('phase')}")
    for c in kj("get", "cronjobs", "-n", ns)["items"]:
        print(f"cronjob {c['metadata']['name']} '{c['spec']['schedule']}' último={c['status'].get('lastSuccessfulTime', '-')}")
    carpetas = [str(p.relative_to(REPO)) for p in (REPO / "cluster").glob("**/namespace.y*ml")
                if re.search(rf"^\s*name:\s*{re.escape(ns)}\s*$", p.read_text(), re.M)]
    print("repo:", " ".join(sorted({str(Path(c).parent) for c in carpetas})) or "(sin namespace.yml con ese nombre)")


def cmd_wait(a):
    """Reemplaza `sleep N; kubectl get …` (bloqueado): rollout status y, si falla, el motivo."""
    r = subprocess.run(["kubectl", "-n", a.ns, "rollout", "status", f"{a.kind}/{a.name}", f"--timeout={a.timeout}"],
                       capture_output=True, text=True)
    print((r.stdout or r.stderr).strip().splitlines()[-1] if (r.stdout or r.stderr).strip() else "")
    if r.returncode:
        print(sh(["kubectl", "-n", a.ns, "get", "pods", "-o", "wide", "--no-headers"], check=False))
        print(sh(["kubectl", "-n", a.ns, "logs", f"{a.kind}/{a.name}", "--tail=20", "--all-containers"], check=False)[-2000:])
        sys.exit(1)


def sha_main():
    """SHA de main en GitHub (ls-remote); si no hay red, el origin/main local."""
    for cmd in (["git", "ls-remote", "origin", "refs/heads/main"], ["git", "rev-parse", "origin/main"]):
        r = subprocess.run(cmd, cwd=REPO, capture_output=True, text=True, timeout=30)
        if r.returncode == 0 and r.stdout.strip():
            return r.stdout.split()[0]
    return ""


def cmd_flux(a):
    """Lo que dice si Flux está sano: fuente en el SHA de main, Kustomizations activas Ready en ese SHA y dónde corre."""
    main = sha_main()
    ready = lambda o: next((c for c in o.get("status", {}).get("conditions", []) if c["type"] == "Ready"), {})
    fuente = ""
    for g in kj("get", "gitrepositories", "-A")["items"]:
        rev = g.get("status", {}).get("artifact", {}).get("revision", "")
        fuente = fuente or rev.split(":")[-1]
        print(f"fuente {g['metadata']['name']} {rev} Ready={ready(g).get('status', '?')}"
              f"{'' if main and rev.endswith(main) else f'  ≠ main {main[:8]}'}")
    # Merge reciente: la fuente aún no trae main (polling de 5 min). Las ks Ready en la revisión de la fuente esperan,
    # no fallan; se cuentan aparte.
    atrasada = bool(main and fuente) and fuente != main
    susp, malas, esperan = [], 0, 0
    for k in kj("get", "kustomizations.kustomize.toolkit.fluxcd.io", "-A")["items"]:
        n = k["metadata"]["name"]
        if k["spec"].get("suspend"):
            susp.append(n)
            continue
        c, rev = ready(k), k.get("status", {}).get("lastAppliedRevision", "")
        en_main = bool(main) and rev.endswith(main)
        ok = c.get("status") == "True" and en_main
        # Una pasada en curso sobre una revisión ya aplicada (Unknown/Progressing, cada 10 min) no es un problema
        en_curso = c.get("status") == "Unknown" and c.get("reason") == "Progressing" and en_main
        espera = atrasada and c.get("status") == "True" and rev.endswith(fuente)
        malas += not (ok or en_curso or espera)
        esperan += espera
        print(f"ks {n} Ready={c.get('status', '?')} {rev.split(':')[-1][:8] or '-'}"
              + ("" if ok else "  (reconciliando)" if en_curso else "  (espera main)" if espera
                 else f"  {c.get('reason', '')}: {c.get('message', '')[:160]}"))
    print(f"suspendidas ({len(susp)}):", " ".join(susp) or "-")
    for h in kj("get", "helmreleases.helm.toolkit.fluxcd.io", "-A")["items"]:
        c = ready(h)
        print(f"helmrelease {h['metadata']['namespace']}/{h['metadata']['name']} Ready={c.get('status', '?')} "
              f"{h.get('status', {}).get('lastAttemptedRevision', '-')}  {c.get('message', '')[:120]}")
    pods = kj("get", "pods", "-n", "flux-system")["items"]
    print("pods:", " ".join(f"{p['metadata']['labels'].get('app', p['metadata']['name'])}@{p['spec'].get('nodeName', '-')}"
                            f"{'' if p['status'].get('phase') == 'Running' else '(' + p['status'].get('phase', '?') + ')'}"
                            for p in pods))
    print(f"activas con problema: {malas}" + ("  (pibot tiene pods de Flux)" if any(p["spec"].get("nodeName") == "pibot" for p in pods) else ""))
    if esperan:
        print(f"esperan main: {esperan} (fuente sin el último commit; $F reconcile ks flux-system --with-source)")
    sys.exit(1 if malas else 0)


def cmd_alertas(a):
    """Alertas activas de vmalert (pending/firing) por el proxy del apiserver, sin port-forward. Horas en UTC."""
    al = json.loads(sh(["kubectl", "get", "--raw", "/api/v1/namespaces/monitoring/services/vmalert:8880/proxy/api/v1/alerts",
                        "--request-timeout=20s"], reintentos=1))["data"]["alerts"]
    print(f"alertas activas: {len(al)}")
    for x in sorted(al, key=lambda x: (x.get("activeAt", ""), x["name"])):
        l = x.get("labels", {})
        extra = ",".join(f"{k}={l[k]}" for k in ("namespace", "pod", "deployment", "instance", "severity") if k in l)
        print(f"{x['state']:8} {x['name']} desde {x.get('activeAt', '?')} [{extra}]")


def promql(q, t=None):
    """Consulta instantánea a VictoriaMetrics por el proxy del apiserver; devuelve [(labels, valor)]."""
    qs = urllib.parse.urlencode({"query": q, **({"time": t} if t else {})})
    r = json.loads(sh(["kubectl", "get", "--raw", f"/api/v1/namespaces/monitoring/services/victoria-metrics:8428/proxy/api/v1/query?{qs}",
                       "--request-timeout=30s"], reintentos=1))["data"]["result"]
    return [(x["metric"], float(x["value"][1])) for x in r]


def cmd_io(a):
    """Máximo de los últimos --ventana (o hasta --en, ISO UTC) por disco y por nodo: latencia, uso, iowait y PSI io."""
    v, dev = a.ventana, 'device!~"dm-.*|loop.*|sr.*|zd.*"'
    def mx(expr):
        return f"max_over_time(({expr})[{v}:30s])"
    disco = {
        "esc_ms": f"rate(node_disk_write_time_seconds_total{{{dev}}}[1m]) / rate(node_disk_writes_completed_total{{{dev}}}[1m]) * 1000",
        "lec_ms": f"rate(node_disk_read_time_seconds_total{{{dev}}}[1m]) / rate(node_disk_reads_completed_total{{{dev}}}[1m]) * 1000",
        "uso%": f"rate(node_disk_io_time_seconds_total{{{dev}}}[1m]) * 100",
        "esc_MB/s": f"rate(node_disk_written_bytes_total{{{dev}}}[1m]) / 1e6",
    }
    nodo = {
        "iowait%": 'sum by (instance) (rate(node_cpu_seconds_total{mode="iowait"}[1m])) / count by (instance) (node_cpu_seconds_total{mode="idle"}) * 100',
        "psi_io_full%": "rate(node_pressure_io_stalled_seconds_total[1m]) * 100",
    }
    filas = {}
    for col, e in disco.items():
        for m, val in promql(mx(e), a.en):
            filas.setdefault(f"{m.get('instance', '?')}/{m.get('device', '?')}", {})[col] = val
    print(f"discos (máx. {v}{' hasta ' + a.en if a.en else ''}); esc_ms > 50 con poco MB/s = disco lento")
    for k in sorted(filas, key=lambda k: -filas[k].get("esc_ms", 0)):
        f = filas[k]
        if f.get("uso%", 0) < 1 and f.get("esc_MB/s", 0) < 0.1:
            continue
        print(f"  {k:24} " + " ".join(f"{c}={f[c]:.0f}" for c in disco if c in f))
    filas = {}
    for col, e in nodo.items():
        for m, val in promql(mx(e), a.en):
            filas.setdefault(m.get("instance", "?"), {})[col] = val
    print("nodos")
    for k in sorted(filas):
        print(f"  {k:24} " + " ".join(f"{c}={filas[k][c]:.0f}" for c in nodo if c in filas[k]))


def cmd_sops(a):
    env = {**os.environ, "SOPS_AGE_KEY_FILE": str(AGE_KEY)}
    # Sin «apply»: desde 2026-10-16 Flux descifra y aplica los *.sops.* (Component solo-flux) al mergear.
    if a.accion == "keys":           # nombres de claves, nunca valores
        out = sh(["sops", "-d", a.archivo], env=env)
        print("\n".join(re.findall(r"^\s+([A-Za-z0-9_.-]+):", out, re.M)))
    elif a.accion == "encrypt":      # cifra en el lugar un Secret en claro (data/stringData)
        sh(["sops", "--encrypt", "--in-place", "--age", "age1ga4dqzwv2wrf5c0dduz0vsjkzlda9xzrp787u2mnhhj6zh5qxaws4mlhhs",
            "--encrypted-regex", "^(data|stringData)$", a.archivo], env=env)
        print("cifrado:", a.archivo)


# ---------------------------------------------------------------- ssh
def ssh_run(alias, comando, quiet=False):
    destinos = HOSTS.get(alias, [alias])
    for d in destinos:
        r = subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=4", d, comando],
                           capture_output=True, text=True)
        if r.returncode != 255:
            if not quiet and d != destinos[0]:
                print(f"(vía {d})", file=sys.stderr)
            return r.stdout + r.stderr
    sys.exit(f"ERROR ssh {alias}: sin conexión por {', '.join(destinos)}")


def cmd_ssh(a):
    sys.stdout.write(ssh_run(a.host, " ".join(a.comando)))


# ---------------------------------------------------------------- documentos
def cmd_doc(a):
    """Imprime solo una sección (por número o texto del encabezado) en vez de leer el documento entero."""
    cands = [REPO / a.archivo, REPO / "docs" / a.archivo, REPO / "docs" / f"{a.archivo}.md", REPO / f"{a.archivo}.md",
             REPO / a.archivo / "README.md"]
    f = next((c for c in cands if c.is_file()), None) or sys.exit(f"no existe {a.archivo}")
    lineas = f.read_text().splitlines()
    heads = [(i, len(m.group(1)), m.group(2)) for i, l in enumerate(lineas) if (m := re.match(r"^(#+)\s+(.*)", l))]
    if not a.seccion:
        for i, n, t in heads:
            print(f"{i + 1:4} {'  ' * (n - 1)}{t}")
        return
    rx = re.compile(rf"^{re.escape(a.seccion)}[.\s]|{re.escape(a.seccion)}", re.I)
    for k, (i, n, t) in enumerate(heads):
        if rx.search(t):
            fin = next((j for j, m, _ in heads[k + 1:] if m <= n), len(lineas))
            print("\n".join(lineas[i:fin]))
            return
    sys.exit(f"sección no encontrada: {a.seccion} (sin argumento lista los encabezados)")


# ---------------------------------------------------------------- Cloudflare
def cf_token():
    """Token de cuenta del vault, en memoria (nunca impreso). Autorizado por el usuario para túneles/DNS/hostnames."""
    exe = shutil.which("ansible-vault") or sys.exit("falta ansible-vault")
    r = subprocess.run([exe, "view", str(VAULT), "--vault-password-file", str(VAULT_PASS)], stdin=subprocess.DEVNULL,
                       capture_output=True, text=True)
    m = re.search(r"^vault_cloudfare_full_api_token:\s*['\"]?([^'\"\s]+)", r.stdout, re.M)
    return m.group(1) if m else sys.exit(f"ERROR vault: {r.stderr.strip()[:300]}")


_TOKEN = None


def _cf_req(method, path, data=None, tipo="application/json", timeout=30):
    global _TOKEN
    _TOKEN = _TOKEN or cf_token()
    path = path.replace("{acc}", CF_ACCOUNT)
    req = urllib.request.Request(f"https://api.cloudflare.com/client/v4/{path.lstrip('/')}", method=method, data=data,
                                 headers={"Authorization": f"Bearer {_TOKEN}", "Content-Type": tipo})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.read()
    except urllib.error.HTTPError as e:
        sys.exit(f"ERROR cf {method} {path}: {e.code} {e.read().decode()[:400]}")


def cf(method, path, body=None):
    return json.loads(_cf_req(method, path, json.dumps(body).encode() if body is not None else None))


def cf_bytes(method, path, data=None):
    """Como cf() pero con cuerpo y respuesta binarios (objetos de R2)."""
    return _cf_req(method, path, data, "application/octet-stream", timeout=120)


def zona(host):
    zs = cf("GET", "zones?per_page=50")["result"]
    z = max((z for z in zs if host == z["name"] or host.endswith("." + z["name"])), key=lambda z: len(z["name"]), default=None)
    return z or sys.exit(f"sin zona para {host}: {[z['name'] for z in zs]}")


def tunel(nombre):
    t = cf("GET", f"accounts/{{acc}}/cfd_tunnel?is_deleted=false&name={nombre}")["result"]
    return t[0] if t else sys.exit(f"no existe el túnel {nombre}")


def cmd_cf(a):
    if a.accion == "api":
        body = None
        if a.data:
            body = json.load(open(a.data[1:])) if a.data.startswith("@") else json.loads(a.data)
        print(json.dumps(cf(a.args[0].upper(), a.args[1], body), ensure_ascii=False))
    elif a.accion == "zones":
        for z in cf("GET", "zones?per_page=50")["result"]:
            print(z["id"], z["name"], z["status"])
    elif a.accion == "tunnels":
        for t in cf("GET", "accounts/{acc}/cfd_tunnel?is_deleted=false")["result"]:
            print(t["id"], t["name"], t["status"], len(t.get("connections", [])), "conexiones")
    elif a.accion == "routes":
        t = tunel(a.args[0])
        for r in cf("GET", f"accounts/{{acc}}/cfd_tunnel/{t['id']}/configurations")["result"]["config"]["ingress"]:
            print(r.get("hostname", "*"), "→", r["service"])
    elif a.accion == "route":        # route <túnel> <host> <servicio>: regla en el túnel + CNAME proxied
        nombre, host, servicio = a.args
        t = tunel(nombre)
        url = f"accounts/{{acc}}/cfd_tunnel/{t['id']}/configurations"
        cfg = cf("GET", url)["result"]["config"]
        ing = [r for r in cfg["ingress"] if r.get("hostname") != host]
        ing.insert(len(ing) - 1 if ing and "hostname" not in ing[-1] else len(ing), {"hostname": host, "service": servicio})
        z = zona(host)
        dns = cf("GET", f"zones/{z['id']}/dns_records?name={host}")["result"]
        destino = f"{t['id']}.cfargotunnel.com"
        print(f"túnel {nombre}: {host} → {servicio}; DNS {host} CNAME {destino} (actual: "
              f"{[(d['type'], d['content']) for d in dns] or 'ninguno'})")
        if not a.apply:
            print("dry-run: repetir con --apply")
            return
        respaldo = Path(os.environ.get("CLAUDE_JOB_DIR", "/tmp")) / "tmp" / f"cf-{nombre}-{int(time.time())}.json"
        respaldo.parent.mkdir(parents=True, exist_ok=True)
        respaldo.write_text(json.dumps(cfg))
        cfg["ingress"] = ing
        cf("PUT", url, {"config": cfg})
        rec = {"type": "CNAME", "name": host, "content": destino, "proxied": True}
        if dns:
            cf("PUT", f"zones/{z['id']}/dns_records/{dns[0]['id']}", rec)
        else:
            cf("POST", f"zones/{z['id']}/dns_records", rec)
        print(f"aplicado (config anterior en {respaldo})")


def cmd_r2(a):
    """R2 por la API de cuenta (sin claves S3). Crear bucket y subir son dry-run salvo --apply."""
    b = "accounts/{acc}/r2/buckets"
    minimo, maximo = {"ls": (0, 1), "mb": (1, 1), "put": (2, 3), "get": (3, 3)}[a.accion]
    if not minimo <= len(a.args) <= maximo:
        sys.exit("uso: r2 ls [bucket] | mb <bucket> | put <bucket> <archivo> [clave] | get <bucket> <clave> <destino>")
    if a.accion == "ls" and not a.args:
        for x in cf("GET", b)["result"]["buckets"]:
            print(x["name"], x["creation_date"][:10])
    elif a.accion == "ls":           # pagina con el cursor hasta el final
        cursor = ""
        while True:
            r = cf("GET", f"{b}/{a.args[0]}/objects?per_page=1000" + (f"&cursor={urllib.parse.quote(cursor)}" if cursor else ""))
            res = r["result"]
            for o in res if isinstance(res, list) else res.get("objects", []):
                print(o["key"], o["size"], "B", o.get("last_modified", "")[:19])
            info = r.get("result_info") or {}
            cursor = info.get("cursor") or ""
            if not (info.get("is_truncated") and cursor):
                break
    elif a.accion == "mb":
        print(f"crear bucket {a.args[0]}")
        if not a.apply:
            print("dry-run: repetir con --apply")
            return
        cf("POST", b, {"name": a.args[0]})
        print("creado")
    elif a.accion == "put":          # put <bucket> <archivo> [clave]
        bucket, archivo = a.args[0], Path(a.args[1])
        clave = a.args[2] if len(a.args) > 2 else archivo.name
        if not archivo.is_file():
            sys.exit(f"no existe {archivo}")
        datos = archivo.read_bytes()
        print(f"{archivo} ({len(datos)} B, sha256 {hashlib.sha256(datos).hexdigest()}) → r2://{bucket}/{clave}")
        if not a.apply:
            print("dry-run: repetir con --apply")
            return
        cf_bytes("PUT", f"{b}/{bucket}/objects/{urllib.parse.quote(clave)}", datos)
        print("subido")
    elif a.accion == "get":          # get <bucket> <clave> <destino>
        bucket, clave, destino = a.args
        datos = cf_bytes("GET", f"{b}/{bucket}/objects/{urllib.parse.quote(clave)}")
        Path(destino).write_bytes(datos)
        print(f"{destino} ({len(datos)} B, sha256 {hashlib.sha256(datos).hexdigest()})")


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sp = p.add_subparsers(dest="cmd", required=True)
    s = sp.add_parser("status", help="nodos (disco libre, cordon, presión) y pods con problema")
    s.add_argument("--deep", action="store_true", help="además pibot throttled y pve (RAM, zpools)")
    s = sp.add_parser("ports", help="NodePorts usados; --serie 30890 da el siguiente libre")
    s.add_argument("--serie")
    s = sp.add_parser("app", help="resumen de un namespace: pods, svc, ingress, pvc, cronjobs, carpeta del repo")
    s.add_argument("ns")
    s = sp.add_parser("wait", help="esperar un rollout (en vez de sleep); si falla muestra pods y logs")
    s.add_argument("ns"); s.add_argument("name"); s.add_argument("--kind", default="deploy"); s.add_argument("--timeout", default="5m")
    sp.add_parser("flux", help="fuente vs SHA de main, Kustomizations activas (Ready y revisión), suspendidas, HelmReleases y nodo de cada pod")
    sp.add_parser("alertas", help="alertas activas de vmalert (pending/firing), una por línea; horas en UTC")
    s = sp.add_parser("io", help="latencia/uso por disco e iowait/PSI por nodo (máximo de --ventana); --en 2026-10-17T01:36:00Z para mirar una ráfaga pasada")
    s.add_argument("--en"); s.add_argument("--ventana", default="10m")
    s = sp.add_parser("sops", help="keys|encrypt <archivo> con SOPS_AGE_KEY_FILE ya puesto (aplicar = merge; lo hace Flux)")
    s.add_argument("accion", choices=["keys", "encrypt"]); s.add_argument("archivo")
    s = sp.add_parser("ssh", help="ssh <pibot|pve|node-1..3> <comando>: LAN y si no, tailnet")
    s.add_argument("host"); s.add_argument("comando", nargs=argparse.REMAINDER)
    s = sp.add_parser("doc", help="doc <archivo> [sección]: índice o una sola sección (p. ej. doc DISENO-APPS 4.2)")
    s.add_argument("archivo"); s.add_argument("seccion", nargs="?")
    s = sp.add_parser("cf", help="Cloudflare: zones | tunnels | routes <túnel> | route <túnel> <host> <servicio> [--apply] | api <M> <ruta> [-d JSON|@archivo]")
    s.add_argument("accion", choices=["zones", "tunnels", "routes", "route", "api"]); s.add_argument("args", nargs="*")
    s.add_argument("-d", "--data"); s.add_argument("--apply", action="store_true")
    s = sp.add_parser("r2", help="R2: ls [bucket] | mb <bucket> [--apply] | put <bucket> <archivo> [clave] [--apply] | get <bucket> <clave> <destino>")
    s.add_argument("accion", choices=["ls", "mb", "put", "get"]); s.add_argument("args", nargs="*")
    s.add_argument("--apply", action="store_true")
    a = p.parse_args()
    globals()[f"cmd_{a.cmd}"](a)


if __name__ == "__main__":
    main()
