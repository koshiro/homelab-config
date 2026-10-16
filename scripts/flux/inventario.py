"""Inventario inverso: objetos vivos del cluster que no están en ninguna kustomization ni secreto SOPS de cluster/.

Los YAML sueltos (fuera de toda kustomization) no cuentan: Flux no los aplicaría.
Excluye lo que crean controladores (ownerReferences o la lista CONTROLADORES), lo que trae k3s y los objetos que
Kubernetes crea solo. Además cuenta los field managers de los objetos que sí están en el repo (quién más escribe en ellos).
"""
import collections
import json
import pathlib
import re
import subprocess

REPO = pathlib.Path(__file__).resolve().parents[2] / "cluster"
SKIP_TYPES = {
    "events", "events.events.k8s.io", "pods", "replicasets.apps", "controllerrevisions.apps",
    "endpoints", "endpointslices.discovery.k8s.io", "leases.coordination.k8s.io", "nodes",
    "componentstatuses", "certificatesigningrequests.certificates.k8s.io", "etcdsnapshotfiles.k3s.cattle.io",
    "apiservices.apiregistration.k8s.io", "flowschemas.flowcontrol.apiserver.k8s.io",
    "prioritylevelconfigurations.flowcontrol.apiserver.k8s.io", "csinodes.storage.k8s.io",
    "nodemetrics.metrics.k8s.io", "podmetrics.metrics.k8s.io", "ipaddresses.networking.k8s.io",
    "servicecidrs.networking.k8s.io",
}
SYSTEM_NS = {"kube-system", "kube-public", "kube-node-lease"}
# Objetos que crea un controlador sin ownerReferences: no se versionan ni se borran.
CONTROLADORES = {
    ("Secret", "cert-manager", "cert-manager-webhook-ca"),   # lo genera el webhook de cert-manager (su CA)
    ("ConfigMap", "postgresql", "cnpg-default-monitoring"),  # lo copia el operador CNPG en cada ns con un Cluster
}


def run(args, stdin=None):
    p = subprocess.run(args, input=stdin, capture_output=True, text=True, timeout=300)
    return p.returncode, p.stdout, p.stderr


def group_of(api_version):
    return api_version.split("/")[0] if "/" in api_version else ""


def key(obj):
    md = obj.get("metadata", {})
    return (group_of(obj.get("apiVersion", "")), obj.get("kind"), md.get("namespace", ""), md.get("name"))


def objs_from_json(text):
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        # kubectl create -o json con varios objetos imprime JSON concatenados
        dec, idx, out = json.JSONDecoder(), 0, []
        text = text.strip()
        while idx < len(text):
            o, end = dec.raw_decode(text, idx)
            out.append(o)
            idx = end
            while idx < len(text) and text[idx].isspace():
                idx += 1
        return [i for o in out for i in (o.get("items") or [o])]
    return data.get("items") or [data]


# --- 1. Lo que describe el repo ---
known, errors = set(), []
# Sin Components (components/, solo-flux/: los SOPS se cuentan abajo) ni cluster/flux (sus CRD no existen hasta la
# fase 3 de docs/PLAN-FLUX.md; ahí hay que sumarla para que Flux no salga como huérfano).
kdirs = sorted({p.parent for p in REPO.rglob("kustomization.y*ml")
                if "components" not in p.relative_to(REPO).parts and p.relative_to(REPO).parts[0] != "flux"
                and "kind: Component" not in p.read_text()})
for d in kdirs:
    rc, out, err = run(["kubectl", "kustomize", str(d)])
    if rc:
        errors.append(f"kustomize {d}: {err.strip()[:120]}")
        continue
    rc, js, err = run(["kubectl", "create", "--dry-run=client", "--validate=false", "-o", "json", "-f", "-"], out)
    if rc and not js:
        errors.append(f"dry-run {d}: {err.strip()[:120]}")
    for o in objs_from_json(js) if js.strip() else []:
        known.add(key(o))
sops_re = re.compile(r"^kind:\s*(\S+)|^\s{2}name:\s*(\S+)|^\s{2}namespace:\s*(\S+)|^apiVersion:\s*(\S+)", re.M)
for f in list(REPO.rglob("*.y*ml")):
    if f.name.startswith("kustomization"):
        continue
    txt = f.read_text(errors="ignore")
    if txt.lstrip().startswith("{") and "ENC[" in txt:
        o = json.loads(txt)
        known.add(key(o))
        continue
    if "sops:" in txt or "ENC[" in txt:
        for doc in txt.split("\n---"):
            kind = re.search(r"^kind:\s*(\S+)", doc, re.M)
            name = re.search(r"^\s+name:\s*(\S+)", doc, re.M)
            ns = re.search(r"^\s+namespace:\s*(\S+)", doc, re.M)
            api = re.search(r"^apiVersion:\s*(\S+)", doc, re.M)
            if kind and name:
                known.add((group_of(api.group(1)) if api else "", kind.group(1), ns.group(1) if ns else "", name.group(1)))
