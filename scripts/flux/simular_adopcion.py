"""Qué cambiaría en el cluster al adoptar Kustomizations de Flux, más allá de lo que muestra `flux diff ks`.

Al adoptar un objeto, kustomize-controller pasa a su nombre los campos de los managers `kubectl*` y
`before-first-apply` (incluidos los valores por defecto que el apiserver les atribuyó al crearlo) y aplica lo de git:
lo que esos managers tenían y git no trae, se borra, y el apiserver lo vuelve a completar con el valor por defecto.
`flux diff` hace el dry-run sin ese traspaso, así que no lo ve (2026-10-16: `pve-exporter` se reinició porque tenía
`imagePullPolicy: Always` de cuando usaba `:latest`, y git fija el tag sin decir nada).

Por cada objeto del render (`flux build ks`): campos de `kubectl*` que no están en git ni son de otro manager (dry-run
server-side con un manager propio) y su valor tras borrarlos (dry-run de crear una copia renombrada). Solo dry-runs.
Las líneas CAMBIA son cambios reales (REINICIA si caen en la plantilla de pods); los valores de Secrets no se muestran.
Los Secrets SOPS (que `flux diff` tampoco muestra) se descifran solo en memoria y se comparan con el vivo (SOPS DISTINTO).

  python3 -I scripts/flux/simular_adopcion.py <ks>...    # sale con 1 si algo CAMBIA o queda SIN SIMULAR
"""
import base64
import concurrent.futures
import copy
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile

FLUX = str(pathlib.Path.home() / ".cache/flux-plan/bin/flux")
REPO = pathlib.Path(__file__).resolve().parents[2]
SIM = "flux-sim"
SOPS_ENV = dict(os.environ, SOPS_AGE_KEY_FILE=str(pathlib.Path.home() / ".config/sops/age/keys.txt"))
# Los que kustomize-controller absorbe al adoptar (ApplyCleanupOptions de Flux; "kubectl" es prefijo).
def absorbido(m):
    return (m["manager"].startswith("kubectl") and m["operation"] in ("Update", "Apply")
            or m["manager"] == "before-first-apply" and m["operation"] == "Update"
            or m["manager"] == "kustomize-controller" and m["operation"] == "Update")


ESPERADO = {("f:metadata", "f:annotations", "f:kubectl.kubernetes.io/last-applied-configuration"),
            ("f:metadata", "f:labels", "f:kubernetes.io/metadata.name"),  # el apiserver la fija igual al nombre
            ("f:metadata", "f:annotations", "f:deprecated.daemonset.template.generation")}  # y esta = generation
# En un Service el apiserver conserva lo asignado (clusterIP, nodePort) aunque el apply no lo traiga.
ASIGNADO = re.compile(r"f:clusterIPs?$|f:nodePort$|f:healthCheckNodePort$|f:ipFamilies$|f:ipFamilyPolicy$")


def kubectl(args, stdin=None):
    return subprocess.run(["kubectl", *args], input=stdin, capture_output=True, text=True, timeout=300)


def jsons(texto):
    dec, i, out, texto = json.JSONDecoder(), 0, [], texto.strip()
    while i < len(texto):
        o, i = dec.raw_decode(texto, i)
        out += o.get("items") or [o] if o.get("kind", "").endswith("List") else [o]
        while i < len(texto) and texto[i].isspace():
            i += 1
    return out


def clave(o):
    md = o["metadata"]
    return (o["apiVersion"].split("/")[0] if "/" in o["apiVersion"] else "", o["kind"], md.get("namespace", ""), md["name"])


def hojas(fields, pre=()):
    """fieldsV1 → (hojas, atómicas): hoja = campo propio; atómica = hoja sin hijos ({}), cubre todo lo de abajo."""
    h, a = set(), set()
    for k, v in fields.items():
        if k == ".":
            continue
        p = pre + (k,)
        if not v or set(v) == {"."}:
            h.add(p)
            if not v:
                a.add(p)
        else:
            hh, aa = hojas(v, p)
            h |= hh
            a |= aa
    return h, a


def resolver(obj, ruta):
    for c in ruta:
        if obj is None:
            return None
        if c.startswith("f:"):
            obj = obj.get(c[2:]) if isinstance(obj, dict) else None
        elif c.startswith("k:"):
            k = json.loads(c[2:])
            obj = next((e for e in obj or [] if isinstance(e, dict) and all(e.get(x) == y for x, y in k.items())), None)
        elif c.startswith("v:"):
            return json.loads(c[2:]) in (obj or [])
        elif c.startswith("i:"):
            i = int(c[2:])
            obj = obj[i] if isinstance(obj, list) and i < len(obj) else None
    return obj


