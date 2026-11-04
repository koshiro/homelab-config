#!/usr/bin/env -S uv run --quiet --no-project --script
# /// script
# requires-python = ">=3.11,<3.14"
# dependencies = ["numpy", "scipy", "shapely>=2.1", "networkx", "rtree", "lxml", "trimesh>=4.4"]
# ///
"""Revisa si un STL o 3MF se puede imprimir en FDM, capa por capa.

ScanRuler no tiene este chequeo: su mapa de espesor mide escaneos, no sólidos.
El flujo es `reverse_export_stl` y después este script.

    revisar_impresion.py pieza.stl
    revisar_impresion.py pieza.stl --abajo 0,-1,0        # otra cara contra la cama
    revisar_impresion.py pieza.stl --orientaciones --carga 0,1,0 --carga 1,0,0
    revisar_impresion.py pieza.stl --json

`--carga` es la dirección de la tracción en un tramo de la pieza, y se repite por tramo. En flexión la tracción corre a
lo largo de la fibra exterior, no en la dirección de la fuerza: un gancho cargado hacia abajo tracciona a lo largo de su
brazo y también a lo largo de su punta.

Convención de ángulo: 0° es pared vertical y 90° es techo plano. "Voladizo de
45°" significa 45° medidos desde la vertical.

Sale con código 1 si hay alguna FALLA. Los umbrales están en Perfil y se
calibran con la impresora real: son punto de partida, no verdad.
"""
from __future__ import annotations

import argparse
import json
import math
import sys
from dataclasses import asdict, dataclass, field

import numpy as np
import shapely
import trimesh
from shapely.geometry import MultiPolygon, Polygon
from shapely.ops import unary_union

VACIO = MultiPolygon()
MITRE = {"join_style": "mitre", "mitre_limit": 5.0}


@dataclass
class Perfil:
    """Valores por defecto: Ender-3 V2 de Daniel, perfil `E3V2-PETG-5-new`."""

    boquilla: float = 0.5
    linea: float = 0.58
    capa: float = 0.16
    primera: float = 0.20
    angulo: float = 45.0  # voladizo admitido sin aviso, desde la vertical
    cama: tuple = (230.0, 225.0, 250.0)
    puente_aviso: float = 10.0  # mm: lo publicado va de 5 a 10; más allá, probar antes
    puente_max: float = 20.0  # mm: de aquí en adelante, partir la luz o rediseñar
    rendija_min: float = 0.30  # mm: rendijas menores tienden a soldarse
    lineas_min: int = 2  # pared bajo esto queda de una sola línea
    capas_min: int = 3  # lámina horizontal bajo esto queda débil
    cordon_min: float = 0.80  # min_bead_width de PrusaSlicer, fracción de boquilla
    rasgo_min: float = 0.20  # min_feature_size de PrusaSlicer, fracción de boquilla
    max_capas: int = 500  # tope de rebanadas: el paso crece en piezas altas

    def pared(self, n: int) -> float:
        """Ancho nominal de n líneas: w + (n-1)s, con s = w - h(1 - pi/4)."""
        return self.linea + (n - 1) * (self.linea - self.capa * (1 - math.pi / 4))


@dataclass
class Evento:
    tipo: str
    z0: float
    z1: float
    caja: tuple  # xmin, ymin, xmax, ymax
    area: float
    medida: float  # vano, profundidad o ancho, en mm
    capas: int = 1

    def texto(self) -> str:
        cx, cy = (self.caja[0] + self.caja[2]) / 2, (self.caja[1] + self.caja[3]) / 2
        return (f"{self.medida:.2f} mm, área {self.area:.1f} mm², "
                f"z {self.z0:.2f}–{self.z1:.2f}, en x {cx:.1f} y {cy:.1f}")


@dataclass
class Hallazgo:
    nivel: str  # FALLA, AVISO u OK
    chequeo: str
    detalle: str


@dataclass
class Informe:
    nombre: str
    hallazgos: list = field(default_factory=list)
    datos: dict = field(default_factory=dict)
    eventos: list = field(default_factory=list)

    def agregar(self, nivel: str, chequeo: str, detalle: str) -> None:
        self.hallazgos.append(Hallazgo(nivel, chequeo, detalle))


