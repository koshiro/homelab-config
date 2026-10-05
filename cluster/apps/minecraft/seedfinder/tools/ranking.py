#!/usr/bin/env python3
"""Ranking final: puntaje v2 (top.db de runner2) + bonus de spawners verificados con Paper (spawners.jsonl).
Las semillas aún sin verificar se marcan con '?'. Uso: python3 ranking.py /work/runs/r2 --top 15
"""
import argparse, json, os, sqlite3


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("run"); ap.add_argument("--top", type=int, default=15)
    a = ap.parse_args()
    sp = {}
    p = os.path.join(a.run, "spawners.jsonl")
    if os.path.exists(p):
        for l in open(p):
            if l.strip():
                r = json.loads(l); sp[r["seed"]] = r
    rows = sqlite3.connect(os.path.join(a.run, "top.db")).execute(
        "select seed, score, info from top order by score desc limit 300").fetchall()
    res = []
    for seed, score, info in rows:
        s = sp.get(seed)
        res.append((score + (s["bonus"] if s else 0), seed, score, json.loads(info), s))
    res.sort(key=lambda r: r[0], reverse=True)
    st = json.load(open(os.path.join(a.run, "stats.json")))
    print(f"evaluadas {st['evaluadas']} | pasan filtros {st['pasan']} | spawners verificados {len(sp)}")
    print(f"{'#':>3} {'semilla':>21} {'total':>6} {'v2':>6} {'spw':>5}  aldea(n<500) trial outpost mansion sulfur "
          f"tipos700 fam500 R10  grupos de spawners")
    for i, (tot, seed, score, f, s) in enumerate(res[:a.top], 1):
        g = "?" if not s else (" ".join(f"{k}@{v['dist']}m({','.join(v['mobs'])})" for k, v in s["grupos"].items())
                              or f"ninguno ({s['spawners']} sueltos)")
        print(f"{i:>3} {seed:>21} {tot:6.1f} {score:6.1f} {(s['bonus'] if s else 0):5.1f}  "
              f"{f['aldea']:>5}({f['aldeas_500']}) {f['trial']:>5} {str(f['outpost']):>7} {str(f['mansion']):>7} "
              f"{str(f['sulfur']):>6} {f['tipos_700']:>8} {f['familias_500']:>6} {str(f['r10']):>4}  {g}")
        print(f"{'':>30} biomas: {', '.join(f'{k} {v}' for k, v in list(f['familias'].items())[:12])}")


if __name__ == "__main__":
    main()
