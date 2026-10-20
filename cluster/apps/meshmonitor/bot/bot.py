#!/usr/bin/env python3
"""Bot de Telegram de la flota Meshtastic: ubicación de los trackers según lo que oye AcevedoRoof.

- Lee los nodos de la API REST de MeshMonitor (/api/v1/sources/{id}/nodes); no toca el nodo del techo.
- Comandos: /donde [nombre] (ubicación en el mapa), /flota (última vez oído cada nodo), /ayuda.
- Solo obedece al chat configurado en TELEGRAM_CHAT_ID.

Solo biblioteca estándar. Variables: TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID, MM_TOKEN, MM_URL (default
http://meshmonitor:3001), MM_SOURCE (default: la fuente primaria), NODOS (JSON: [{"id", "alias", "tracker"}]),
FUERA_MIN (default 120: sin oírlo en ese tiempo se marca fuera de alcance).
"""
import json
import os
import time
import urllib.parse
import urllib.request

TOKEN = os.environ["TELEGRAM_BOT_TOKEN"].strip()
CHAT_ID = int(os.environ["TELEGRAM_CHAT_ID"].strip())
MM_TOKEN = os.environ["MM_TOKEN"].strip()
MM_URL = os.environ.get("MM_URL", "http://meshmonitor:3001").rstrip("/")
MM_SOURCE = os.environ.get("MM_SOURCE", "").strip()
NODOS = json.loads(os.environ["NODOS"])
FUERA = int(os.environ.get("FUERA_MIN", "120")) * 60
API = f"https://api.telegram.org/bot{TOKEN}"


def log(*a):
    print(time.strftime("%Y-%m-%d %H:%M:%S"), *a, flush=True)


# ---------------------------------------------------------------- Telegram
def tg(method, **params):
    data = json.dumps(params).encode()
    req = urllib.request.Request(f"{API}/{method}", data=data,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=70) as r:
        return json.load(r)


def send(text):
    return tg("sendMessage", chat_id=CHAT_ID, text=text, parse_mode="HTML", disable_web_page_preview=True)


def esc(s):
    return str(s).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


# ---------------------------------------------------------------- MeshMonitor
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


def nodos_flota():
    """Nodos de NODOS con su registro de MeshMonitor (None si nunca se oyó), en el orden de NODOS."""
    sid = urllib.parse.quote(source_id())
    por_id = {n["nodeId"]: n for n in mm(f"/sources/{sid}/nodes")}
    return [(cfg, por_id.get(cfg["id"])) for cfg in NODOS]


# ---------------------------------------------------------------- Formato
def hace(epoch):
    s = max(0, int(time.time() - epoch))
    if s < 90:
        return f"{s} s"
    if s < 5400:
        return f"{s // 60} min"
    if s < 172800:
        return f"{s // 3600} h {s % 3600 // 60} min"
    return f"{s // 86400} días"


def nombre(n, cfg):
    if not n:
        return esc(cfg["id"])
    return f"{esc(n.get('shortName') or '')} {esc(n.get('longName') or cfg['id'])}".strip()


def enlace(n):
    return n.get("hopsAway") if not n.get("viaMqtt") else "mqtt"


def detalle(n):
    """Una línea: cuándo se oyó, por dónde y batería."""
    partes = []
    if n.get("lastHeard"):
        oido = f"oído hace {hace(n['lastHeard'])}"
        if time.time() - n["lastHeard"] > FUERA:
            oido = "⚠️ fuera de alcance, " + oido
        partes.append(oido)
    else:
        partes.append("nunca oído")
    hops = enlace(n)
    if hops == "mqtt":
        partes.append("vía MQTT")
    elif hops == 0:
        partes.append("directo al techo")
    elif hops is not None:
        partes.append(f"{hops} saltos")
    if n.get("snr") is not None and hops == 0:
        partes.append(f"SNR {n['snr']:g} dB")
    bat = n.get("batteryLevel")
    if bat is not None:
        partes.append("🔌 enchufado" if bat > 100 else f"🔋 {bat} %")
    return " · ".join(partes)


