#!/usr/bin/env -S uv run --quiet --no-project --script
# /// script
# requires-python = ">=3.11,<3.14"
# dependencies = ["numpy", "scipy", "shapely>=2.1", "networkx", "rtree", "lxml", "trimesh>=4.4", "manifold3d", "pytest"]
# ///
"""Pruebas del revisor con piezas sintéticas cuyo resultado se conoce de antemano.

    uv run --no-project --script scripts/test_revisar_impresion.py
"""
import math
import sys
from pathlib import Path

import numpy as np
import pytest
import trimesh

sys.path.insert(0, str(Path(__file__).parent))
from revisar_impresion import Perfil, orientaciones, orientar, revisar  # noqa: E402

P = Perfil()


def caja(x, y, z, cx=0.0, cy=0.0, cz=None):
    m = trimesh.creation.box(extents=[x, y, z])
    m.apply_translation([cx, cy, z / 2 if cz is None else cz])
    return m


def niveles(inf, chequeo):
    return [h.nivel for h in inf.hallazgos if h.chequeo == chequeo]


def medidas(inf, tipo):
    return [e.medida for e in inf.eventos if e.tipo == tipo]


def test_cubo_limpio_no_tiene_fallas():
    inf = revisar("cubo", orientar(caja(30, 30, 20), None), P)
    assert not [h for h in inf.hallazgos if h.nivel == "FALLA"]
    assert inf.datos["contacto_mm2"] == pytest.approx(900, rel=0.01)


def test_no_cabe_en_la_cama():
    inf = revisar("grande", orientar(caja(300, 30, 20), None), P)
    assert "FALLA" in niveles(inf, "cama")


def test_estante_en_voladizo_es_falla():
    pieza = trimesh.boolean.union([caja(10, 30, 30), caja(15, 30, 4, cx=12.5, cz=20)])
    inf = revisar("estante", orientar(pieza, None), P)
    assert "FALLA" in niveles(inf, "voladizo plano")
    assert max(medidas(inf, "voladizo plano")) == pytest.approx(15, abs=1.0)


def test_rampa_a_45_grados_no_es_voladizo_plano():
    perfil = trimesh.creation.extrude_polygon(
        trimesh.path.polygons.Polygon([(0, 0), (10, 0), (10, 2), (20, 12), (20, 16), (0, 16)]), 20)
    pieza = orientar(perfil, [0, -1, 0])
    inf = revisar("rampa", pieza, P)
    assert not niveles(inf, "voladizo plano")


def test_puente_mide_el_vano():
    puente = trimesh.boolean.union([caja(5, 20, 20, cx=-10), caja(5, 20, 20, cx=10),
                                    caja(25, 20, 3, cz=21.5)])
    inf = revisar("puente", orientar(puente, None), P)
    assert max(medidas(inf, "puente")) == pytest.approx(15, abs=1.5)
    assert "AVISO" in niveles(inf, "puente")


def test_puente_muy_largo_es_falla():
    puente = trimesh.boolean.union([caja(5, 20, 20, cx=-42.5), caja(5, 20, 20, cx=42.5),
                                    caja(90, 20, 3, cz=21.5)])
    inf = revisar("puente largo", orientar(puente, None), P)
    assert "FALLA" in niveles(inf, "puente")


def test_techo_de_cavidad_cerrada_mide_el_lado_corto():
    hueco = caja(10, 30, 10, cz=12)
    pieza = trimesh.boolean.difference([caja(20, 40, 20), hueco])
    inf = revisar("cavidad", orientar(pieza, None), P)
    assert max(medidas(inf, "puente")) == pytest.approx(10, abs=1.0)


def test_isla_flotante_es_falla():
    malla = trimesh.boolean.union([caja(30, 30, 3), caja(10, 10, 3, cz=10)])
    assert len(malla.split()) == 2
    con_voladizo = trimesh.util.concatenate(malla.split())
    inf = revisar("isla", orientar(con_voladizo, None), P)
    assert "FALLA" in niveles(inf, "isla")


def test_pared_de_una_linea_y_rasgo_perdido():
    fina = trimesh.boolean.union([caja(30, 30, 2), caja(30, 0.6, 10, cz=7)])
    inf = revisar("pared", orientar(fina, None), P)
    assert niveles(inf, "pared de una línea")
    angosta = trimesh.boolean.union([caja(30, 30, 2), caja(30, 0.3, 10, cz=7)])
    inf = revisar("angosta", orientar(angosta, None), P)
    assert niveles(inf, "rasgo bajo el cordón mínimo")
    perdida = trimesh.boolean.union([caja(30, 30, 2), caja(30, 0.08, 10, cz=7)])
    inf = revisar("rasgo", orientar(perdida, None), P)
    assert "FALLA" in niveles(inf, "rasgo perdido")


