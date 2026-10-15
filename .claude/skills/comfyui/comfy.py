#!/usr/bin/env python3
"""CLI para diagnosticar ComfyUI del homelab sin explorar el pod a mano.

Todo corre dentro del pod (kubectl exec + python del venv), así no hace falta port-forward ni pasar por
Cloudflare Access.
"""
import argparse
import subprocess
import sys

NS, DEPLOY, PY = "comfyui", "deploy/comfyui", "/app/venv/bin/python"

# Código que se ejecuta dentro del pod. Recibe argv del subcomando.
REMOTE = r'''
import glob, json, os, re, sqlite3, sys, collections, urllib.request
cmd, args = sys.argv[1], sys.argv[2:]
STATIC = "/app/venv/lib/python3.12/site-packages/comfyui_frontend_package/static/assets/*.js.map"
BASE = "http://127.0.0.1:8188"

def sources():
    seen = set()
    for f in glob.glob(STATIC):
        m = json.load(open(f))
        for src, content in zip(m["sources"], m.get("sourcesContent") or []):
            if content and src not in seen and "node_modules" not in src:
                seen.add(src)
                yield src.replace("../../src/", ""), content

if cmd == "src":
    fpat = re.compile(args[0])
    lpat = re.compile(args[1], re.I) if len(args) > 1 else None
    for src, content in sources():
        if not fpat.search(src):
            continue
        if lpat is None:
            print(src, len(content.splitlines()))
            continue
        for i, line in enumerate(content.splitlines(), 1):
            if lpat.search(line):
                print(f"{src}:{i}: {line.strip()[:200]}")
elif cmd == "show":
    start = int(args[1]) if len(args) > 1 else 1
    end = int(args[2]) if len(args) > 2 else 10**9
    for src, content in sources():
        if src.endswith(args[0]):
            for i, line in enumerate(content.splitlines(), 1):
                if start <= i <= end:
                    print(f"{i}: {line}")
            break
    else:
        print("no encontrado")
elif cmd == "api":
    data = json.load(urllib.request.urlopen(BASE + args[0]))
    print(json.dumps(data, indent=1, ensure_ascii=False)[: int(args[1]) if len(args) > 1 else 6000])
elif cmd == "assets":
    disk = collections.Counter()
    for root, _, files in os.walk("/app/output"):
        disk[os.path.relpath(root, "/app/output")] += len(files)
    con = sqlite3.connect("file:/app/user/comfyui.db?mode=ro", uri=True)
    db = collections.Counter()
    for (path,) in con.execute("select path from asset_contents where path like '/app/output/%' and is_missing=0"):
        db[os.path.relpath(os.path.dirname(path), "/app/output")] += 1
    print(f"{'carpeta':40} {'disco':>6} {'BD':>6}")
    for k in sorted(set(disk) | set(db)):
        flag = "" if disk[k] == db[k] else "  <- difiere"
        print(f"{k:40} {disk[k]:6} {db[k]:6}{flag}")
    newest = con.execute("select a.created_at, a.loader_path from assets a join asset_contents c on c.id=a.content_id "
                         "where c.path like '/app/output/%' order by a.created_at desc limit 3").fetchall()
    print("más nuevos:", newest)
    sample = json.load(urllib.request.urlopen(BASE + "/api/assets?include_tags=output&limit=1"))["assets"]
    print("user_metadata de muestra (debe traer subfolder):", sample[0].get("user_metadata") if sample else None)
else:
    print("subcomando desconocido", cmd)
'''


def remote(*argv: str) -> int:
    proc = subprocess.run(
        ["kubectl", "-n", NS, "exec", "-i", DEPLOY, "-c", "comfyui", "--", PY, "-", *argv],
        input=REMOTE, text=True)
    return proc.returncode


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("src", help="lista fuentes TS/Vue del frontend (sourcemaps) o grep: src <archivo-regex> [<línea-regex>]")
    s.add_argument("file_re")
    s.add_argument("line_re", nargs="?")
    s = sub.add_parser("show", help="muestra una fuente del frontend: show <sufijo-ruta> [desde] [hasta]")
    s.add_argument("suffix")
    s.add_argument("start", nargs="?")
    s.add_argument("end", nargs="?")
    s = sub.add_parser("api", help="GET a la API interna: api /api/assets?limit=2 [max_chars]")
    s.add_argument("path")
    s.add_argument("max_chars", nargs="?")
    sub.add_parser("assets", help="salidas en disco vs BD de assets, más nuevos y user_metadata")
    s = sub.add_parser("logs", help="logs del pod filtrados: logs [regex] [--tail N]")
    s.add_argument("pattern", nargs="?")
    s.add_argument("--tail", default="400")
    a = p.parse_args()

    if a.cmd == "logs":
        out = subprocess.run(["kubectl", "-n", NS, "logs", DEPLOY, "-c", "comfyui", f"--tail={a.tail}"],
                             capture_output=True, text=True).stdout
        import re
        pat = re.compile(a.pattern, re.I) if a.pattern else None
        for line in out.splitlines():
            if pat is None or pat.search(line):
                print(line)
        return 0
    rest = [x for x in vars(a).values() if x is not None and x != a.cmd]
    return remote(a.cmd, *[str(x) for x in rest])


if __name__ == "__main__":
    sys.exit(main())