def cargar(ruta: str) -> list:
    """Devuelve los cuerpos separados de un STL o 3MF."""
    malla = trimesh.load(ruta, force="mesh", process=True)
    malla.merge_vertices()
    cuerpos = malla.split(only_watertight=False)
    return list(cuerpos) if len(cuerpos) else [malla]


def orientar(malla: trimesh.Trimesh, abajo) -> trimesh.Trimesh:
    """Gira la malla para que la dirección `abajo` apunte a la cama."""
    m = malla.copy()
    if abajo is not None:
        v = np.asarray(abajo, float)
        m.apply_transform(trimesh.geometry.align_vectors(v / np.linalg.norm(v), [0, 0, -1]))
    m.apply_translation([0, 0, -m.bounds[0][2]])
    return m


def desde_capa(c) -> float:
    """Ángulo entre una dirección y el plano de capa: 0 corre por la capa, 90 la cruza."""
    c = np.asarray(c, float)
    return math.degrees(math.asin(min(1.0, abs(c[2]) / np.linalg.norm(c))))


def lado_menor(g) -> float:
    """Lado menor del rectángulo mínimo que contiene la geometría."""
    rect = g.minimum_rotated_rectangle
    if not isinstance(rect, Polygon):
        return 0.0
    c = np.asarray(rect.exterior.coords)
    return float(min(np.linalg.norm(c[i + 1] - c[i]) for i in range(4)))


def angulos_cara(normales: np.ndarray) -> np.ndarray:
    """Ángulo desde la vertical de las caras que miran hacia abajo; 0 en el resto."""
    return np.degrees(np.arcsin(np.clip(-np.minimum(normales[:, 2], 0.0), 0.0, 1.0)))


def mascara_cama(m: trimesh.Trimesh) -> np.ndarray:
    return (m.triangles_center[:, 2] < 0.02) & (m.face_normals[:, 2] < -0.99)


def voladizos(m: trimesh.Trimesh, p: Perfil) -> dict:
    """Área de voladizo por rango de ángulo y sus zonas conexas."""
    ang = angulos_cara(m.face_normals)
    libres = ~mascara_cama(m)
    rangos = {}
    tope = p.angulo + 0.5  # un chaflán de 45° exactos no es exceso por redondeo
    bordes = [tope, 60.0, 75.0, 90.01]
    for lo, hi in zip(bordes[:-1], bordes[1:]):
        sel = libres & (ang > lo) & (ang <= hi)
        rangos[f"{lo:.0f}-{min(hi, 90):.0f}"] = float(m.area_faces[sel].sum())
    malas = np.nonzero(libres & (ang > tope))[0]
    zonas = []
    if len(malas):
        adj = m.face_adjacency
        sel = np.isin(adj, malas).all(axis=1)
        grupos = trimesh.graph.connected_components(adj[sel], nodes=malas, min_len=1)
        for g in grupos:
            g = np.asarray(g)
            c = m.triangles_center[g]
            planas = g[ang[g] > 60.0]
            # El ancho de lo casi plano separa un techo real del tope de un agujero chico.
            ancho60 = lado_menor(shapely.MultiPoint(m.triangles[planas].reshape(-1, 3)[:, :2])) if len(planas) else 0.0
            zonas.append({
                "area": float(m.area_faces[g].sum()),
                "area_60": float(m.area_faces[planas].sum()),
                "ancho_60": round(ancho60, 2),
                "ang_max": float(ang[g].max()),
                "z": [float(c[:, 2].min()), float(c[:, 2].max())],
                "x": float(c[:, 0].mean()),
                "y": float(c[:, 1].mean()),
            })
        zonas.sort(key=lambda z: -z["area"])
    return {"rangos": rangos, "zonas": zonas}


def rebanar(m: trimesh.Trimesh, p: Perfil) -> tuple:
    """Devuelve alturas y secciones. La capa i va a media altura de la capa."""
    alto = float(m.bounds[1][2])
    paso = max(p.capa, alto / p.max_capas)
    zs = [p.primera / 2]
    z = p.primera + paso / 2
    while z < alto:
        zs.append(z)
        z += paso
    secciones = []
    for z in zs:
        s = m.section(plane_origin=[0, 0, z], plane_normal=[0, 0, 1])
        if s is None:
            secciones.append(VACIO)
            continue
        plano, _ = s.to_2D(to_2D=np.eye(4))
        polys = [q if q.is_valid else q.buffer(0) for q in plano.polygons_full]
        secciones.append(unary_union(polys) if polys else VACIO)
    return zs, secciones, paso


