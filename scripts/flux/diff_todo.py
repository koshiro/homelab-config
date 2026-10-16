"""kubectl diff -k en cada carpeta con kustomization de cluster/; una línea por carpeta (OK, CAMBIOS o ERROR)."""
import pathlib
import subprocess

REPO = pathlib.Path(__file__).resolve().parents[2] / "cluster"


# cluster/flux entra solo cuando el cluster ya tiene los CRD de Flux (fase 3 de docs/PLAN-FLUX.md).
FLUX = subprocess.run(["kubectl", "get", "crd", "kustomizations.kustomize.toolkit.fluxcd.io"],
                      capture_output=True).returncode == 0


def aplicable(k):
    """Carpetas con kustomization, sin Components (components/, solo-flux/) ni, antes de la fase 3, cluster/flux."""
    rel = k.relative_to(REPO).parts
    return ("components" not in rel and (FLUX or rel[0] != "flux")
            and "kind: Component" not in k.read_text())


for d in sorted({p.parent for p in REPO.rglob("kustomization.y*ml") if aplicable(p)}):
    p = subprocess.run(["kubectl", "diff", "-k", str(d)], capture_output=True, text=True, timeout=300)
    rel = d.relative_to(REPO)
    if p.returncode == 0:
        print(f"OK      {rel}")
    elif p.returncode == 1:
        objs = [l.split()[-1].rsplit("/", 1)[-1] for l in p.stdout.splitlines() if l.startswith("diff -u -N")]
        print(f"CAMBIOS {rel}: {len(objs)} -> {', '.join(objs[:8])}")
    else:
        err = p.stderr.strip().splitlines()
        print(f"ERROR   {rel}: {err[-1] if err else p.returncode}")
