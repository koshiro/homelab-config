"""Línea base de la adopción de Flux (docs/PLAN-FLUX.md, fase 4): guarda el estado de los workloads o lo compara.

Por workload (Deployment, StatefulSet, DaemonSet, CronJob y el Cluster de CNPG): su generation, la plantilla vigente
(pod-template-hash del ReplicaSet de mayor revisión, o el hash de la ControllerRevision de mayor revisión) y los UID
de sus pods (sin los de Jobs). Además, los objetos de cada namespace, sin los tipos que cambian solos.

  linea_base.py guardar [--nombre pre-flux] [--forzar]   # ~/.cache/flux-plan/linea-base-<nombre>.json (fuera del repo)
  linea_base.py comparar [--nombre pre-flux]             # sale con 1 si hay un hash o generation distinto, un pod
                                                         # reemplazado, un workload que falta o un objeto menos
"""
import argparse
import collections
import concurrent.futures
import datetime
import json
import pathlib
import subprocess
import sys

DIR = pathlib.Path.home() / ".cache" / "flux-plan"
WORKLOADS = ("Deployment", "StatefulSet", "DaemonSet", "CronJob", "Cluster")
# Tipos que cambian sin que nadie aplique nada (pods, Jobs de CronJobs, revisiones, eventos, métricas, certificados
# emitidos, respaldos diarios de CNPG, snapshots de etcd): no entran en el conteo de objetos.
VOLATILES = {
    "events", "events.events.k8s.io", "pods", "replicasets.apps", "controllerrevisions.apps", "jobs.batch",
    "endpoints", "endpointslices.discovery.k8s.io", "leases.coordination.k8s.io", "nodes", "componentstatuses",
    "certificatesigningrequests.certificates.k8s.io", "etcdsnapshotfiles.k3s.cattle.io", "csinodes.storage.k8s.io",
    "nodemetrics.metrics.k8s.io", "podmetrics.metrics.k8s.io", "ipaddresses.networking.k8s.io",
    "volumeattachments.storage.k8s.io", "certificaterequests.cert-manager.io", "orders.acme.cert-manager.io",
    "challenges.acme.cert-manager.io", "backups.postgresql.cnpg.io",
}


def kubectl(*args, opcional=False):
    p = subprocess.run(["kubectl", *args], capture_output=True, text=True, timeout=300)
    if p.returncode:
        if opcional:
            return None
        sys.exit(f"kubectl {' '.join(args)}: {p.stderr.strip()[:200]}")
    return p.stdout


def items(*args, opcional=False):
    out = kubectl("get", *args, "-A", "-o", "json", opcional=opcional)
    return json.loads(out)["items"] if out else []


def ref(o):
    md = o["metadata"]
    return f"{o['kind']}/{md.get('namespace', '')}/{md['name']}"


def workloads():
    objs = items("deployments,statefulsets,daemonsets,cronjobs,replicasets,controllerrevisions")
    objs += items("clusters.postgresql.cnpg.io", opcional=True)
    por_uid = {o["metadata"]["uid"]: ref(o) for o in objs if o["kind"] in WORKLOADS}
    w = {r: {"gen": o["metadata"].get("generation"), "hash": "", "pods": []}
         for o in objs if o["kind"] in WORKLOADS for r in [ref(o)]}
    # Plantilla vigente: ReplicaSet (Deployment) o ControllerRevision (StatefulSet, DaemonSet) de mayor revisión.
    rev, rs_de = {}, {}
    for o in objs:
        if o["kind"] not in ("ReplicaSet", "ControllerRevision"):
            continue
        md = o["metadata"]
        dueño = next((por_uid[r["uid"]] for r in md.get("ownerReferences") or []
                      if r.get("controller") and r["uid"] in por_uid), None)
        if not dueño:
            continue
        if o["kind"] == "ReplicaSet":
            rs_de[md["uid"]] = dueño
            n = int((md.get("annotations") or {}).get("deployment.kubernetes.io/revision", 0))
            h = (md.get("labels") or {}).get("pod-template-hash", md["name"])
        else:
            n, h = o.get("revision", 0), md["name"].rsplit("-", 1)[-1]
        if n >= rev.get(dueño, -1):
            rev[dueño], w[dueño]["hash"] = n, h
    for p in items("pods"):
        md = p["metadata"]
        c = next((r for r in md.get("ownerReferences") or [] if r.get("controller")), None)
        if c and c["kind"] == "Job":
            continue
        if c:
            dueño = rs_de.get(c["uid"]) or por_uid.get(c["uid"]) or f"{c['kind']}/{md['namespace']}/{c['name']}"
        else:
            dueño = f"Pod/{md['namespace']}/{md['name']}"
        w.setdefault(dueño, {"gen": None, "hash": "", "pods": []})["pods"].append(md["uid"])
    for v in w.values():
        v["pods"].sort()
    return w