def partes(g) -> list:
    if g.is_empty:
        return []
    if isinstance(g, Polygon):
        return [g]
    return [x for x in getattr(g, "geoms", []) if isinstance(x, Polygon) and x.area > 0]


def abrir(g, r: float):
    """Apertura morfológica: borra lo más angosto que 2r y conserva las esquinas."""
    return g.buffer(-r, **MITRE).buffer(r, **MITRE)


def cerrar(g, r: float):
    return g.buffer(r, **MITRE).buffer(-r, **MITRE)


def ancho(g) -> float:
    """Diámetro del mayor círculo inscrito."""
    try:
        return 2 * shapely.maximum_inscribed_circle(g, tolerance=0.02).length
    except Exception:
        return 2 * math.sqrt(g.area / math.pi)


def clasificar(u: Polygon, soporte, p: Perfil) -> tuple:
    """Clasifica una zona sin apoyo como isla, puente o voladizo plano."""
    borde = u.boundary
    if not u.buffer(0.02).intersects(soporte):
        return "isla", ancho(u)
    apoyo = borde.intersection(soporte.buffer(0.03))
    tramos = [t for t in getattr(shapely.line_merge(apoyo), "geoms", [shapely.line_merge(apoyo)])
              if t.length >= p.linea]
    total = sum(t.length for t in tramos)
    if not tramos:
        return "isla", ancho(u)
    if len(tramos) >= 2:
        a, b = sorted(tramos, key=lambda t: -t.length)[:2]
        return "puente", max(a.distance(b), ancho(u) if total / borde.length > 0.7 else 0.0)
    if total / borde.length >= 0.5:
        return "puente", ancho(u)
    return "voladizo plano", ancho(u)


def registrar(lista: list, ev: Evento, paso: float) -> None:
    """Une el evento con el de la capa anterior si son la misma zona."""
    for e in reversed(lista):
        if e.z1 < ev.z0 - 2.5 * paso:
            break
        if e.tipo != ev.tipo:
            continue
        a, b = e.caja, ev.caja
        if a[0] <= b[2] and b[0] <= a[2] and a[1] <= b[3] and b[1] <= a[3]:
            e.z1 = ev.z1
            e.capas += 1
            e.area = max(e.area, ev.area)
            e.medida = max(e.medida, ev.medida) if ev.tipo in ("puente", "voladizo plano", "isla") \
                else min(e.medida, ev.medida)
            e.caja = (min(a[0], b[0]), min(a[1], b[1]), max(a[2], b[2]), max(a[3], b[3]))
            return
    lista.append(ev)


def huella(sec) -> tuple:
    return (round(sec.area, 3), tuple(round(v, 3) for v in sec.bounds)) if not sec.is_empty else None


