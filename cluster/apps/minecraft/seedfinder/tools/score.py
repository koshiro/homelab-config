#!/usr/bin/env python3
"""Puntaje de semillas desde features.db (sin volver a buscar). Perfil 'familia' (2026-10-04):
variedad de biomas cercanos con mucho peso; Sulfur Caves y Trial Chambers cercanos muy valorados.

Por estructura: valor del tipo × utilidad(distancia) × rendimiento decreciente (1, ½, ¼… para repetidas).
Componentes normalizados a percentiles (0–1) y combinados con PESOS; además se marca el frente de Pareto
en (inicio, biomas, exploración). Uso: python3 score.py /work/runs/r1/features.db --top 30 --json top.json
"""
import argparse, bisect, json, math, sqlite3

# valor por tipo y curva de distancia: ("exp", λ) decae; ("banda", ideal_min, ideal_max) óptimo en un rango
STRUCT = {
    "village":          (100, ("exp", 450)),
    "trial_chambers":   (90,  ("exp", 500)),
    "desert_pyramid":   (60,  ("exp", 600)),
    "jungle_pyramid":   (60,  ("exp", 600)),
    "pillager_outpost": (55,  ("exp", 600)),
    "shipwreck":        (45,  ("exp", 450)),
    "trail_ruins":      (40,  ("exp", 600)),
    "ruined_portal":    (35,  ("exp", 450)),
    "igloo":            (30,  ("exp", 700)),
    "swamp_hut":        (25,  ("exp", 700)),
    "buried_treasure":  (20,  ("exp", 400)),
    "monument":         (30,  ("exp", 900)),
    "mansion":          (55,  ("exp", 1500)),
    "stronghold":       (60,  ("banda", 500, 2500)),
    "ancient_city":     (50,  ("banda", 400, 1500)),   # muy cerca de la base asusta (Warden)
    "mineshaft":        (4,   ("exp", 300)),
    "ocean_ruin":       (4,   ("exp", 300)),
}
EXPLORE_MIN = 1000          # estructuras más lejos que esto cuentan como "exploración"
PESOS = {"inicio": 0.30, "biomas": 0.30, "especiales": 0.25, "exploracion": 0.15}


def utilidad(curva, d):
    if curva[0] == "exp":
        return math.exp(-d / curva[1])
    lo, hi = curva[1], curva[2]
    if d < lo:
        return 0.3 + 0.7 * d / lo
    return 1.0 if d <= hi else math.exp(-(d - hi) / 800)


def componentes(structs, b):
    por_tipo = {}
    for t, x, z in structs:
        d = math.hypot(x, z)
        if t in STRUCT:
            por_tipo.setdefault(t, []).append(d)
    inicio = explor = 0.0
    for t, ds in por_tipo.items():
        v, curva = STRUCT[t]
        cerca = sorted((utilidad(curva, d) for d in ds if d < EXPLORE_MIN), reverse=True)
        lejos = sorted((1.0 for d in ds if d >= EXPLORE_MIN), reverse=True)
        inicio += sum(v * u * 0.5 ** i for i, u in enumerate(cerca))
        explor += sum(v * 0.5 ** i for i, _ in enumerate(lejos)) if t not in ("mineshaft", "ocean_ruin") else 0
    trial = min(por_tipo.get("trial_chambers", [9e9]))
    sulfur = b["sulfur_dist"] if b["sulfur_dist"] >= 0 else 9e9
    especiales = 90 * math.exp(-trial / 500) + 90 * math.exp(-sulfur / 500)
    biomas = b["biomes_near"] * 4 + b["biomes_far"] * 3 + b["entropy_far"] * 15
    penal = 0.0
    if b["land_near"] < 0.6:
        penal += (0.6 - b["land_near"]) * 1.5          # base con mucho mar o río
    dd = b["deep_dark_dist"]
    if 0 <= dd < 250:
        penal += 0.15                                  # Deep Dark bajo la base
    return {"inicio": inicio, "biomas": biomas, "especiales": especiales, "exploracion": explor}, penal, {
        "aldeas_500": sum(1 for d in por_tipo.get("village", []) if d < 500),
        "trial_m": round(trial) if trial < 9e9 else None, "sulfur_m": round(sulfur) if sulfur < 9e9 else None,
        "biomas_300": b["biomes_near"], "biomas_600": b["biomes_far"], "tierra_300": round(b["land_near"], 2),
        "tipos_1km": len({t for t, ds in por_tipo.items() for d in ds if d < 1000 and t not in ("mineshaft", "ocean_ruin")}),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("db"); ap.add_argument("--top", type=int, default=20); ap.add_argument("--json")
    a = ap.parse_args()
    rows = []
    for seed, s, b in sqlite3.connect(a.db).execute("select seed, structures, biomes from seeds"):
        c, penal, info = componentes(json.loads(s), json.loads(b))
        rows.append({"seed": seed, "c": c, "penal": penal, "info": info})
    if not rows:
        print("sin datos"); return
    orden = {k: sorted(r["c"][k] for r in rows) for k in PESOS}
    for r in rows:
        r["p"] = {k: bisect.bisect_right(orden[k], r["c"][k]) / len(rows) for k in PESOS}
        r["score"] = round(sum(PESOS[k] * r["p"][k] for k in PESOS) - r["penal"], 4)
    rows.sort(key=lambda r: r["score"], reverse=True)
    cand = rows[:5000]                                         # Pareto (inicio, biomas, exploración) entre los mejores
    for r in cand:
        r["pareto"] = not any(all(o["p"][k] >= r["p"][k] for k in ("inicio", "biomas", "exploracion")) and
                              any(o["p"][k] > r["p"][k] for k in ("inicio", "biomas", "exploracion")) for o in cand if o is not r)
    print(f"{len(rows)} semillas puntuadas. Top {a.top}:")
    print(f"{'#':>3} {'semilla':>21} {'puntaje':>7} {'inic':>5} {'biom':>5} {'espec':>5} {'expl':>5} P  aldeas<500 trial sulfur biomas300/600 tierra tipos<1km")
    for i, r in enumerate(rows[:a.top], 1):
        p, f = r["p"], r["info"]
        print(f"{i:>3} {r['seed']:>21} {r['score']:>7.3f} {p['inicio']:>5.2f} {p['biomas']:>5.2f} {p['especiales']:>5.2f} {p['exploracion']:>5.2f} "
              f"{'★' if r.get('pareto') else ' '}  {f['aldeas_500']:>10} {str(f['trial_m']):>5} {str(f['sulfur_m']):>6} {f['biomas_300']:>6}/{f['biomas_600']:<6} {f['tierra_300']:>6} {f['tipos_1km']:>9}")
    if a.json:
        json.dump(rows[:max(a.top, 200)], open(a.json, "w"), indent=1)


if __name__ == "__main__":
    main()
