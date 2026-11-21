#!/usr/bin/env python3
"""Administrador automático de la flota Meshtastic por el nodo del techo (AcevedoRoof).

Cada vez que MeshMonitor oye a un nodo de la flota, le lleva `security.admin_key` al estado deseado por admin remoto
(PKC) a través del nodo virtual de MeshMonitor. Así un cambio de administradores llega solo a los nodos que pasan
poco por casa (trackers, nodos portátiles) sin tener que perseguirlos con el CLI.

- Detecta "oído" con la API REST de MeshMonitor (/api/v1/sources/{id}/nodes, campo transportLastRf): solo cuenta lo
  oído por LoRa, porque un nodo que llega por MQTT (Client Proxy, PapoRelay) no está al alcance de la radio del techo.
- Lee la sección security del nodo por radio; si admin_key ya coincide, lo deja tranquilo por OK_HORAS.
- Si no coincide, reemplaza solo la lista admin_key (el resto de la sección es la que devolvió el nodo) y la vuelve a
  leer la próxima vez que lo oiga para confirmar.
- Avisa por Telegram cuando corrige o confirma un nodo. Estado en memoria: tras un reinicio, relee cada nodo una vez.

Variables: MM_TOKEN, MM_URL (default http://meshmonitor:3001), MM_SOURCE (default: la primaria), VNODE
(default meshmonitor-vnode:4404), FLOTA (JSON [{"id", "nombre", "pubkey", "local"?}]; `local: true` = el techo mismo, no se administra por radio), ADMINS (JSON con los nombres de FLOTA
cuya llave va en admin_key; la propia de cada nodo se omite), TELEGRAM_BOT_TOKEN y TELEGRAM_CHAT_ID (opcionales),
POLL_SEG (60), RECIENTE_SEG (300), OK_HORAS (168), REINTENTO_MIN (30).
"""
import base64
import contextlib
import io
import json
import os
import threading
import time
import urllib.request

import meshtastic.tcp_interface
from meshtastic.protobuf import localonly_pb2

MM_TOKEN = os.environ["MM_TOKEN"].strip()
MM_URL = os.environ.get("MM_URL", "http://meshmonitor:3001").rstrip("/")
MM_SOURCE = os.environ.get("MM_SOURCE", "").strip()
VNODE_HOST, _, VNODE_PORT = os.environ.get("VNODE", "meshmonitor-vnode:4404").partition(":")
FLOTA = json.loads(os.environ["FLOTA"])
ADMINS = json.loads(os.environ["ADMINS"])
TG_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "").strip()
TG_CHAT = os.environ.get("TELEGRAM_CHAT_ID", "").strip()
POLL = int(os.environ.get("POLL_SEG", "60"))
RECIENTE = int(os.environ.get("RECIENTE_SEG", "300"))
OK_SEG = int(os.environ.get("OK_HORAS", "168")) * 3600
REINTENTO = int(os.environ.get("REINTENTO_MIN", "30")) * 60

POR_NOMBRE = {n["nombre"]: n for n in FLOTA}
# nodo → epoch hasta el que no se vuelve a tocar (ok, recién escrito o fallido)
quieto = {}
# nodo → lastHeard ya procesado (un intento por cada vez que se le oye)
visto = {}
escrito = set()


def log(*a):
    print(time.strftime("%Y-%m-%d %H:%M:%S"), *a, flush=True)


def aviso(texto):
    if not (TG_TOKEN and TG_CHAT):
        return
    try:
        req = urllib.request.Request(f"https://api.telegram.org/bot{TG_TOKEN}/sendMessage",
                                     data=json.dumps({"chat_id": int(TG_CHAT), "text": texto}).encode(),
                                     headers={"Content-Type": "application/json"})
        urllib.request.urlopen(req, timeout=20).close()
    except Exception as e:   # un aviso perdido no detiene la administración
        log("telegram:", e)


def mm(path):
    req = urllib.request.Request(f"{MM_URL}/api/v1{path}", headers={"Authorization": f"Bearer {MM_TOKEN}"})
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.load(r)["data"]