def analizar_capas(zs: list, secs: list, paso: float, p: Perfil) -> list:
    eventos: list = []
    margen = paso * math.tan(math.radians(p.angulo))
    r_apoyo = p.linea / 4
    k = max(1, math.ceil(p.capas_min * p.capa / paso))
    r_perdido = p.rasgo_min * p.boquilla / 2  # bajo esto el slicer lo descarta
    r_cordon = p.cordon_min * p.boquilla / 2  # bajo esto sale más ancho que el modelo
    r_pared = (p.pared(p.lineas_min) - 0.05) / 2  # bajo esto no caben lineas_min líneas limpias
    cache: dict = {}

    def delgados(sec) -> list:
        clave = huella(sec)
        if clave in cache:
            return cache[clave]
        res = []
        sin_perdido = abrir(sec, r_perdido)
        sin_angosto = abrir(sec, r_cordon)
        for q in partes(sec.difference(sin_perdido)):
            if q.area >= 0.1:
                res.append(("rasgo perdido", q))
        for q in partes(sin_perdido.difference(sin_angosto)):
            if q.area >= 0.3:
                res.append(("rasgo bajo el cordón mínimo", q))
        for q in partes(sin_angosto.difference(abrir(sec, r_pared))):
            if q.area >= 0.5:
                res.append(("pared de una línea", q))
        for q in partes(cerrar(sec, p.rendija_min / 2).difference(sec)):
            if q.area >= 0.3:
                res.append(("rendija", q))
        cache[clave] = res
        return res

    for i, (z, sec) in enumerate(zip(zs, secs)):
        if sec.is_empty:
            continue
        for tipo, q in delgados(sec):
            registrar(eventos, Evento(tipo, z, z, q.bounds, q.area, ancho(q)), paso)
        if i == 0:
            continue
        previa = secs[i - 1]
        soporte = previa.buffer(margen, **MITRE) if not previa.is_empty else VACIO
        sin_apoyo = abrir(sec.difference(soporte), r_apoyo)
        for u in partes(sin_apoyo):
            if u.area < p.linea ** 2:
                continue
            tipo, medida = clasificar(u, soporte, p)
            registrar(eventos, Evento(tipo, z, z, u.bounds, u.area, medida), paso)
    # Lámina: material que nace en una capa y ya no sigue k capas más arriba.
    for i, (z, sec) in enumerate(zip(zs, secs)):
        if sec.is_empty:
            continue
        nueva = sec if i == 0 else sec.difference(secs[i - 1])
        arriba = secs[i + k] if i + k < len(secs) else VACIO
        for q in partes(abrir(nueva.difference(arriba), 0.5)):
            if q.area >= 4.0:
                registrar(eventos, Evento("lámina fina", z, z, q.bounds, q.area, ancho(q)), paso)
    return eventos


def chaflan_inferior(zs: list, secs: list, p: Perfil) -> float | None:
    """Fracción del contorno de la primera capa sin chaflán (0 = todo achaflanado)."""
    if not secs or secs[0].is_empty:
        return None
    alto = next((s for z, s in zip(zs, secs) if z >= 0.8 and not s.is_empty), None)
    if alto is None:
        return None
    borde = secs[0].boundary
    sin = borde.intersection(alto.boundary.buffer(0.04))
    return float(sin.length / borde.length) if borde.length else None