def copia(o):
    """El objeto de git, renombrado, para un dry-run de crear: sus valores por defecto son los que quedarían."""
    c = copy.deepcopy(o)
    c["metadata"]["name"] = c["metadata"]["name"][:45] + "-fluxsim"
    if c["kind"] == "CustomResourceDefinition":  # el nombre debe ser <plural>.<group>
        c["spec"]["group"] = "fluxsim." + c["spec"]["group"]
        c["metadata"]["name"] = f"{c['spec']['names']['plural']}.{c['spec']['group']}"
    for k in ("resourceVersion", "uid", "creationTimestamp"):
        c["metadata"].pop(k, None)
    if c["kind"] == "Service":
        if c["spec"].get("clusterIP") != "None":
            c["spec"].pop("clusterIP", None)
            c["spec"].pop("clusterIPs", None)
        for p in c["spec"].get("ports") or []:
            p.pop("nodePort", None)
    return c


def ver(v):
    s = json.dumps(v, ensure_ascii=False)
    return s if len(s) <= 80 else s[:77] + "…"


def ks_spec(ks):
    for f in ("cluster/flux/apps.yaml", "cluster/flux/capas.yaml"):
        for d in (REPO / f).read_text().split("\n---\n"):
            if re.search(rf"^metadata:\n  name: {re.escape(ks)}\n", d, re.M):
                comps = re.search(r"^  components:\n((?:    - \S+\n?)+)", d, re.M)
                return (re.search(r"^  path: \./(\S+)", d, re.M).group(1), f,
                        re.findall(r"- (\S+)", comps.group(1)) if comps else [])
    sys.exit(f"no existe la Kustomization {ks}")


def descifrados(path, comps):
    """Secrets de los *.sops.* de los Component: {nombre: {clave: base64}} (solo en memoria; no se imprimen)."""
    out = {}
    for c in comps:
        d = REPO / path / c
        for r in re.findall(r"^\s*- (\S+\.sops\.\S+)", (d / "kustomization.yaml").read_text(), re.M):
            p = subprocess.run(["sops", "-d", "--output-type", "json", str((d / r).resolve())], capture_output=True,
                               text=True, env=SOPS_ENV, timeout=60)
            if p.returncode:
                sys.exit(f"sops -d {r}: {p.stderr.strip()[-200:]}")
            s = json.loads(p.stdout)
            datos = dict(s.get("data") or {})
            datos.update({k: base64.b64encode(v.encode()).decode() for k, v in (s.get("stringData") or {}).items()})
            out[s["metadata"]["name"]] = datos
    return out


def enmascarado(o):
    """flux build deja los valores SOPS como base64("**SOPS**")."""
    return o["kind"] == "Secret" and (
        any(base64.b64decode(v or "") == b"**SOPS**" for v in (o.get("data") or {}).values())
        or "**SOPS**" in (o.get("stringData") or {}).values())


