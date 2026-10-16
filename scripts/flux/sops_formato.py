"""Clasifica los *.sops.y*ml de cluster/: binario (todo el archivo cifrado como un blob) o manifiesto estructurado."""
import json
import pathlib
import re

for f in sorted((pathlib.Path(__file__).resolve().parents[2] / "cluster").rglob("*.sops.y*ml")):
    t = f.read_text()
    rel = f.relative_to(f.parents[2]) if len(f.parents) > 2 else f
    if t.lstrip().startswith("{"):
        o = json.loads(t)
        fmt = "BINARIO(json)" if set(o) == {"data", "sops"} and isinstance(o["data"], str) else "json-estructurado"
        regex = o.get("sops", {}).get("encrypted_regex", "-")
        meta = "-"
    elif re.search(r"^data: ENC\[", t, re.M) and not re.search(r"^kind:", t, re.M):
        fmt, regex, meta = "BINARIO(yaml)", "-", "-"
    else:
        fmt = "yaml-estructurado"
        m = re.search(r"encrypted_regex:\s*(\S+)", t)
        regex = m.group(1) if m else "(todo cifrado)"
        name = re.search(r"^metadata:\s*\n(?:\s+.*\n)*?\s+name:\s*(\S+)", t, re.M)
        meta = "name en claro" if name and "ENC[" not in name.group(1) else "name CIFRADO"
    print(f"{fmt:18} regex={regex:22} {meta:14} {rel}")
