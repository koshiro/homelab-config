#!/usr/bin/env python3
"""Puntaje v2 (2026-10-05): diversidad en el menor espacio posible, en puntos absolutos (sin percentiles).

Lo que falló en v1: los percentiles aplastaban el top (todo 0,96–1,00); contaba ríos, playas y variantes de océano
como biomas distintos; Trial Chambers, portales y naufragios (decenas por km²) inflaban el puntaje; y las
estructuras a 1–2 km sumaban "exploración", lo contrario de un mundo compacto.

Ahora:
- Estructuras: cada TIPO cuenta una vez (la más cercana), con valor por rareza/interés y utilidad 1 hasta d_full
  y lineal a 0 en d_zero. Solo las aldeas suman 2.ª y 3.ª instancia.
- Biomas: familias jugables (plains + sunflower_plains = una), con valor por rareza; ríos y playas no cuentan.
- Cuevas: sulfur, lush y dripstone suman; deep_dark o ciudad antigua bajo la base descartan la semilla.
- R10: radio que contiene 10 atracciones distintas (estructura o familia de bioma de valor >= 3): bonus si es chico.
- Filtros duros (FILTROS): una semilla que no los cumple no se guarda.
- Spawners (dungeons/minas) no se pueden predecir sin generar el terreno: los suma spawners.py tras verificar con Paper.
"""
import math

# tipo: (valor, d_full, d_zero) — utilidad 1 hasta d_full, lineal a 0 en d_zero
STRUCT = {
    "village":          (12, 100, 500),
    "mansion":          (15, 600, 2000),
    "pillager_outpost": (10, 250, 900),
    "jungle_pyramid":   (7, 250, 800),
    "desert_pyramid":   (6, 250, 800),
    "igloo":            (6, 250, 800),
    "swamp_hut":        (6, 250, 800),
    "trial_chambers":   (6, 150, 500),
    "monument":         (6, 400, 1000),
    "trail_ruins":      (5, 250, 800),
    "shipwreck":        (3, 150, 500),
    "ruined_portal":    (3, 150, 500),
    "buried_treasure":  (2, 150, 500),
}
VILLAGE_EXTRA = (6, 3)              # 2.ª y 3.ª aldea (misma curva)
# banda: (valor, d_min_ideal, d_max_ideal, d_zero) — demasiado cerca también resta utilidad
BANDA = {
    "ancient_city": (7, 400, 1000, 1500),
    "stronghold":   (6, 300, 1200, 2000),
}

# familia: (valor, biomas). Ríos, playas y stony_shore no cuentan.
FAMILIAS = {
    "plains":        (1, ["plains", "sunflower_plains"]),
    "forest":        (1, ["forest"]),
    "flower_forest": (3, ["flower_forest"]),
    "birch":         (2, ["birch_forest", "old_growth_birch_forest"]),
    "dark_forest":   (3, ["dark_forest"]),
    "pale_garden":   (5, ["pale_garden"]),
    "taiga":         (2, ["taiga", "old_growth_pine_taiga", "old_growth_spruce_taiga"]),
    "snowy":         (3, ["snowy_plains", "snowy_taiga"]),
    "ice_spikes":    (5, ["ice_spikes"]),
    "desert":        (3, ["desert"]),
    "badlands":      (5, ["badlands", "eroded_badlands", "wooded_badlands"]),
    "savanna":       (2, ["savanna", "savanna_plateau", "windswept_savanna"]),
    "jungle":        (3, ["jungle", "sparse_jungle"]),
    "bamboo_jungle": (4, ["bamboo_jungle"]),
    "swamp":         (2, ["swamp"]),
    "mangrove":      (4, ["mangrove_swamp"]),
    "mushroom":      (7, ["mushroom_fields"]),
    "cherry":        (4, ["cherry_grove"]),
    "meadow":        (2, ["meadow"]),
    "hills":         (2, ["windswept_hills", "windswept_gravelly_hills", "windswept_forest"]),
    "peaks":         (3, ["jagged_peaks", "frozen_peaks", "stony_peaks", "snowy_slopes", "grove"]),
    "ocean":         (1, ["ocean", "deep_ocean", "cold_ocean", "deep_cold_ocean", "lukewarm_ocean",
                          "deep_lukewarm_ocean", "frozen_ocean", "deep_frozen_ocean"]),
    "warm_ocean":    (3, ["warm_ocean", "deep_warm_ocean"]),
}
BIOMA_CURVA = (150, 700)
CUEVAS = {"sulfur_caves": (8, 150, 500), "lush_caves": (4, 150, 600), "dripstone_caves": (3, 150, 600)}