def test_dos_lineas_de_1_1_mm_no_avisan():
    pared = trimesh.boolean.union([caja(30, 30, 2), caja(30, 1.1, 10, cz=7)])
    inf = revisar("pared", orientar(pared, None), P)
    assert not niveles(inf, "pared de una línea")


def test_ancho_de_paredes_coincide_con_la_formula():
    assert P.pared(2) == pytest.approx(1.126, abs=0.01)
    assert P.pared(3) == pytest.approx(1.671, abs=0.01)


def test_rendija_estrecha():
    pieza = trimesh.boolean.difference([caja(30, 30, 10), caja(40, 0.2, 12, cz=6)])
    partes = pieza.split()
    junta = trimesh.util.concatenate(partes) if len(partes) > 1 else pieza
    inf = revisar("rendija", orientar(junta, None), P)
    assert niveles(inf, "rendija")


def test_lamina_mide_el_espesor_real():
    fina = trimesh.boolean.difference([caja(40, 40, 10), caja(30, 30, 10, cz=5.3)])
    assert niveles(revisar("fina", orientar(fina, None), P), "lámina fina")
    gruesa = trimesh.boolean.difference([caja(40, 40, 10), caja(30, 30, 10, cz=6)])
    assert not niveles(revisar("gruesa", orientar(gruesa, None), P), "lámina fina")


def test_agujero_horizontal_grande_se_detecta_como_voladizo():
    tubo = trimesh.creation.cylinder(radius=8, height=60, sections=96)
    tubo.apply_transform(trimesh.transformations.rotation_matrix(math.pi / 2, [1, 0, 0]))
    tubo.apply_translation([0, 0, 15])
    inf = revisar("agujero", orientar(trimesh.boolean.difference([caja(40, 40, 30), tubo]), None), P)
    assert inf.datos["voladizo_mm2_por_angulo"]["75-90"] > 10


def test_chaflan_inferior():
    sin = revisar("sin", orientar(caja(30, 30, 10), None), P)
    assert sin.datos["contorno_sin_chaflan"] > 0.9
    achaflanada = trimesh.creation.extrude_polygon(
        trimesh.path.polygons.Polygon([(1, 0), (29, 0), (30, 1), (30, 10), (0, 10), (0, 1)]), 30)
    con = revisar("con", orientar(achaflanada, [0, -1, 0]), P)
    assert con.datos["contacto_mm2"] < 900


def test_orientaciones_prefiere_la_cara_grande_abajo():
    ele = trimesh.boolean.union([caja(40, 40, 4), caja(4, 40, 30, cx=-18)])
    filas = orientaciones(ele, P)
    assert filas[0]["contacto_mm2"] >= 1500
    assert filas[0]["voladizo_mm2"] == pytest.approx(0, abs=1)


def test_carga_avisa_sobre_30_grados_del_plano_de_capa():
    pieza = orientar(caja(30, 30, 20), None)
    assert "AVISO" in niveles(revisar("z", pieza, P, cargas=[[0, 0, 1]]), "carga")
    assert "AVISO" in niveles(revisar("59", pieza, P, cargas=[[0, 0.6, 1]]), "carga")
    assert not niveles(revisar("plano", pieza, P, cargas=[[1, 0, 0]]), "carga")
    assert not niveles(revisar("20", pieza, P, cargas=[[1, 0, 0.36]]), "carga")


def test_varias_cargas_avisan_por_el_peor_tramo():
    pieza = orientar(caja(30, 30, 20), None)
    inf = revisar("dos", pieza, P, cargas=[[1, 0, 0], [0, 0, 1]])
    assert len(niveles(inf, "carga")) == 1


def agujero_horizontal(radio):
    tubo = trimesh.creation.cylinder(radius=radio, height=60, sections=96)
    tubo.apply_transform(trimesh.transformations.rotation_matrix(math.pi / 2, [1, 0, 0]))
    tubo.apply_translation([0, 0, 15])
    return trimesh.boolean.difference([caja(40, 40, 30), tubo])


def test_el_tope_de_un_agujero_chico_no_avisa_y_el_de_uno_grande_si():
    assert not niveles(revisar("m4", orientar(agujero_horizontal(2.25), None), P), "voladizo")
    assert niveles(revisar("grande", orientar(agujero_horizontal(8), None), P), "voladizo")


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-q", "--no-header", "-p", "no:cacheprovider"]))
