#!/usr/bin/env python3
"""Etapa 3: spawners reales de los finalistas (dungeons y minas no se pueden predecir sin generar el terreno).

Corre como sidecar del Paper de seed-verifier.yaml (comparte /data, habla por RCON). Para cada semilla del top de
la corrida que aún no esté verificada: crea el mundo con Multiverse, pregenera RADIO bloques con Chunky, lo
descarga, lee los .mca y busca block entities `minecraft:mob_spawner` (nombre en 26.x). Solo cuentan los de
dungeons (esqueleto > zombi > araña); arañas de cueva y trial spawners no. Luego borra el mundo.

Grupo activable: un jugador activa un spawner a <= 16 bloques (esfera). Dos o tres spawners forman grupo si existe
un punto a <= 16 de todos (radio de la esfera mínima que los contiene <= 16). Resultado en <run>/spawners.jsonl.
"""
import argparse, glob, itertools, json, math, os, shutil, socket, struct, time, zlib

RADIO = 400
ACTIVACION = 16.0
# Valor del grupo = BASE[tamaño] × promedio del peso de sus mobs × factor_dist. Esqueletos primero (huesos,
# flechas, más fáciles de juntar en granja), luego zombis; arañas valen poco (miden 2x1 y escalan paredes).
# Las arañas de cueva (minas) se descartan: muy comunes y malas para granjas de XP.
BASE = {3: 25, 2: 12}
MOB = {"skeleton": 1.0, "zombie": 0.75, "spider": 0.4}
DESCARTAR = {"cave_spider"}


# --- RCON mínimo ---
class Rcon:
    def __init__(self, host, port, pw):
        self.s = socket.create_connection((host, port), timeout=600)
        self._send(3, pw)

    def _send(self, kind, body):
        data = struct.pack("<ii", 1, kind) + body.encode() + b"\0\0"
        self.s.sendall(struct.pack("<i", len(data)) + data)
        n = struct.unpack("<i", self._recv(4))[0]
        return self._recv(n)[8:-2].decode(errors="replace")

    def _recv(self, n):
        b = b""
        while len(b) < n:
            c = self.s.recv(n - len(b))
            if not c:
                raise ConnectionError("rcon cerrado")
            b += c
        return b

    def cmd(self, c):
        return self._send(2, c)


# --- NBT mínimo (solo lectura) ---
def nbt_leer(buf):
    pos = 0

    def u(fmt):
        nonlocal pos
        v = struct.unpack_from(">" + fmt, buf, pos); pos += struct.calcsize(">" + fmt)
        return v[0]

    def string():
        nonlocal pos
        n = u("H"); s = buf[pos:pos + n].decode("utf-8", "replace"); pos += n
        return s

    def payload(t):
        nonlocal pos
        if t == 1: return u("b")
        if t == 2: return u("h")
        if t == 3: return u("i")
        if t == 4: return u("q")
        if t == 5: return u("f")
        if t == 6: return u("d")
        if t == 7: n = u("i"); pos += n; return None
        if t == 8: return string()
        if t == 9:
            et = u("b"); n = u("i")
            return [payload(et) for _ in range(n)]
        if t == 10:
            d = {}
            while True:
                tt = u("b")
                if tt == 0: return d
                k = string(); d[k] = payload(tt)
        if t == 11: n = u("i"); pos += 4 * n; return None
        if t == 12: n = u("i"); pos += 8 * n; return None
        raise ValueError(f"tag {t}")

    t = u("b"); string()
    return payload(t)


def spawners_en_region(path):
    out = []
    with open(path, "rb") as fh:
        data = fh.read()
    for i in range(1024):
        off = int.from_bytes(data[i * 4:i * 4 + 3], "big") * 4096
        if not off:
            continue
        n = struct.unpack_from(">i", data, off)[0]; comp = data[off + 4]
        raw = data[off + 5:off + 4 + n]
        if comp == 2: raw = zlib.decompress(raw)
        elif comp == 1:
            import gzip; raw = gzip.decompress(raw)
        elif comp != 3:
            continue
        try:
            ch = nbt_leer(raw)
        except Exception:
            continue
        for be in ch.get("block_entities") or []:
            if be.get("id") in ("minecraft:mob_spawner", "minecraft:spawner"):   # 26.x usa mob_spawner
                mob = (((be.get("SpawnData") or {}).get("entity") or {}).get("id") or "?").replace("minecraft:", "")
                out.append((be["x"], be["y"], be["z"], mob))
    return out


def radio_esfera(pts):
    """Radio de la esfera mínima que contiene 2 o 3 puntos (3D)."""
    if len(pts) == 2:
        return math.dist(*pts) / 2
    a, b, c = (tuple(map(float, p)) for p in pts)
    lados = sorted([(math.dist(a, b), (a, b)), (math.dist(b, c), (b, c)), (math.dist(a, c), (a, c))])
    la, lb, lc = (x[0] for x in lados)
    if lc * lc >= la * la + lb * lb:      # obtuso o recto: basta el lado mayor
        return lc / 2
    s = (la + lb + lc) / 2
    area = math.sqrt(max(s * (s - la) * (s - lb) * (s - lc), 1e-9))
    return la * lb * lc / (4 * area)      # circunradio