def posicion(n):
    if n.get("positionOverrideEnabled") and n.get("latitudeOverride") is not None:
        return n["latitudeOverride"], n["longitudeOverride"], None
    if n.get("latitude") is None or n.get("longitude") is None:
        return None
    ts = n.get("positionTimestamp")
    return n["latitude"], n["longitude"], ts / 1000 if ts else None


# ---------------------------------------------------------------- Comandos
def buscar(arg):
    arg = arg.lower()
    return [cfg for cfg in NODOS
            if arg == cfg["id"].lower() or any(arg in a.lower() for a in cfg.get("alias", []))]


def cmd_donde(arg):
    cfgs = buscar(arg) if arg else [c for c in NODOS if c.get("tracker")]
    if not cfgs:
        send(f"No conozco «{esc(arg)}». Prueba /flota para ver los nombres.")
        return
    ids = {c["id"] for c in cfgs}
    for cfg, n in nodos_flota():
        if cfg["id"] not in ids:
            continue
        if not n:
            send(f"❔ <b>{nombre(n, cfg)}</b>: AcevedoRoof nunca lo ha oído.")
            continue
        pos = posicion(n)
        if not pos:
            send(f"📍 <b>{nombre(n, cfg)}</b>: sin posición registrada.\n{detalle(n)}")
            continue
        lat, lon, ts = pos
        edad = f"posición de hace {hace(ts)}" if ts else "posición fija"
        tg("sendVenue", chat_id=CHAT_ID, latitude=lat, longitude=lon,
           title=f"{n.get('shortName') or ''} {n.get('longName') or cfg['id']}".strip(),
           address=f"{edad} · {detalle(n)}")


def cmd_flota():
    lineas = []
    for cfg, n in nodos_flota():
        if not n:
            lineas.append(f"❔ <b>{nombre(n, cfg)}</b>: nunca oído")
            continue
        pin = " 📍" if posicion(n) else ""
        lineas.append(f"<b>{nombre(n, cfg)}</b>{pin}: {detalle(n)}")
    send("📡 <b>Flota según AcevedoRoof</b>\n" + "\n".join(lineas))


AYUDA = ("🛰️ Flota Meshtastic (lo que oye AcevedoRoof)\n"
         "/donde — ubicación de los trackers\n"
         "/donde &lt;nombre&gt; — un nodo (p. ej. akira, gato, auto)\n"
         "/flota — cuándo se oyó cada nodo, saltos y batería")


def handle_message(m):
    if m.get("chat", {}).get("id") != CHAT_ID:
        return
    text = (m.get("text") or "").strip()
    cmd, _, arg = text.partition(" ")
    cmd = cmd.split("@")[0].lower()
    arg = arg.strip()
    try:
        if cmd in ("/donde", "/ubicacion"):
            cmd_donde(arg)
        elif cmd in ("/flota", "/nodos"):
            cmd_flota()
        elif cmd in ("/ayuda", "/help", "/start"):
            send(AYUDA)
    except Exception as e:  # noqa: BLE001
        log("error en comando", repr(cmd), e)
        try:
            send(f"⚠️ <code>{esc(str(e))}</code>")
        except Exception as e2:  # noqa: BLE001
            log("no se pudo avisar del error:", e2)


def poll_updates():
    offset = None
    while True:
        try:
            p = {"timeout": 50, "allowed_updates": ["message"]}
            if offset is not None:
                p["offset"] = offset
            for u in tg("getUpdates", **p).get("result", []):
                offset = u["update_id"] + 1
                if "message" in u:
                    handle_message(u["message"])
        except Exception as e:  # noqa: BLE001
            log("error en getUpdates:", e)
            time.sleep(5)


if __name__ == "__main__":
    log("bot de la flota iniciado; MeshMonitor", MM_URL)
    try:
        tg("setMyCommands", commands=[
            {"command": "donde", "description": "Ubicación de los trackers"},
            {"command": "flota", "description": "Cuándo se oyó cada nodo"},
            {"command": "ayuda", "description": "Comandos"}])
    except Exception as e:  # noqa: BLE001
        log("setMyCommands falló:", e)
    poll_updates()