FILTROS = {
    "aldea_250":     lambda f: f["d"]["village"] <= 250,
    "2_aldeas_500":  lambda f: f["aldeas_500"] >= 2,
    "trial_400":     lambda f: f["d"]["trial_chambers"] <= 400,
    "sulfur_400":    lambda f: f["d"]["sulfur_caves"] <= 400,
    "outpost_o_mansion": lambda f: f["d"]["pillager_outpost"] <= 800 or f["d"]["mansion"] <= 1500,
    "tierra_75":     lambda f: f["land200"] >= 0.75,
    "sin_deep_dark_250": lambda f: f["d"]["deep_dark"] > 250 and f["d"]["ancient_city"] > 250,
    "7_tipos_700":   lambda f: f["tipos_700"] >= 7,
    "6_familias_500": lambda f: f["familias_500"] >= 6,
}
INF = 9e9


def lineal(d, d_full, d_zero):
    if d <= d_full:
        return 1.0
    return max(0.0, (d_zero - d) / (d_zero - d_full))


def banda(d, lo, hi, zero):
    if d < lo:
        return d / lo
    return 1.0 if d <= hi else max(0.0, (zero - d) / (zero - hi))


def evaluar(structs, bio):
    """structs: [[tipo, x, z], ...]; bio: salida de biomefeat2. Devuelve dict con score, ok, fallos e info."""
    ds = {}
    for t, x, z in structs:
        ds.setdefault(t, []).append(math.hypot(x, z))
    for v in ds.values():
        v.sort()
    d = {t: ds.get(t, [INF])[0] for t in list(STRUCT) + list(BANDA)}
    surf, cave = bio["surf"], bio["cave"]
    fam_d = {f: min((surf[b] for b in bs if b in surf), default=INF) for f, (_, bs) in FAMILIAS.items()}
    for c in CUEVAS:
        d[c] = cave.get(c, INF)
    d["deep_dark"] = cave.get("deep_dark", INF)

    pts = {}
    s_est = 0.0
    for t, (v, a, b) in STRUCT.items():
        u = lineal(d[t], a, b)
        if u: pts[t] = round(v * u, 1); s_est += v * u
    for i, extra in enumerate(VILLAGE_EXTRA, 1):
        if len(ds.get("village", [])) > i:
            s_est += extra * lineal(ds["village"][i], *STRUCT["village"][1:])
    for t, (v, lo, hi, zero) in BANDA.items():
        s_est += v * banda(d[t], lo, hi, zero)
    s_bio = sum(v * lineal(fam_d[f], *BIOMA_CURVA) for f, (v, _) in FAMILIAS.items())
    s_cue = sum(v * lineal(d[c], a, b) for c, (v, a, b) in CUEVAS.items())

    # R10: radio con 10 atracciones distintas (estructuras de valor >= 3 + familias de valor >= 3 + cuevas)
    atr = sorted([d[t] for t, (v, *_) in STRUCT.items() if v >= 3] + [d[t] for t in BANDA] +
                 [fam_d[f] for f, (v, _) in FAMILIAS.items() if v >= 3] + [d[c] for c in CUEVAS])
    r10 = atr[9] if len(atr) > 9 else INF
    s_comp = 20 * lineal(r10, 300, 900)

    f = {
        "d": d, "land200": bio["land200"],
        "aldeas_500": sum(1 for x in ds.get("village", []) if x <= 500),
        "tipos_700": sum(1 for t in STRUCT if d[t] <= 700) + sum(1 for t in BANDA if d[t] <= 700),
        "familias_500": sum(1 for f_, (v, _) in FAMILIAS.items() if v >= 2 and fam_d[f_] <= 500),
    }
    fallos = [k for k, fn in FILTROS.items() if not fn(f)]
    score = s_est + s_bio + s_cue + s_comp
    info = {
        "aldea": round(d["village"]), "aldeas_500": f["aldeas_500"], "trial": round(d["trial_chambers"]),
        "outpost": r(d["pillager_outpost"]), "mansion": r(d["mansion"]), "sulfur": r(d["sulfur_caves"]),
        "tipos_700": f["tipos_700"], "familias_500": f["familias_500"], "r10": r(r10), "tierra": bio["land200"],
        "familias": {k: round(v) for k, v in sorted(fam_d.items(), key=lambda kv: kv[1]) if v <= 700},
        "partes": {"estructuras": round(s_est, 1), "biomas": round(s_bio, 1), "cuevas": round(s_cue, 1),
                   "compacto": round(s_comp, 1)},
    }
    return {"score": round(score, 2), "ok": not fallos, "fallos": fallos, "info": info}


def r(x):
    return None if x >= INF else round(x)
