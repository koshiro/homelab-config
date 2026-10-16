"""Falla si algún secreto del repo no está como Flux lo necesita (lo corre el CI en cada PR).

Reglas: todo *.sops.y*ml de cluster/ es un manifiesto estructurado (no binario), con metadatos sops, destinatario age y
cada valor de data/stringData cifrado (ENC[...]); ningún otro YAML de cluster/ define un Secret con data o stringData.
Sin dependencias: corre con el python3 del runner.
"""
import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parents[2]
errores = []

for f in sorted((REPO / "cluster").rglob("*.y*ml")):
    rel = f.relative_to(REPO)
    t = f.read_text(errors="ignore")
    es_sops = ".sops." in f.name
    if not es_sops:
        for doc in re.split(r"^---\s*$", t, flags=re.M):
            if re.search(r"^kind:\s*Secret\s*$", doc, re.M) and re.search(r"^(data|stringData):\s*$", doc, re.M):
                errores.append(f"{rel}: Secret con datos fuera de un archivo *.sops.*")
        continue
    if t.lstrip().startswith("{"):
        errores.append(f"{rel}: formato binario/JSON (recifrar como YAML con .sops.yaml)")
        continue
    if not re.search(r"^sops:\s*$", t, re.M) or not re.search(r"^\s+- recipient: age1", t, re.M):
        errores.append(f"{rel}: sin metadatos sops o sin destinatario age")
    if not re.search(r"^kind:\s*\S+", t, re.M):
        errores.append(f"{rel}: no es un manifiesto (falta kind)")
    seccion = None
    for linea in t.splitlines():
        m = re.match(r"^(\S[^:]*):", linea)
        if m:
            seccion = m.group(1)
            continue
        if seccion in ("data", "stringData") and not linea.lstrip().startswith("#"):
            v = re.match(r"^\s+[^:\s][^:]*:\s*(.*)$", linea)
            if v and not v.group(1).startswith("ENC["):
                errores.append(f"{rel}: valor sin cifrar en {seccion}")
                break

for e in errores:
    print("FALLA", e)
print(f"secretos revisados; fallas: {len(errores)}")
sys.exit(1 if errores else 0)
