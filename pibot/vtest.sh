#!/bin/bash
# vtest.sh <etiqueta>: reposo 3 min, carga 4 hilos (7z + openssl 60 s), reposo 3 min; muestrea cada 1 s
L=${1:-v}; D=/tmp/vtest-$L; rm -rf $D; mkdir -p $D; cd $D
mon() { while :; do echo "$(date +%s) $1 $(vcgencmd measure_clock arm|cut -d= -f2) $(vcgencmd measure_volts core|cut -d= -f2) $(vcgencmd measure_temp|cut -d= -f2) $(vcgencmd get_throttled|cut -d= -f2)"; sleep 1; done; }
mon idle1 >> mon.log & M=$!; sleep 180; kill $M
mon load >> mon.log & M=$!
7z b -mmt4 > 7z-4.txt 2>&1
openssl speed -seconds 60 -multi 4 sha256 > ssl.txt 2>&1
kill $M
mon idle2 >> mon.log & M=$!; sleep 180; kill $M
python3 -I - mon.log > summary.txt <<'PY'
import sys, collections
st = collections.OrderedDict()
for line in open(sys.argv[1]):
    p = line.split()
    if len(p) < 6: continue
    ph, f, v = p[1], int(p[2]) / 1e6, int(p[5], 16)
    s = st.setdefault(ph, dict(n=0, uv=0, th=0, fmin=1e9, last=''))
    s['n'] += 1; s['uv'] += v & 1; s['th'] += (v >> 2) & 1
    s['fmin'] = min(s['fmin'], f); s['last'] = p[5]
for ph, s in st.items():
    print(f"{ph:6} muestras={s['n']} bajo_voltaje_activo={s['uv']} throttling_activo={s['th']} freq_min={s['fmin']:.0f}MHz ultimo={s['last']}")
PY
grep Tot: 7z-4.txt >> summary.txt; grep "^sha256 " ssl.txt | tail -1 >> summary.txt
touch done