def revisar(nombre: str, m: trimesh.Trimesh, p: Perfil, cargas=None) -> Informe:
    inf = Informe(nombre)
    ext = m.bounds[1] - m.bounds[0]
    inf.datos.update(medidas=[round(float(v), 2) for v in ext], triangulos=len(m.faces))

    if not m.is_watertight:
        inf.agregar("FALLA", "malla", "no es cerrada: el volumen y las secciones no son fiables")
    else:
        inf.datos["volumen_cm3"] = round(float(m.volume) / 1000, 2)
    if any(e > c for e, c in zip(sorted(ext[:2]), sorted(p.cama[:2]))) or ext[2] > p.cama[2]:
        inf.agregar("FALLA", "cama", f"{ext[0]:.1f}×{ext[1]:.1f}×{ext[2]:.1f} mm no cabe en "
                                     f"{p.cama[0]:.0f}×{p.cama[1]:.0f}×{p.cama[2]:.0f}")

    vol = voladizos(m, p)
    inf.datos["voladizo_mm2_por_angulo"] = {k: round(v, 1) for k, v in vol["rangos"].items()}
    inf.datos["zonas_voladizo"] = vol["zonas"][:6]

    zs, secs, paso = rebanar(m, p)
    inf.datos.update(capas=len(zs), paso_mm=round(paso, 3))
    base = secs[0] if secs else VACIO
    if base.is_empty:
        inf.agregar("FALLA", "contacto", "la primera capa no tiene sección: la pieza no toca la cama")
    else:
        menor = lado_menor(base)
        mayor = max((s.area for s in secs), default=0.0)
        inf.datos.update(contacto_mm2=round(base.area, 1),
                         contacto_sobre_seccion_max=round(base.area / mayor, 2) if mayor else None)
        if menor and ext[2] / menor > 4:
            inf.agregar("AVISO", "esbeltez", f"alto {ext[2]:.1f} mm sobre base de {menor:.1f} mm "
                                             f"(relación {ext[2] / menor:.1f}): puede soltarse o vibrar")
        if base.area < 50:
            inf.agregar("AVISO", "contacto", f"solo {base.area:.1f} mm² sobre la cama: considerar brim")
        sin = chaflan_inferior(zs, secs, p)
        if sin is not None:
            inf.datos["contorno_sin_chaflan"] = round(sin, 2)
            if sin > 0.5:
                inf.agregar("AVISO", "pata de elefante",
                            f"{sin:.0%} del contorno inferior sin chaflán: si ese borde ajusta con "
                            "otra pieza, achaflanar o compensar en el slicer")

    eventos = analizar_capas(zs, secs, paso, p)
    inf.eventos = sorted(eventos, key=lambda e: -e.area)
    por_tipo = {t: [e for e in inf.eventos if e.tipo == t] for t in {e.tipo for e in inf.eventos}}

    for e in por_tipo.get("isla", []):
        grave = e.area >= p.linea ** 2 * 2
        inf.agregar("FALLA" if grave else "AVISO", "isla", "sin nada debajo: " + e.texto())
    for e in por_tipo.get("voladizo plano", []):
        inf.agregar("FALLA" if e.medida > 3 * p.linea else "AVISO", "voladizo plano", e.texto())
    for e in por_tipo.get("puente", []):
        if e.medida > p.puente_max:
            inf.agregar("FALLA", "puente", e.texto())
        elif e.medida > p.puente_aviso:
            inf.agregar("AVISO", "puente", e.texto())
    for e in por_tipo.get("rasgo perdido", [])[:4]:
        # Una punta de gancho de 0.1 mm² es ruido; un rasgo de verdad ocupa más.
        inf.agregar("FALLA" if e.area >= 1.0 else "AVISO", "rasgo perdido", e.texto())
    for t in ("rasgo bajo el cordón mínimo", "pared de una línea", "lámina fina"):
        for e in por_tipo.get(t, [])[:4]:
            inf.agregar("AVISO", t, e.texto())
    # La punta de una gota o de una V se angosta en una sola capa: eso no es una rendija.
    for e in [e for e in por_tipo.get("rendija", []) if e.capas >= 3][:4]:
        inf.agregar("AVISO", "rendija", e.texto())
    pendiente = sum(z["area_60"] for z in vol["zonas"] if z["ancho_60"] >= 3.0)
    if pendiente > 25:
        inf.agregar("AVISO", "voladizo", f"{pendiente:.0f} mm² con más de 60° desde la vertical, en zonas de 3 mm "
                                         "o más de ancho: el tope de un agujero chico no cuenta")

    for c in cargas or []:
        ang = desde_capa(c)
        inf.datos.setdefault("carga_grados_desde_capa", []).append(round(ang, 1))
        if ang > 30:
            inf.agregar("AVISO", "carga", f"tracción a {ang:.0f}° del plano de capa: cruza capas, buscar otra "
                                          "orientación o partir la pieza")
    if not inf.hallazgos:
        inf.agregar("OK", "general", "sin hallazgos con este perfil")
    return inf


def candidatos(m: trimesh.Trimesh) -> list:
    dirs = [np.array(d, float) for d in
            [(0, 0, -1), (0, 0, 1), (1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0)]]
    if len(m.facets):
        for i in np.argsort(-m.facets_area)[:8]:
            dirs.append(m.facets_normal[i].copy())
    unicos: list = []
    for d in dirs:
        d = d / np.linalg.norm(d)
        if not any(np.dot(d, u) > 0.999 for u in unicos):
            unicos.append(d)
    return unicos


def orientaciones(m: trimesh.Trimesh, p: Perfil, cargas=None) -> list:
    filas = []
    for d in candidatos(m):
        rot = orientar(m, d)
        vol = voladizos(rot, p)
        cama = mascara_cama(rot)
        fila = {
            "abajo": ",".join(f"{v:.3g}" for v in d),
            "alto_mm": round(float(rot.bounds[1][2]), 1),
            "contacto_mm2": round(float(rot.area_faces[cama].sum()), 1),
            "voladizo_mm2": round(sum(vol["rangos"].values()), 1),
        }
        if cargas:
            giro = trimesh.geometry.align_vectors(d, [0, 0, -1])[:3, :3]
            fila["carga_peor_desde_capa"] = round(max(desde_capa(giro @ np.asarray(c, float)) for c in cargas), 1)
        filas.append(fila)
    return sorted(filas, key=lambda f: (f.get("carga_peor_desde_capa", 0) > 30, f["contacto_mm2"] < 25,
                                        f["voladizo_mm2"], f["alto_mm"]))


