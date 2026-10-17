"""Resume la carpeta de scripts/ssd/prueba.sh: latencias por prueba y curva del llenado con temperatura.

Uso: python3 scripts/ssd/analiza.py prueba-ssd-<serie>
"""
import csv, glob, json, os, sys

d = sys.argv[1]
ms = lambda ns: ns / 1e6


def pct(lat, p):
    return ms(lat.get("percentile", {}).get(p, 0))


print(f"{'prueba':26} {'IOPS':>7} {'MB/s':>7} {'p50':>7} {'p99':>7} {'p99.9':>8} {'máx':>8}  (ms; fsync aparte)")
for f in sorted(glob.glob(os.path.join(d, "[ABD]*.json"))):
    j = json.load(open(f))["jobs"][0]
    lado = "read" if j["read"]["io_bytes"] > j["write"]["io_bytes"] else "write"
    s = j[lado]
    lat = s["clat_ns"]
    print(f"{os.path.basename(f)[:-5]:26} {s['iops']:7.0f} {s['bw_bytes'] / 1e6:7.1f} {pct(lat, '50.000000'):7.2f} "
          f"{pct(lat, '99.000000'):7.2f} {pct(lat, '99.900000'):8.2f} {ms(lat['max']):8.1f}")
    sy = j.get("sync", {}).get("lat_ns", {})
    if sy.get("N"):
        print(f"{'  └ fsync':26} {'':7} {'':7} {pct(sy, '50.000000'):7.2f} {pct(sy, '99.000000'):7.2f} "
              f"{pct(sy, '99.900000'):8.2f} {ms(sy['max']):8.1f}  media {ms(sy['mean']):.2f}")

# llenado: MB/s cada 1 s → tramos de 60 s con GB acumulados y temperatura
cj = json.load(open(os.path.join(d, "C-llenado-1m-qd8.json")))
inicio = cj["timestamp_ms"] / 1000 - cj["jobs"][0]["job_runtime"] / 1000
temps = [(int(r[0]), [int(x) for x in r[1:]]) for r in csv.reader(open(os.path.join(d, "temps.csv"))) if len(r) > 2]
bw = []
for log in glob.glob(os.path.join(d, "C_bw*.log")):
    for r in csv.reader(open(log)):
        bw.append((int(r[0]) / 1000, int(r[1]) * 1024 / 1e6))
bw.sort()


def temp_en(t):
    cerca = min(temps, key=lambda x: abs(x[0] - t))
    return cerca[1]


print("\nllenado secuencial 1M QD8: tramos de 60 s")
print(f"{'t(s)':>6} {'GB':>6} {'MB/s':>7}  temps (composite,s1,s2,s3,s4)")
gb, tramo = 0.0, []
for t, v in bw:
    gb += v / 1000
    tramo.append(v)
    if len(tramo) == 60:
        print(f"{t:6.0f} {gb:6.1f} {sum(tramo) / 60:7.0f}  {temp_en(inicio + t)}")
        tramo = []
w = cj["jobs"][0]["write"]
print(f"total {w['io_bytes'] / 1e9:.0f} GB en {cj['jobs'][0]['job_runtime'] / 1000:.0f} s, media {w['bw_bytes'] / 1e6:.0f} MB/s")
print("temp máx. durante toda la batería:", [max(t[1][i] for t in temps) for i in range(len(temps[0][1]))])
