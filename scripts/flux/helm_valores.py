"""Chart y valores de usuario de un release de Helm sin el CLI: decodifica el secret sh.helm.release.v1.<rel>.vN.

Uso: python3 -I scripts/flux/helm_valores.py cnpg-system sh.helm.release.v1.cnpg.v1
"""
import base64
import gzip
import json
import subprocess
import sys

ns, name = sys.argv[1], sys.argv[2]
raw = subprocess.run(["kubectl", "get", "secret", "-n", ns, name, "-o", "jsonpath={.data.release}"],
                     capture_output=True, text=True, check=True).stdout
rel = json.loads(gzip.decompress(base64.b64decode(base64.b64decode(raw))))
md = rel["chart"]["metadata"]
print("chart:", md["name"], md["version"], "app", md.get("appVersion"))
print("values:", json.dumps(rel.get("config") or {}, indent=2))
