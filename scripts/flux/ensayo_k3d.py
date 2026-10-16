"""Ensayo de Flux en un cluster k3d desechable (docs/PLAN-FLUX.md, fases 2 y 6).

  ensayo_k3d.py crear                         cluster k3d con la versión de k3s de prod y la guarda de pods
  ensayo_k3d.py render --rama R               solo escribe la raíz del ensayo (para probarla con flux build)
  ensayo_k3d.py instalar --rama R --clave-git K   Flux desde la rama R: CRD y controladores, secrets flux-system
                                              (clave SSH de solo lectura K) y sops-age, y la Kustomization raíz
                [--como-prod]                 sin quitar el suspend: Flux instalado sin gestionar nada (fase 3)
  ensayo_k3d.py estado                        Kustomizations, HelmRelease, los *.sops.* descifrados y pods por ns
  ensayo_k3d.py borrar                        borra el cluster y su kubeconfig

Seguridad: todo kubectl va con el kubeconfig propio del ensayo (~/.cache/flux-plan/ensayo/kubeconfig), nunca con el
de prod. Como el ensayo lleva los secretos reales, una ValidatingAdmissionPolicy (la «guarda», en los manifiestos de
arranque de k3s) rechaza todo pod fuera de k3s, Flux y los operadores: sin ella, cloudflared se sumaría a los túneles
de prod, los bots y alertmanager hablarían con Telegram y Postgres o los respaldos podrían escribir en el S3 y el NFS
de prod. Las Kustomizations quedan Ready igual (wait: false), pero ningún workload de apps corre.

Diferencias con prod, solo en la Kustomization raíz del ensayo: sigue la rama R en vez de main, y sus spec.patches
quitan el suspend de las hijas, ponen wait: false (salvo cert-manager, cnpg y el plugin, que sí corren y así prueban
el dependsOn CRD → operador → Cluster) y sacan del render la fuente y la raíz de git (si no, Flux se reaplicaría
gotk-sync.yaml y volvería a main).
Binarios: k3d y flux en el PATH o en ~/.cache/flux-plan/bin.
"""
import argparse
import base64
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys

REPO = pathlib.Path(__file__).resolve().parents[2]
CLUSTER = "flux-ensayo"
CONTEXTO = f"k3d-{CLUSTER}"
IMAGEN = "rancher/k3s:v1.35.9-k3s1"  # la misma de prod (hechos.md); subirla junto con k3s
DIR = pathlib.Path.home() / ".cache/flux-plan/ensayo"
KUBECONFIG = DIR / "kubeconfig"
GUARDA_NS = ["kube-system", "flux-system", "cert-manager", "cnpg-system"]
OPERADORES = "cert-manager|cnpg|cnpg-plugin-barman-cloud"

GUARDA = f"""\
# Guarda del ensayo k3d (scripts/flux/ensayo_k3d.py): ningún pod fuera de {", ".join(GUARDA_NS)}.
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: ensayo-solo-sistema
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
      - apiGroups: [""]
        apiVersions: ["v1"]
        operations: ["CREATE"]
        resources: ["pods"]
    namespaceSelector:
      matchExpressions:
        - key: kubernetes.io/metadata.name
          operator: NotIn
          values: {json.dumps(GUARDA_NS)}
  validations:
    - expression: "false"
      message: "ensayo k3d: solo corren k3s, Flux y los operadores (los secretos son los reales)"
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: ensayo-solo-sistema
spec:
  policyName: ensayo-solo-sistema
  validationActions: [Deny]
"""

PARCHES_HIJAS = f"""\
- target:
    group: kustomize.toolkit.fluxcd.io
    kind: Kustomization
  patch: |
    apiVersion: kustomize.toolkit.fluxcd.io/v1
    kind: Kustomization
    metadata:
      name: hijas
    spec:
      suspend: false
      wait: false
- target:
    group: kustomize.toolkit.fluxcd.io
    kind: Kustomization
    name: "^({OPERADORES})$"
  patch: |
    apiVersion: kustomize.toolkit.fluxcd.io/v1
    kind: Kustomization
    metadata:
      name: operadores
    spec:
      wait: true
"""
PARCHES_RAIZ = """\
- target:
    group: source.toolkit.fluxcd.io
    kind: GitRepository
    name: flux-system
  patch: |
    $patch: delete
    apiVersion: source.toolkit.fluxcd.io/v1
    kind: GitRepository
    metadata:
      name: flux-system
      namespace: flux-system
- target:
    group: kustomize.toolkit.fluxcd.io
    kind: Kustomization
    name: flux-system
  patch: |
    $patch: delete
    apiVersion: kustomize.toolkit.fluxcd.io/v1
    kind: Kustomization
    metadata:
      name: flux-system
      namespace: flux-system
"""