def vector(texto: str) -> list:
    v = [float(x) for x in texto.split(",")]
    if len(v) != 3:
        raise argparse.ArgumentTypeError("se espera x,y,z")
    return v


def main() -> int:
    d = Perfil()
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("archivo")
    ap.add_argument("--abajo", type=vector, help="dirección del modelo que va a la cama, x,y,z")
    ap.add_argument("--carga", type=vector, action="append",
                    help="dirección de la tracción en un tramo, x,y,z; repetir por tramo")
    ap.add_argument("--orientaciones", action="store_true", help="compara orientaciones candidatas")
    ap.add_argument("--json", action="store_true")
    for n in ("boquilla", "linea", "capa", "primera", "angulo", "puente_aviso", "puente_max", "rendija_min"):
        ap.add_argument("--" + n.replace("_", "-"), type=float, default=getattr(d, n))
    ap.add_argument("--lineas-min", type=int, default=d.lineas_min)
    ap.add_argument("--capas-min", type=int, default=d.capas_min)
    ap.add_argument("--cordon-min", type=float, default=d.cordon_min)
    ap.add_argument("--rasgo-min", type=float, default=d.rasgo_min)
    ap.add_argument("--cama", type=lambda t: tuple(float(x) for x in t.split("x")), default=d.cama)
    a = ap.parse_args()
    p = Perfil(a.boquilla, a.linea, a.capa, a.primera, a.angulo, a.cama, a.puente_aviso, a.puente_max,
               a.rendija_min, a.lineas_min, a.capas_min, a.cordon_min, a.rasgo_min)

    cuerpos = cargar(a.archivo)
    salida, falla = [], False
    for i, c in enumerate(cuerpos, 1):
        nombre = f"cuerpo {i}/{len(cuerpos)}"
        m = orientar(c, a.abajo)
        cargas = a.carga
        if cargas and a.abajo is not None:
            v = np.asarray(a.abajo, float)
            giro = trimesh.geometry.align_vectors(v / np.linalg.norm(v), [0, 0, -1])[:3, :3]
            cargas = [(giro @ np.asarray(c, float)).tolist() for c in cargas]
        inf = revisar(nombre, m, p, cargas)
        falla |= any(h.nivel == "FALLA" for h in inf.hallazgos)
        filas = orientaciones(c, p, a.carga) if a.orientaciones else []
        salida.append((inf, filas))

    if a.json:
        print(json.dumps([{"nombre": i.nombre, "hallazgos": [asdict(h) for h in i.hallazgos], "datos": i.datos,
                           "eventos": [asdict(e) for e in i.eventos[:40]], "orientaciones": f}
                          for i, f in salida], ensure_ascii=False, indent=1))
        return int(falla)

    print(f"Perfil: boquilla {p.boquilla}, línea {p.linea}, capa {p.capa}, ángulo {p.angulo:.0f}° desde la vertical")
    print("Paredes nominales: " + ", ".join(f"{n} líneas {p.pared(n):.2f}" for n in range(1, 7)) + " mm")
    for inf, filas in salida:
        print(f"\n== {inf.nombre} ==")
        print("  " + ", ".join(f"{k}={v}" for k, v in inf.datos.items() if k != "zonas_voladizo"))
        for z in inf.datos.get("zonas_voladizo", [])[:3]:
            print(f"  zona de voladizo: {z['area']:.1f} mm², hasta {z['ang_max']:.0f}°, "
                  f"z {z['z'][0]:.1f}–{z['z'][1]:.1f}, en x {z['x']:.1f} y {z['y']:.1f}")
        orden = {"FALLA": 0, "AVISO": 1, "OK": 2}
        for h in sorted(inf.hallazgos, key=lambda h: orden[h.nivel]):
            print(f"  {h.nivel:5} {h.chequeo}: {h.detalle}")
        if filas:
            print("  orientaciones (mejor primero):")
            for f in filas[:6]:
                print("    " + ", ".join(f"{k}={v}" for k, v in f.items()))
    return int(falla)


if __name__ == "__main__":
    sys.exit(main())
