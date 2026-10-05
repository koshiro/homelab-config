#!/usr/bin/env python3
"""Búsqueda v2: candidatas (MCSeedFinder find, starter-v3) → estructuras a 2 km + biomas (biomefeat2) →
puntaje v2 (scoring2.py) en el momento. Solo se guardan las semillas que pasan los filtros duros, y la tabla se
recorta a las TOPN mejores; del resto quedan solo contadores (stats.json). Cada minuto escribe top.txt.

Uso (en el pod seedfinder, desacoplado de la sesión: la red puede ser intermitente):
  cd /work && nohup python3 runner2.py --run /work/runs/r2 > runs/r2.log 2>&1 </dev/null &
Detener: kill -INT <pid del proceso principal> (guarda antes de salir).
"""
import argparse, json, multiprocessing as mp, os, random, signal, sqlite3, subprocess, sys, threading, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from scoring2 import evaluar, FILTROS

FIND = "/work/MCseedFinder/target/release/mcseed-finder"          # build normal: búsqueda
FULL = "/work/MCseedFinder-full/target/release/mcseed-finder"     # HIT_CAPACITY=4096: todas las coordenadas
BIOME = "/work/biomefeat2"
TYPES = ["village", "desert_pyramid", "jungle_pyramid", "igloo", "swamp_hut", "pillager_outpost", "ancient_city",
         "monument", "mansion", "ruined_portal", "shipwreck", "trial_chambers", "trail_ruins", "stronghold",
         "buried_treasure"]                                         # sin mineshaft ni ocean_ruin (no puntúan)
RADIUS = 2000
GUARDAR_R = 1500        # coordenadas que se guardan de las semillas del top (las mansiones cuentan hasta 2 km)
TOPN = 1000
BATCH = 500


def features_config(path):
    conds = [{"type": "structure_near", "any_of": [t], "radius": RADIUS, "anchor": "origin", "min_count": 100000} for t in TYPES]
    json.dump({"version": "26.2", "conditions": [{"type": "any", "conditions": conds}]}, open(path, "w"))


