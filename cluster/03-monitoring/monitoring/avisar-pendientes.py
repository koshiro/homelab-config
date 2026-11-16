#!/usr/bin/env python3
"""Avisa por Telegram de los pendientes abiertos de docs/PENDIENTES.md (lo lee de main en GitHub).

Corre cada hora en punto (CronJob avisar-pendientes, zona America/Santiago). Sin estado:
  - Un `- [ ]` con `⏰ AAAA-MM-DD [HH:MM]` (sin hora = 09:00) avisa en la primera hora en punto desde su hora
    (ventana de 60 min: una sola vez).
  - A las 09:00, los vencidos que siguen abiertos se repiten cada día.
  - Los lunes a las 09:00 llega el resumen de todos los abiertos, por sección.
Marcar `[x]` en el archivo silencia el pendiente.

Pruebas locales sin enviar: AHORA="2026-11-16 09:00" DRY_RUN=1 PENDIENTES_ARCHIVO=docs/PENDIENTES.md ./avisar-pendientes.py
"""
import json
import os
import re
import sys
import time
import urllib.request
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

URL = os.environ.get(
    "PENDIENTES_URL",
    "https://raw.githubusercontent.com/koshiro/homelab-config/main/docs/PENDIENTES.md",
)
VER = "https://github.com/koshiro/homelab-config/blob/main/docs/PENDIENTES.md"
TZ = ZoneInfo(os.environ.get("TZ_AVISOS", "America/Santiago"))
HORA_DIARIA = 9
LIMITE = 3800  # Telegram corta en 4096 caracteres
MARCA = re.compile(r"⏰\s*(\d{4}-\d{2}-\d{2})(?:[ T](\d{2}:\d{2}))?")
ITEM = re.compile(r"^(\s*)- \[ \]\s*(.*)$")


def descargar():
    ruta = os.environ.get("PENDIENTES_ARCHIVO")
    if ruta:
        return open(ruta, encoding="utf-8").read()
    for intento in range(5):
        try:
            with urllib.request.urlopen(URL, timeout=20) as r:
                texto = r.read().decode("utf-8")
            if texto.strip():
                return texto
        except Exception as e:  # noqa: BLE001
            print(f"intento {intento + 1}: {e}", file=sys.stderr)
        time.sleep(10)
    return None


def limpiar(texto, largo=170):
    texto = MARCA.sub("", texto)
    texto = re.sub(r"\*\*|`", "", texto)
    texto = re.sub(r"\s+", " ", texto).strip(" -—:")
    return texto if len(texto) <= largo else texto[: largo - 1].rstrip() + "…"


def parsear(texto):
    """Devuelve [{seccion, titulo, vence(datetime|None)}] de los `- [ ]` abiertos."""
    lineas = texto.splitlines()
    items, seccion = [], ""
    for i, linea in enumerate(lineas):
        if linea.startswith("## "):
            seccion = re.sub(r"\s*✅.*$", "", linea[3:]).strip()
            continue
        m = ITEM.match(linea)
        if not m:
            continue
        sangria = len(m.group(1))
        partes = [m.group(2)]
        for sig in lineas[i + 1 :]:
            if not sig.strip() or len(sig) - len(sig.lstrip()) <= sangria:
                break
            if sig.strip().startswith("- ["):
                break
            partes.append(sig.strip())
        completo = " ".join(partes)
        marca = MARCA.search(completo)
        vence = None
        if marca:
            hora = marca.group(2) or f"{HORA_DIARIA:02d}:00"
            vence = datetime.strptime(f"{marca.group(1)} {hora}", "%Y-%m-%d %H:%M").replace(tzinfo=TZ)
        items.append({"seccion": seccion, "titulo": limpiar(completo), "vence": vence})
    return items


def fmt(it):
    cola = f" (⏰ {it['vence']:%Y-%m-%d %H:%M})" if it["vence"] else ""
    return f"• {it['titulo']}{cola}"


def trozos(encabezado, cuerpo):
    """Parte un mensaje largo en varios de <= LIMITE caracteres, repitiendo el encabezado."""
    salida, actual = [], encabezado
    for linea in cuerpo:
        if len(actual) + len(linea) + 1 > LIMITE and actual != encabezado:
            salida.append(actual)
            actual = encabezado + " (cont.)"
        actual += "\n" + linea
    salida.append(actual)
    return salida


def mensajes(items, ahora):
    msgs = []
    con_fecha = [i for i in items if i["vence"]]
    justo = [i for i in con_fecha if i["vence"] <= ahora < i["vence"] + timedelta(minutes=60)]
    if justo:
        msgs += trozos("⏰ Pendiente del homelab que vence ahora", [fmt(i) for i in justo] + [VER])
    if ahora.hour == HORA_DIARIA:
        vencidos = sorted(
            (i for i in con_fecha if i["vence"] + timedelta(minutes=60) <= ahora), key=lambda i: i["vence"]
        )
        if vencidos:
            msgs += trozos("⚠️ Pendientes del homelab vencidos", [fmt(i) for i in vencidos] + [VER])
        if ahora.weekday() == 0:
            cuerpo, ultima = [], None
            for i in items:
                if i["seccion"] != ultima:
                    ultima = i["seccion"]
                    cuerpo.append(f"\n{ultima or 'Sin sección'}")
                cuerpo.append(fmt(i))
            msgs += trozos(f"📋 Resumen semanal: {len(items)} pendientes abiertos", cuerpo + ["", VER])
    return msgs


def enviar(texto):
    if os.environ.get("DRY_RUN"):
        print("--- mensaje ---\n" + texto)
        return
    cuerpo = json.dumps(
        {"chat_id": os.environ["CHAT_ID"], "text": texto, "disable_web_page_preview": True}
    ).encode()
    req = urllib.request.Request(
        f"https://api.telegram.org/bot{os.environ['BOT_TOKEN']}/sendMessage",
        data=cuerpo,
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=20) as r:
        r.read()


def main():
    ahora = datetime.now(TZ)
    if os.environ.get("AHORA"):
        ahora = datetime.strptime(os.environ["AHORA"], "%Y-%m-%d %H:%M").replace(tzinfo=TZ)
    texto = descargar()
    if texto is None:
        # una caída de GitHub no debe parecer un fallo del cluster ni generar avisos propios
        print("GitHub no respondió: aviso omitido")
        return 0
    items = parsear(texto)
    msgs = mensajes(items, ahora)
    print(f"{ahora:%Y-%m-%d %H:%M %Z}: {len(items)} abiertos, {len(msgs)} mensajes")
    for m in msgs:
        enviar(m)
    return 0


if __name__ == "__main__":
    sys.exit(main())