def binario(nombre):
    ruta = shutil.which(nombre) or pathlib.Path.home() / ".cache/flux-plan/bin" / nombre
    if not pathlib.Path(ruta).is_file():
        sys.exit(f"falta {nombre}: ponerlo en el PATH o en ~/.cache/flux-plan/bin")
    return str(ruta)


def correr(cmd, check=True, entrada=None):
    p = subprocess.run(cmd, capture_output=True, text=True, input=entrada)
    if check and p.returncode:
        sys.exit(f"falló: {' '.join(cmd[:4])}…\n{p.stderr.strip() or p.stdout.strip()}")
    return p


def kubectl(*args, check=True, entrada=None):
    return correr(["kubectl", "--kubeconfig", str(KUBECONFIG), "--context", CONTEXTO, *args], check, entrada)


def crear(_):
    DIR.mkdir(parents=True, exist_ok=True)
    guarda = DIR / "guarda.yaml"
    guarda.write_text(GUARDA)
    correr([binario("k3d"), "cluster", "create", CLUSTER, "--image", IMAGEN, "--servers", "1", "--agents", "0",
            "--kubeconfig-update-default=false", "--kubeconfig-switch-context=false", "--wait",
            "--volume", f"{guarda}:/var/lib/rancher/k3s/server/manifests/ensayo-guarda.yaml@server:0"])
    correr([binario("k3d"), "kubeconfig", "write", CLUSTER, "--output", str(KUBECONFIG)])
    kubectl("wait", "--for=create", "validatingadmissionpolicybinding/ensayo-solo-sistema", "--timeout=3m")
    # La política tarda unos segundos en cargarse: comprobar que un pod de prueba se rechaza.
    for _ in range(30):
        p = kubectl("run", "prueba-guarda", "--image=busybox", "--restart=Never", "--dry-run=server", "-n",
                    "default", check=False)
        if p.returncode and "ensayo k3d" in p.stderr:
            break
        kubectl("wait", "--for=create", "namespace/default", "--timeout=10s", check=False)
    else:
        sys.exit("la guarda no rechaza pods: no instalar Flux con los secretos reales")
    print(f"cluster {CLUSTER} listo ({IMAGEN}); guarda activa; kubeconfig {KUBECONFIG}")


def render(a):
    """Escribe la raíz del ensayo (flux-system de git con la rama y los parches) en DIR/raiz.yaml."""
    overlay = DIR / "raiz"
    overlay.mkdir(parents=True, exist_ok=True)
    rama = json.dumps(a.rama)
    texto = PARCHES_RAIZ if a.como_prod else PARCHES_HIJAS + PARCHES_RAIZ
    parches = "\n".join("        " + l if l else "" for l in texto.splitlines())
    (overlay / "kustomization.yaml").write_text(f"""\
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - {os.path.relpath(REPO / "cluster/flux/flux-system", overlay)}
patches:
  - target:
      kind: GitRepository
      name: flux-system
    patch: |-
      - op: replace
        path: /spec/ref
        value:
          branch: {rama}
  - target:
      kind: Kustomization
      name: flux-system
    patch: |-
      - op: add
        path: /spec/patches
        value:
{parches}
""")
    (DIR / "raiz.yaml").write_text(correr(["kubectl", "kustomize", str(overlay)]).stdout)
    print(f"raíz del ensayo: {DIR / 'raiz.yaml'}")


def instalar(a):
    render(a)
    # 1.ª pasada: CRD y controladores (los CR de Flux fallan hasta que existan sus CRD).
    kubectl("apply", "--server-side", "-f", str(DIR / "raiz.yaml"), check=False)
    kubectl("wait", "--for=condition=established", "crd", "-l", "app.kubernetes.io/part-of=flux",
            "--timeout=2m")
    # Los dos secretos del bootstrap.
    correr([binario("flux"), "create", "secret", "git", "flux-system", "--kubeconfig", str(KUBECONFIG),
            "--context", CONTEXTO, "--url=ssh://git@github.com/koshiro/homelab-config",
            f"--private-key-file={a.clave_git}"])
    clave_age = pathlib.Path.home() / ".config/sops/age/keys.txt"
    secreto = kubectl("create", "secret", "generic", "sops-age", "-n", "flux-system",
                      f"--from-file=age.agekey={clave_age}", "--dry-run=client", "-o", "yaml").stdout
    kubectl("apply", "-f", "-", entrada=secreto)
    # 2.ª pasada: GitRepository y Kustomization raíz.
    kubectl("apply", "--server-side", "-f", str(DIR / "raiz.yaml"))
    print(f"Flux instalado desde {a.rama}; esperar con: kubectl --kubeconfig {KUBECONFIG} wait ks --all "
          "-n flux-system --for=condition=Ready --timeout=20m")