def factor_dist(d):
    """1 hasta 150 m del origen; baja lineal hasta 40 % en RADIO."""
    return 1.0 if d <= 150 else max(0.4, 1 - 0.6 * (d - 150) / (RADIO - 150))


def grupos(sp):
    """Grupo de 3 y de 2 de mayor valor (mob × distancia) entre spawners activables a la vez."""
    res = {}
    for k in (3, 2):
        mejor = None
        for comb in itertools.combinations(sp, k):
            if any(math.dist(p[:3], q[:3]) > 2 * ACTIVACION for p, q in itertools.combinations(comb, 2)):
                continue
            if radio_esfera([p[:3] for p in comb]) <= ACTIVACION:
                cx = sum(p[0] for p in comb) / k; cz = sum(p[2] for p in comb) / k
                d = math.hypot(cx, cz)
                mobs = [p[3] for p in comb]
                v = BASE[k] * sum(MOB.get(m, 0.4) for m in mobs) / k * factor_dist(d)
                if mejor is None or v > mejor["valor"]:
                    mejor = {"valor": round(v, 1), "dist": round(d), "mobs": mobs,
                             "centro": [round(cx), round(sum(p[1] for p in comb) / k), round(cz)]}
        if mejor:
            res[f"x{k}"] = mejor
    return res


def bonus(g):
    """Puntos que suma al puntaje v2: el grupo de mayor valor."""
    return max((v["valor"] for v in g.values()), default=0.0)


def esperar_chunky(rc, mundo, limite=1800):
    t0 = time.time()
    while time.time() - t0 < limite:
        time.sleep(10)
        r = rc.cmd("chunky progress")
        if "No tasks" in r:               # Chunky responde "No tasks running." al terminar
            return True
    return False


def verificar(rc, seed, data):
    mundo = f"sv{abs(seed) % 10**8}"
    carpeta = os.path.join(data, "world", "dimensions", "minecraft", mundo)   # Multiverse en 26.x
    shutil.rmtree(carpeta, ignore_errors=True)
    print(rc.cmd(f"mv create {mundo} normal --seed {seed}"), flush=True)
    for c in (f"chunky world {mundo}", "chunky center 0 0", f"chunky radius {RADIO}", "chunky shape square",
              "chunky start"):
        rc.cmd(c)
    t0 = time.time(); ok = esperar_chunky(rc, mundo)
    rc.cmd(f"mv unload {mundo}"); time.sleep(5)
    sp = []
    for f in glob.glob(os.path.join(carpeta, "region", "*.mca")):
        sp += spawners_en_region(f)
    rc.cmd(f"mv remove {mundo}")
    shutil.rmtree(carpeta, ignore_errors=True)
    sp = [s for s in sp if math.hypot(s[0], s[2]) <= RADIO + 32]
    dungeons = [s for s in sp if s[3] not in DESCARTAR]
    g = grupos(dungeons)
    return {"seed": seed, "completo": ok, "segundos": round(time.time() - t0), "spawners": len(dungeons),
            "descartados": len(sp) - len(dungeons), "mobs": sorted({s[3] for s in dungeons}), "grupos": g,
            "bonus": bonus(g), "lista": sorted(dungeons, key=lambda s: math.hypot(s[0], s[2]))}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--run", default="/work/runs/r2")
    ap.add_argument("--data", default="/data")
    ap.add_argument("--top", type=int, default=100, help="verificar las N mejores (por puntaje v2) aún sin verificar")
    a = ap.parse_args()
    pw = os.environ["RCON_PASSWORD"]
    hecho_path = os.path.join(a.run, "spawners.jsonl")
    while True:
        hechos = set()
        if os.path.exists(hecho_path):
            hechos = {json.loads(l)["seed"] for l in open(hecho_path) if l.strip()}
        try:
            top = [s for s, _ in json.load(open(os.path.join(a.run, "finalistas.json")))[:a.top]]
        except (OSError, ValueError) as e:
            print(f"[spawners] sin finalistas.json aún: {e}", flush=True); time.sleep(120); continue
        pend = [s for s in top if s not in hechos]
        if not pend:
            print(f"[spawners] top {a.top} verificado; espero nuevas finalistas", flush=True)
            time.sleep(600); continue
        try:
            rc = Rcon("127.0.0.1", 25575, pw)
            res = verificar(rc, pend[0], a.data)
        except (OSError, ConnectionError) as e:
            print(f"[spawners] rcon: {e}", flush=True); time.sleep(60); continue
        with open(hecho_path, "a") as fh:
            fh.write(json.dumps(res, separators=(",", ":")) + "\n")
        print(f"[spawners] {res['seed']}: {res['spawners']} spawners, grupos {res['grupos']}, "
              f"bonus {res['bonus']} ({res['segundos']} s)", flush=True)


if __name__ == "__main__":
    main()