def worker(inq, outq, cfg):
    signal.signal(signal.SIGINT, signal.SIG_IGN)
    biome = subprocess.Popen([BIOME], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
    while True:
        seed = inq.get()
        try:
            out = subprocess.run([FULL, "check", str(seed), "--config", cfg, "--format", "jsonl"],
                                 capture_output=True, text=True, timeout=60).stdout
            d = json.loads(out.splitlines()[0])
            structs = [[h["name"], h["position"]["x"], h["position"]["z"]]
                       for c in d["filter"]["children"][0]["children"] for h in c.get("hits", [])]
            biome.stdin.write(f"{seed}\n"); biome.stdin.flush()
            bio = json.loads(biome.stdout.readline())
            e = evaluar(structs, bio)
            if e["ok"]:
                near = [s for s in structs if s[0] == "mansion" or s[1] ** 2 + s[2] ** 2 <= GUARDAR_R ** 2]
                outq.put((seed, e, near, bio))
            else:
                outq.put((seed, e, None, None))
        except Exception as ex:  # una semilla problemática no detiene la corrida
            print(f"[worker] semilla {seed}: {ex}", file=sys.stderr, flush=True)
            outq.put((seed, None, None, None))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--run", required=True)
    ap.add_argument("--config", default="/work/starter-v3.json")
    ap.add_argument("--workers", type=int, default=7)
    ap.add_argument("--search-threads", type=int, default=2)
    a = ap.parse_args()
    os.makedirs(a.run, exist_ok=True)
    cfg = os.path.join(a.run, "features.json"); features_config(cfg)
    db = sqlite3.connect(os.path.join(a.run, "top.db"))
    db.execute("create table if not exists top(seed integer primary key, score real, info text, structures text,"
               " biomes text, ts real)")
    sp = os.path.join(a.run, "stats.json")
    stats = json.load(open(sp)) if os.path.exists(sp) else {
        "candidatas": 0, "evaluadas": 0, "errores": 0, "pasan": 0, "fallo": {k: 0 for k in FILTROS},
        "solo_falla": {k: 0 for k in FILTROS}, "hist": {}, "minutos": 0}
    base = json.load(open(a.config))
    inq, outq = mp.Queue(maxsize=5000), mp.Queue()
    for _ in range(a.workers):
        mp.Process(target=worker, args=(inq, outq, cfg), daemon=True).start()

    stop = threading.Event()
    signal.signal(signal.SIGINT, lambda *_: stop.set())
    signal.signal(signal.SIGTERM, lambda *_: stop.set())

    def searcher():
        while not stop.is_set():
            while inq.qsize() > 3 * BATCH and not stop.is_set():
                time.sleep(1)
            base["search"]["random_seed"] = random.SystemRandom().getrandbits(48)
            base["search"]["results"] = BATCH
            path = os.path.join(a.run, "search.json"); json.dump(base, open(path, "w"))
            r = subprocess.run([FIND, "find", "--config", path, "--threads", str(a.search_threads), "--accelerator", "cpu",
                                "--format", "jsonl"], capture_output=True, text=True)
            for l in r.stdout.splitlines():
                if l.strip():
                    inq.put(json.loads(l)["seed"]); stats["candidatas"] += 1
            if r.returncode not in (0, 1):
                print(f"[runner] find salió con {r.returncode}: {r.stderr[-300:]}", flush=True); time.sleep(10)
    threading.Thread(target=searcher, daemon=True).start()

    def guardar():
        db.execute(f"delete from top where seed not in (select seed from top order by score desc limit {TOPN})")
        db.commit()
        json.dump(stats, open(sp + ".tmp", "w"), indent=1); os.replace(sp + ".tmp", sp)
        rows = db.execute("select seed, score, info from top order by score desc limit 30").fetchall()
        with open(os.path.join(a.run, "top.txt.tmp"), "w") as fh:
            fh.write(f"evaluadas {stats['evaluadas']} | pasan {stats['pasan']} | en tabla {len(rows)}+\n")
            for i, (s, sc, inf) in enumerate(rows, 1):
                fh.write(f"{i:>3} {s:>21} {sc:6.1f} {inf}\n")
        os.replace(os.path.join(a.run, "top.txt.tmp"), os.path.join(a.run, "top.txt"))
        # para spawners.py (otro nodo): JSON atómico en vez de leer SQLite por NFS mientras se escribe
        fin = db.execute("select seed, score from top order by score desc limit 300").fetchall()
        json.dump(fin, open(os.path.join(a.run, "finalistas.json.tmp"), "w"))
        os.replace(os.path.join(a.run, "finalistas.json.tmp"), os.path.join(a.run, "finalistas.json"))

    t0 = last = time.time(); n0 = stats["evaluadas"]
    print(f"[runner2] inicio run={a.run} workers={a.workers} filtros={list(FILTROS)}", flush=True)
    while not stop.is_set():
        while not outq.empty():
            seed, e, near, bio = outq.get()
            stats["evaluadas"] += 1
            if e is None:
                stats["errores"] += 1; continue
            for k in e["fallos"]:
                stats["fallo"][k] += 1
            if len(e["fallos"]) == 1:
                stats["solo_falla"][e["fallos"][0]] += 1
            b = str(int(e["score"] // 10 * 10)); stats["hist"][b] = stats["hist"].get(b, 0) + 1
            if e["ok"]:
                stats["pasan"] += 1
                db.execute("insert or replace into top values (?,?,?,?,?,?)",
                           (seed, e["score"], json.dumps(e["info"], ensure_ascii=False, separators=(",", ":")),
                            json.dumps(near, separators=(",", ":")), json.dumps(bio, separators=(",", ":")), time.time()))
        if time.time() - last > 60:
            el = time.time() - t0; last = time.time(); stats["minutos"] += 1
            guardar()
            print(f"[runner2] {el/60:.0f} min | candidatas {stats['candidatas']} | evaluadas {stats['evaluadas']} "
                  f"({(stats['evaluadas'] - n0)/el:.1f}/s) | pasan {stats['pasan']} | cola {inq.qsize()}", flush=True)
        time.sleep(0.2)
    guardar()
    for p in mp.active_children():
        p.terminate()                 # biomefeat de cada worker sale solo al cerrarse su stdin
    print("[runner2] detenido, tabla y stats guardadas", flush=True)
    os._exit(0)


if __name__ == "__main__":
    main()