def source_id():
    global MM_SOURCE
    if not MM_SOURCE:
        fuentes = mm("/sources")
        MM_SOURCE = next((f for f in fuentes if f.get("isPrimary")), fuentes[0])["id"]
    return MM_SOURCE


def deseadas(nodo):
    """Llaves de admin para `nodo`: las de ADMINS menos la suya (no sirve y gasta uno de los 3 cupos)."""
    return [base64.b64decode(POR_NOMBRE[a]["pubkey"]) for a in ADMINS if a != nodo["nombre"]]


def con_limite(fn, *args, t=90):
    th = threading.Thread(target=fn, args=args, daemon=True)
    th.start()
    th.join(t)
    return not th.is_alive()


def corto(llaves):
    return [base64.b64encode(k).decode()[:8] for k in llaves]


def administrar(nodo):
    """Lee security del nodo por radio y corrige admin_key. Devuelve 'ok', 'escrito' o lanza si no responde."""
    quiero = deseadas(nodo)
    iface = meshtastic.tcp_interface.TCPInterface(VNODE_HOST, portNumber=int(VNODE_PORT or 4404))
    try:
        remoto = iface.getNode(nodo["id"], requestChannels=False, timeout=60)
        fd = localonly_pb2.LocalConfig.DESCRIPTOR.fields_by_name["security"]
        with contextlib.redirect_stdout(io.StringIO()):
            llego = con_limite(remoto.requestConfig, fd)
        if not llego or not remoto.localConfig.HasField("security"):
            raise RuntimeError("no llegó la sección security")
        sec = remoto.localConfig.security
        tengo = [k for k in sec.admin_key if k]
        if set(tengo) == set(quiero):
            return "ok", tengo, quiero
        del sec.admin_key[:]
        sec.admin_key.extend(quiero)
        con_limite(remoto.beginSettingsTransaction)
        con_limite(remoto.writeConfig, "security")
        con_limite(remoto.commitSettingsTransaction)
        time.sleep(10)
        return "escrito", tengo, quiero
    finally:
        iface.close()


def ciclo():
    por_id = {n["nodeId"]: n for n in mm(f"/sources/{source_id()}/nodes")}
    ahora = time.time()
    for nodo in FLOTA:
        if nodo.get("local"):
            continue
        n = por_id.get(nodo["id"]) or {}
        oido = n.get("transportLastRf") or 0
        if ahora - oido > RECIENTE or visto.get(nodo["id"]) == oido or quieto.get(nodo["id"], 0) > ahora:
            continue
        visto[nodo["id"]] = oido
        log(f"{nodo['nombre']} oído por radio hace {int(ahora - oido)} s → revisando admin_key")
        try:
            estado, tengo, quiero = administrar(nodo)
        except Exception as e:
            log(f"{nodo['nombre']}: sin respuesta ({e}); reintento en {REINTENTO // 60} min")
            quieto[nodo["id"]] = time.time() + REINTENTO
            continue
        if estado == "ok":
            log(f"{nodo['nombre']}: admin_key correcto {corto(tengo)}")
            quieto[nodo["id"]] = time.time() + OK_SEG
            if nodo["id"] in escrito:
                escrito.discard(nodo["id"])
                aviso(f"Flota: {nodo['nombre']} confirmó admin_key {corto(tengo)}")
        else:
            log(f"{nodo['nombre']}: admin_key {corto(tengo)} → {corto(quiero)}")
            escrito.add(nodo["id"])
            quieto[nodo["id"]] = time.time() + 600   # releer para confirmar la próxima vez que se le oiga
            aviso(f"Flota: {nodo['nombre']} admin_key {corto(tengo)} → {corto(quiero)} (se confirmará al oírlo)")


def main():
    log(f"administrando {len(FLOTA)} nodos por {VNODE_HOST}:{VNODE_PORT}; admins {ADMINS}")
    while True:
        try:
            ciclo()
        except Exception as e:
            log("ciclo:", e)
        time.sleep(POLL)


if __name__ == "__main__":
    main()