def sops_del_repo():
    for f in sorted((REPO / "cluster").rglob("*.sops.y*ml")):
        t = f.read_text()
        nombre = re.search(r"^metadata:\n(?:\s+.*\n)*?\s+name:\s*(\S+)", t, re.M)
        ns = re.search(r"^metadata:\n(?:\s+.*\n)*?\s+namespace:\s*(\S+)", t, re.M)
        yield f.relative_to(REPO), nombre.group(1), ns.group(1)


def estado(_):
    ks = json.loads(kubectl("get", "kustomizations.kustomize.toolkit.fluxcd.io", "-n", "flux-system", "-o",
                            "json").stdout)["items"]
    listas = 0
    for k in sorted(ks, key=lambda x: x["metadata"]["name"]):
        c = {x["type"]: x for x in k.get("status", {}).get("conditions", [])}.get("Ready", {})
        listas += c.get("status") == "True"
        rev = k.get("status", {}).get("lastAppliedRevision", "-")
        print(f"ks  {k['metadata']['name']:<26} Ready={c.get('status', '?'):<7} {rev[:40]:<40} "
              f"{c.get('reason', '')}" + ("" if c.get("status") == "True" else f": {c.get('message', '')[:160]}"))
    print(f"Kustomizations Ready=True: {listas}/{len(ks)}")
    hr = json.loads(kubectl("get", "helmreleases.helm.toolkit.fluxcd.io", "-A", "-o", "json").stdout)["items"]
    for h in hr:
        c = {x["type"]: x for x in h.get("status", {}).get("conditions", [])}.get("Ready", {})
        print(f"hr  {h['metadata']['namespace']}/{h['metadata']['name']} Ready={c.get('status', '?')} "
              f"{c.get('message', '')[:120]}")
    ok = 0
    sops = list(sops_del_repo())
    for ruta, nombre, ns in sops:
        p = kubectl("get", "secret", nombre, "-n", ns, "-o", "json", check=False)
        if p.returncode:
            print(f"sops FALTA {ruta} ({ns}/{nombre})")
            continue
        datos = json.loads(p.stdout).get("data") or {}
        cifrados = [k for k, v in datos.items() if base64.b64decode(v).startswith(b"ENC[")]
        if cifrados or not datos:
            print(f"sops CIFRADO {ruta}: {cifrados or 'sin data'}")
            continue
        ok += 1
    print(f"*.sops.* descifrados en el cluster: {ok}/{len(sops)}")
    pods = json.loads(kubectl("get", "pods", "-A", "-o", "json").stdout)["items"]
    por_ns = {}
    for p in pods:
        por_ns.setdefault(p["metadata"]["namespace"], []).append(p["status"].get("phase", "?"))
    print("pods: " + ", ".join(f"{n}={len(v)}" for n, v in sorted(por_ns.items())))
    fuera = sorted(set(por_ns) - set(GUARDA_NS))
    print(f"pods fuera de la guarda: {fuera or 'ninguno'}")


def borrar(_):
    correr([binario("k3d"), "cluster", "delete", CLUSTER])
    KUBECONFIG.unlink(missing_ok=True)
    print(f"cluster {CLUSTER} borrado")


ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
sub = ap.add_subparsers(dest="cmd", required=True)
sub.add_parser("crear").set_defaults(f=crear)
COMO_PROD = "deja las hijas como en git (suspendidas): ensayo de la fase 3, Flux sin gestionar nada"
r = sub.add_parser("render", help="solo escribe la raíz del ensayo, sin cluster")
r.add_argument("--rama", required=True)
r.add_argument("--como-prod", action="store_true", help=COMO_PROD)
r.set_defaults(f=render)
i = sub.add_parser("instalar")
i.add_argument("--rama", required=True)
i.add_argument("--clave-git", required=True, help="clave SSH privada con acceso de lectura al repo")
i.add_argument("--como-prod", action="store_true", help=COMO_PROD)
i.set_defaults(f=instalar)
sub.add_parser("estado").set_defaults(f=estado)
sub.add_parser("borrar").set_defaults(f=borrar)
a = ap.parse_args()
a.f(a)