def objetos():
    tipos = [t for t in kubectl("api-resources", "--verbs=list", "-o", "name").split() if t not in VOLATILES]
    jp = '{range .items[*]}{.metadata.namespace}{"\\t"}{.metadata.name}{"\\n"}{end}'
    res = collections.defaultdict(dict)
    with concurrent.futures.ThreadPoolExecutor(8) as ex:
        for t, out in zip(tipos, ex.map(lambda t: kubectl("get", t, "-A", "-o", f"jsonpath={jp}", opcional=True), tipos)):
            por_ns = collections.defaultdict(list)
            for linea in (out or "").splitlines():
                ns, _, nombre = linea.partition("\t")
                por_ns[ns or "(cluster)"].append(nombre)
            for ns, nombres in por_ns.items():
                res[ns][t] = sorted(nombres)
    return res


def tomar():
    return {"fecha": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
            "contexto": kubectl("config", "current-context").strip(),
            "workloads": workloads(), "objetos": objetos()}


def guardar(a, archivo):
    if archivo.exists() and not a.forzar:
        sys.exit(f"{archivo} ya existe (--forzar para reemplazarla, o --nombre otra)")
    lb = tomar()
    archivo.parent.mkdir(parents=True, exist_ok=True)
    archivo.write_text(json.dumps(lb, indent=1, sort_keys=True))
    w, o = lb["workloads"], lb["objetos"]
    print(f"guardada {archivo} ({lb['fecha']}, {lb['contexto']}): {len(w)} workloads, "
          f"{sum(len(v['pods']) for v in w.values())} pods, "
          f"{sum(len(n) for t in o.values() for n in t.values())} objetos en {len(o)} namespaces")


def comparar(a, archivo):
    if not archivo.exists():
        sys.exit(f"no existe {archivo}: primero guardar")
    base, hoy = json.loads(archivo.read_text()), tomar()
    bw, hw = base["workloads"], hoy["workloads"]
    hash_, gen, pods, faltan = [], [], [], []
    for r, b in sorted(bw.items()):
        h = hw.get(r)
        if h is None:
            faltan.append(r)
            continue
        if b["hash"] != h["hash"]:
            hash_.append(f"HASH  {r}: {b['hash']} -> {h['hash']}")
        if b["gen"] != h["gen"]:
            gen.append(f"GEN   {r}: {b['gen']} -> {h['gen']}")
        idos = set(b["pods"]) - set(h["pods"])
        if idos:
            pods.append(f"PODS  {r}: {len(idos)} de {len(b['pods'])} reemplazados")
    nuevos = sorted(set(hw) - set(bw))
    menos, total_b, total_h = [], 0, 0
    for ns in sorted(set(base["objetos"]) | set(hoy["objetos"])):
        bt, ht = base["objetos"].get(ns, {}), hoy["objetos"].get(ns, {})
        for t in sorted(set(bt) | set(ht)):
            total_b, total_h = total_b + len(bt.get(t, [])), total_h + len(ht.get(t, []))
            idos = sorted(set(bt.get(t, [])) - set(ht.get(t, [])))
            if idos:
                menos.append(f"MENOS {ns} {t}: {', '.join(idos[:8])}{' …' if len(idos) > 8 else ''}")
    print(f"línea base {base['fecha']} ({base['contexto']}) vs {hoy['fecha']}")
    print(f"workloads {len(bw)} -> {len(hw)}: hash distinto {len(hash_)}, generation distinta {len(gen)}, "
          f"con pods reemplazados {len(pods)}, faltan {len(faltan)}, nuevos {len(nuevos)}")
    print(f"objetos {total_b} -> {total_h}: tipos con objetos menos {len(menos)}")
    for linea in hash_ + gen + pods + [f"FALTA {r}" for r in faltan] + menos:
        print(linea)
    for r in nuevos:
        print(f"NUEVO {r}")
    sys.exit(1 if hash_ or gen or pods or faltan or menos else 0)


ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
ap.add_argument("accion", choices=["guardar", "comparar"])
ap.add_argument("--nombre", default="pre-flux", help="nombre de la línea base (default pre-flux)")
ap.add_argument("--forzar", action="store_true", help="guardar: reemplazar una línea base existente")
args = ap.parse_args()
{"guardar": guardar, "comparar": comparar}[args.accion](args, DIR / f"linea-base-{args.nombre}.json")