known_kn = {(g, k, n) for g, k, _, n in known}

# --- 2. Lo que hay vivo ---
rc, out, _ = run(["kubectl", "api-resources", "--verbs=list,get", "-o", "name"])
types = [t for t in out.split() if t not in SKIP_TYPES]
unmanaged = collections.defaultdict(list)
managers = collections.Counter()
mgr_examples = collections.defaultdict(set)
k3s_bundled = 0
for t in types:
    rc, js, err = run(["kubectl", "get", t, "-A", "-o", "json", "--show-managed-fields"])
    if rc or not js.strip():
        continue
    for o in json.loads(js).get("items", []):
        md = o.get("metadata", {})
        g, kind, ns, name = key(o)
        labels, ann = md.get("labels") or {}, md.get("annotations") or {}
        in_repo = (g, kind, ns, name) in known or (g, kind, name) in known_kn and not ns
        if in_repo or (g, kind, "", name) in known:
            for mf in md.get("managedFields") or []:
                m = f"{mf.get('manager')}/{mf.get('operation')}"
                managers[m] += 1
                if len(mgr_examples[m]) < 3:
                    mgr_examples[m].add(f"{kind}/{ns}/{name}")
            continue
        if md.get("ownerReferences") or (kind, ns, name) in CONTROLADORES:
            continue
        if kind in ("PodMetrics", "NodeMetrics"):
            continue
        mset = {mf.get("manager", "") for mf in md.get("managedFields") or []}
        if mset and all(m == "k3s" or m.endswith("@pibot") or m == "clusterrole-aggregation-controller" for m in mset):
            k3s_bundled += 1
            continue
        if labels.get("app.kubernetes.io/managed-by") == "Helm" and ns not in SYSTEM_NS:
            rel = ann.get("meta.helm.sh/release-name", "?")
            unmanaged[ns or "(cluster)"].append(f"{kind}/{name} [HELM release={rel}]")
            continue
        if "objectset.rio.cattle.io/hash" in ann or labels.get("app.kubernetes.io/managed-by") == "Helm" \
                or "helmcharts.helm.cattle.io/configHash" in ann or ns in SYSTEM_NS:
            k3s_bundled += 1
            continue
        if (kind == "ConfigMap" and name == "kube-root-ca.crt") or (kind == "ServiceAccount" and name == "default") \
                or (kind == "Secret" and o.get("type") in ("kubernetes.io/service-account-token", "helm.sh/release.v1")) \
                or (kind == "Secret" and "cert-manager.io/certificate-name" in ann) \
                or (kind == "PersistentVolume" and "pv.kubernetes.io/provisioned-by" in ann) \
                or (kind == "Namespace" and name in ("default",)) or name.startswith("system:") \
                or kind in ("PriorityClass", "RuntimeClass", "StorageClass", "CustomResourceDefinition",
                            "ValidatingWebhookConfiguration", "MutatingWebhookConfiguration", "IngressClass") \
                and ("k3s" in name or name.startswith("system") or "rancher" in name):
            continue
        last = "CSA" if "kubectl.kubernetes.io/last-applied-configuration" in ann else "-"
        mgrs = ",".join(sorted({mf.get("manager", "?") for mf in md.get("managedFields") or []}))[:60]
        unmanaged[ns or "(cluster)"].append(f"{kind}/{name} [{last}; {mgrs}]")

print(f"repo: {len(known)} objetos en {len(kdirs)} kustomizations + secretos SOPS; errores: {len(errors)}")
for e in errors[:5]:
    print("  ", e)
print(f"k3s/sistema omitidos: {k3s_bundled}")
print("\n== Vivos sin archivo en el repo ==")
for ns in sorted(unmanaged):
    print(f"{ns} ({len(unmanaged[ns])}):")
    for x in sorted(unmanaged[ns]):
        print("   ", x)
print("\n== Field managers en objetos del repo ==")
for m, c in managers.most_common():
    print(f"{c:5d}  {m}  ej: {'; '.join(sorted(mgr_examples[m]))}")
