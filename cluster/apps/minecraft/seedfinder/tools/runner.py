#!/usr/bin/env python3
"""Búsqueda de semillas: candidatas (MCSeedFinder find) → características (estructuras a 2 km + biomas) → SQLite.

Separa la generación de datos del puntaje: score.py lee la base y puede cambiar de perfil sin volver a buscar.
Uso (en el pod seedfinder): python3 runner.py --run /work/runs/r1 --workers 7 --search-threads 1
"""
import argparse, json, multiprocessing as mp, os, random, sqlite3, subprocess, sys, threading, time

FIND = "/work/MCseedFinder/target/release/mcseed-finder"          # build normal: búsqueda
FULL = "/work/MCseedFinder-full/target/release/mcseed-finder"     # HIT_CAPACITY=4096: todas las coordenadas
BIOME = "/work/biomefeat"
TYPES = ["village", "desert_pyramid", "jungle_pyramid", "igloo", "swamp_hut", "pillager_outpost", "ancient_city",
         "monument", "mansion", "ruined_portal", "shipwreck", "trial_chambers", "trail_ruins", "mineshaft",
         "stronghold", "buried_treasure", "ocean_ruin"]
RADIUS = 2000


def features_config(path):
    conds = [{"type": "structure_near", "any_of": [t], "radius": RADIUS, "anchor": "origin", "min_count": 100000} for t in TYPES]
    json.dump({"version": "26.2", "conditions": [{"type": "any", "conditions": conds}]}, open(path, "w"))


def worker(inq, outq, cfg):
    biome = subprocess.Popen([BIOME], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
    while True:
        seed = inq.get()
        if seed is None:
            break
        try:
            out = subprocess.run([FULL, "check", str(seed), "--config", cfg, "--format", "jsonl"],
                                 capture_output=True, text=True, timeout=60).stdout
            d = json.loads(out.splitlines()[0])
            structs = [[h["name"], h["position"]["x"], h["position"]["z"]]
                       for c in d["filter"]["children"][0]["children"] for h in c.get("hits", [])]
            biome.stdin.write(f"{seed}\n"); biome.stdin.flush()
            b = json.loads(biome.stdout.readline())
            outq.put((seed, json.dumps(structs, separators=(",", ":")), json.dumps(b, separators=(",", ":"))))
        except Exception as e:  # una semilla problemática no detiene la corrida
            print(f"[worker] semilla {seed}: {e}", file=sys.stderr, flush=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--run", required=True)
    ap.add_argument("--config", default="/work/starter-v2.json")
    ap.add_argument("--workers", type=int, default=7)
    ap.add_argument("--search-threads", type=int, default=1)
    a = ap.parse_args()
    os.makedirs(a.run, exist_ok=True)
    cfg = os.path.join(a.run, "features.json"); features_config(cfg)
    db = sqlite3.connect(os.path.join(a.run, "features.db"))
    db.execute("pragma journal_mode=wal")
    db.execute("create table if not exists seeds(seed integer primary key, structures text, biomes text, ts real)")
    base = json.load(open(a.config))
    inq, outq = mp.Queue(maxsize=5000), mp.Queue()
    procs = [mp.Process(target=worker, args=(inq, outq, cfg), daemon=True) for _ in range(a.workers)]
    for p in procs: p.start()
    # MCSeedFinder find se llama en tandas de BATCH resultados, cada una con otra permutación aleatoria
    # (random_seed). Un hilo lee su salida mientras corre (si no, la tubería se llena y find se bloquea).
    BATCH = 500
    stats = {"found": 0}
    def searcher():
        while True:
            while inq.qsize() > 3 * BATCH:
                time.sleep(1)
            base["search"]["random_seed"] = random.SystemRandom().getrandbits(48)
            base["search"]["results"] = BATCH
            path = os.path.join(a.run, "search.json"); json.dump(base, open(path, "w"))
            r = subprocess.run([FIND, "find", "--config", path, "--threads", str(a.search_threads), "--accelerator", "cpu",
                                "--format", "jsonl"], capture_output=True, text=True)
            for l in r.stdout.splitlines():
                if l.strip():
                    inq.put(json.loads(l)["seed"]); stats["found"] += 1
            if r.returncode not in (0, 1):
                print(f"[runner] find salió con {r.returncode}: {r.stderr[-300:]}", flush=True); time.sleep(10)
    threading.Thread(target=searcher, daemon=True).start()
    t0 = last = time.time(); stored = 0
    print(f"[runner] inicio run={a.run} workers={a.workers} tandas de {BATCH}", flush=True)
    while True:
        while not outq.empty():
            db.execute("insert or ignore into seeds values (?,?,?,?)", (*outq.get(), time.time())); stored += 1
        if time.time() - last > 60:
            db.commit(); el = time.time() - t0; last = time.time()
            print(f"[runner] {el/60:.0f} min | candidatas {stats['found']} | analizadas {stored} ({stored/el:.1f}/s) | cola {inq.qsize()}", flush=True)
        time.sleep(0.2)
    db.commit()


if __name__ == "__main__":
    main()