malos = 0
DETALLE = "--detalle" in sys.argv  # imprime también los campos que vuelven al mismo valor por defecto
for ks in [a for a in sys.argv[1:] if a != "--detalle"]:
    path, f, comps = ks_spec(ks)
    b = subprocess.run([FLUX, "build", "ks", ks, "--path", str(REPO / path), "--kustomization-file", str(REPO / f),
                        "--dry-run"], capture_output=True, text=True, timeout=300)
    if b.returncode:
        sys.exit(f"{ks}: flux build: {b.stderr.strip()[-300:]}")
    r = kubectl(["create", "--dry-run=client", "--validate=false", "-o", "json", "-f", "-"], b.stdout)
    git = {clave(o): o for o in jsons(r.stdout)}
    with tempfile.NamedTemporaryFile("w", suffix=".json") as t:
        json.dump({"apiVersion": "v1", "kind": "List", "items": list(git.values())}, t)
        t.flush()
        vivos = {clave(o): o for o in jsons(kubectl(["get", "-f", t.name, "-o", "json", "--show-managed-fields",
                                                     "--ignore-not-found"]).stdout or "{}") if o.get("metadata")}
        a = kubectl(["apply", "--server-side", "--dry-run=server", "--force-conflicts", f"--field-manager={SIM}",
                     "--show-managed-fields", "-f", t.name, "-o", "json"])
        if a.returncode:
            sys.exit(f"{ks}: dry-run apply: {a.stderr.strip()[-300:]}")
        aplicados = {clave(o): o for o in jsons(a.stdout)}
    nuevos = sorted(set(git) - set(vivos))
    # Secrets SOPS: el valor descifrado reemplaza la máscara (para la simulación) y se compara con el vivo.
    n_sops = sum(enmascarado(o) for o in git.values())
    sops, claro = [], descifrados(path, comps) if n_sops else {}
    for k, o in git.items():
        if not enmascarado(o):
            continue
        nombre = f"Secret/{k[2]}/{k[3]}"
        if k[3] not in claro:
            sops.append(f"SOPS SIN DESCIFRAR {nombre}")
            continue
        o["data"], _ = claro[k[3]], o.pop("stringData", None)
        if k not in vivos:
            continue
        viv = vivos[k].get("data") or {}
        dif = [f"solo en git {sorted(set(o['data']) - set(viv))}" if set(o["data"]) - set(viv) else "",
               f"solo en vivo {sorted(set(viv) - set(o['data']))}" if set(viv) - set(o["data"]) else "",
               f"valores distintos {sorted(c for c in set(viv) & set(o['data']) if viv[c] != o['data'][c])}"
               if any(viv[c] != o["data"][c] for c in set(viv) & set(o["data"])) else ""]
        if any(dif):
            sops.append(f"SOPS DISTINTO {nombre}: " + "; ".join(d for d in dif if d))
    borrar = {}  # clave -> [rutas que Flux dejaría sin dueño y borraría]
    for k, vivo in vivos.items():
        mf = vivo["metadata"].get("managedFields") or []
        mio, otros, otros_at, absorb = set(), set(), set(), set()
        for m in (aplicados.get(k) or {}).get("metadata", {}).get("managedFields") or []:
            if m["manager"] == SIM:
                hh, aa = hojas(m.get("fieldsV1") or {})
                mio |= hh
                otros_at |= aa
        for m in mf:
            hh, aa = hojas(m.get("fieldsV1") or {})
            if m.get("subresource") == "status":
                continue
            if absorbido(m):
                absorb |= hh
            else:
                otros |= hh
                otros_at |= aa
        rutas = sorted(p for p in absorb - mio - otros - ESPERADO
                       if p[0] != "f:status" and not any(p[:i] in otros_at for i in range(1, len(p))))
        if vivo["kind"] == "Service":
            rutas = [p for p in rutas if not ASIGNADO.search(p[-1])]
        if rutas:
            borrar[k] = rutas

    def simular(k):
        r = kubectl(["create", "--dry-run=server", "-o", "json", "-f", "-"], json.dumps(copia(git[k])))
        return k, (json.loads(r.stdout) if r.returncode == 0 else None), r.stderr.strip()[-160:]

    iguales, cambios, sin = 0, [], []
    with concurrent.futures.ThreadPoolExecutor(8) as ex:
        for k, fresco, err in ex.map(simular, borrar):
            nombre = f"{k[1]}/{k[2] + '/' if k[2] else ''}{k[3]}"
            for p in borrar[k]:
                legible = ".".join(c[2:] if c.startswith("f:") else c for c in p)
                antes = resolver(vivos[k], p)
                if fresco is None:
                    sin.append(f"SIN SIMULAR {nombre} {legible} ({err})")
                    continue
                despues = resolver(fresco, p)
                if antes == despues:
                    iguales += 1
                    if DETALLE:
                        print(f"igual  {nombre} {legible}")
                    continue
                reinicia = " [REINICIA]" if p[:3] == ("f:spec", "f:template", "f:spec") or p[:4] == (
                    "f:spec", "f:template", "f:metadata", "f:annotations") or p[:4] == (
                    "f:spec", "f:template", "f:metadata", "f:labels") else ""
                valores = "" if k[1] == "Secret" else f": {ver(antes)} -> {ver(despues)}"
                cambios.append(f"CAMBIA {nombre} {legible}{valores}{reinicia}")
    print(f"== {ks}: {len(git)} objetos ({len(nuevos)} nuevos); campos que Flux borraría: "
          f"{sum(map(len, borrar.values()))} (vuelven al mismo valor por defecto {iguales}, cambian {len(cambios)}, "
          f"sin simular {len(sin)}); Secrets SOPS {n_sops}, distintos {len(sops)}")
    for k in nuevos:
        print(f"NUEVO  {k[1]}/{k[2] + '/' if k[2] else ''}{k[3]}")
    for linea in cambios + sin + sops:
        print(linea)
    malos += len(cambios) + len(sin) + len(sops)
sys.exit(1 if malos else 0)
