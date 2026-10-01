#!/usr/bin/env python3
"""Bot de Telegram para la whitelist de Minecraft.

- Lee el log del servidor (/data/logs/latest.log, NFS de solo lectura) y avisa cuando alguien
  que no está en la whitelist intenta entrar, con botones "Agregar" / "Ignorar".
- "Agregar" ejecuta por RCON `whitelist add <nombre>` (Java) o `fwhitelist add <gamertag>`
  (Bedrock vía Floodgate: los nombres llegan con el prefijo ".").
- Comandos: /whitelist (lista), /quitar <nombre>, /ayuda.
- Solo obedece al chat configurado en TELEGRAM_CHAT_ID.

Solo biblioteca estándar. Variables: TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID, RCON_HOST, RCON_PORT,
DATA_DIR (default /data), FLOODGATE_PREFIX (default "."), COOLDOWN_MIN (default 15).
"""
import json
import os
import re
import socket
import struct
import threading
import time
import urllib.parse
import urllib.request

TOKEN = os.environ["TELEGRAM_BOT_TOKEN"].strip()
CHAT_ID = int(os.environ["TELEGRAM_CHAT_ID"].strip())
RCON_HOST = os.environ.get("RCON_HOST", "minecraft-rcon")
RCON_PORT = int(os.environ.get("RCON_PORT", "25575"))
DATA_DIR = os.environ.get("DATA_DIR", "/data")
PREFIX = os.environ.get("FLOODGATE_PREFIX", ".")
COOLDOWN = int(os.environ.get("COOLDOWN_MIN", "15")) * 60
API = f"https://api.telegram.org/bot{TOKEN}"
DENIED = re.compile(r"Disconnecting (\S+) \(/([^)]*)\): You are not whitelisted")
NAME_OK = re.compile(r"^\.?[A-Za-z0-9_ ]{1,32}$")

last_alert = {}  # nombre -> epoch del último aviso


def log(*a):
    print(time.strftime("%Y-%m-%d %H:%M:%S"), *a, flush=True)


# ---------------------------------------------------------------- Telegram
def tg(method, **params):
    data = json.dumps(params).encode()
    req = urllib.request.Request(f"{API}/{method}", data=data,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=70) as r:
        return json.load(r)


def send(text, buttons=None):
    p = {"chat_id": CHAT_ID, "text": text, "parse_mode": "HTML"}
    if buttons:
        p["reply_markup"] = {"inline_keyboard": buttons}
    return tg("sendMessage", **p)


def esc(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


# ---------------------------------------------------------------- RCON
def rcon(cmd):
    pw = ""
    with open(os.path.join(DATA_DIR, ".rcon-cli.env")) as f:
        for line in f:
            if line.startswith("password="):
                pw = line.split("=", 1)[1].strip()
    s = socket.create_connection((RCON_HOST, RCON_PORT), timeout=10)
    try:
        def packet(rid, ptype, body):
            payload = struct.pack("<ii", rid, ptype) + body.encode() + b"\x00\x00"
            s.sendall(struct.pack("<i", len(payload)) + payload)

        def recv():
            ln = struct.unpack("<i", s.recv(4))[0]
            buf = b""
            while len(buf) < ln:
                buf += s.recv(ln - len(buf))
            rid, _ = struct.unpack("<ii", buf[:8])
            return rid, buf[8:-2].decode(errors="replace")

        packet(1, 3, pw)
        if recv()[0] == -1:
            raise RuntimeError("RCON: contraseña rechazada")
        packet(2, 2, cmd)
        return re.sub(r"§.", "", recv()[1]).strip()
    finally:
        s.close()


def add_player(name):
    if name.startswith(PREFIX):
        out = rcon(f"fwhitelist add {name[len(PREFIX):]}")
        kind = "Bedrock"
    else:
        out = rcon(f"whitelist add {name}")
        kind = "Java"
    rcon("whitelist reload")
    return kind, out or "(sin respuesta)"


def remove_player(name):
    if name.startswith(PREFIX):
        out = rcon(f"fwhitelist remove {name[len(PREFIX):]}")
    else:
        out = rcon(f"whitelist remove {name}")
    rcon("whitelist reload")
    return out or "(sin respuesta)"


# ---------------------------------------------------------------- Log
def follow_log():
    path = os.path.join(DATA_DIR, "logs", "latest.log")
    f, inode = None, None
    while True:
        try:
            st = os.stat(path)
            if f is None or st.st_ino != inode or st.st_size < f.tell():
                if f:
                    f.close()
                f = open(path, errors="replace")
                inode = st.st_ino
                if not getattr(follow_log, "started", False):
                    f.seek(0, os.SEEK_END)  # al arrancar, solo eventos nuevos
                    follow_log.started = True
            line = f.readline()
            if not line:
                time.sleep(1)
                continue
            m = DENIED.search(line)
            if m:
                on_denied(m.group(1))
        except FileNotFoundError:
            time.sleep(5)
        except Exception as e:  # noqa: BLE001
            log("error leyendo log:", e)
            time.sleep(5)


def on_denied(name):
    now = time.time()
    if now - last_alert.get(name, 0) < COOLDOWN:
        return
    last_alert[name] = now
    kind = "Bedrock" if name.startswith(PREFIX) else "Java"
    log("intento rechazado:", name, kind)
    send(f"🚫 <b>{esc(name)}</b> ({kind}) intentó entrar al servidor de Minecraft y no está en la whitelist.",
         [[{"text": "✅ Agregar", "callback_data": f"add:{name}"},
           {"text": "Ignorar", "callback_data": f"ign:{name}"}]])


# ---------------------------------------------------------------- Updates
def handle_callback(cq):
    if cq["from"]["id"] != CHAT_ID:
        tg("answerCallbackQuery", callback_query_id=cq["id"], text="No autorizado")
        return
    action, _, name = cq.get("data", "").partition(":")
    msg = cq["message"]
    if not NAME_OK.match(name):
        tg("answerCallbackQuery", callback_query_id=cq["id"], text="Nombre inválido")
        return
    if action == "add":
        try:
            kind, out = add_player(name)
            text = f"✅ <b>{esc(name)}</b> agregado a la whitelist ({kind}).\n<code>{esc(out)}</code>"
        except Exception as e:  # noqa: BLE001
            text = f"⚠️ No se pudo agregar <b>{esc(name)}</b>: <code>{esc(str(e))}</code>"
    else:
        text = f"🙈 Ignorado: <b>{esc(name)}</b>"
    tg("editMessageText", chat_id=msg["chat"]["id"], message_id=msg["message_id"],
       text=text, parse_mode="HTML")
    tg("answerCallbackQuery", callback_query_id=cq["id"])


def handle_message(m):
    if m.get("chat", {}).get("id") != CHAT_ID:
        return
    text = (m.get("text") or "").strip()
    cmd, _, arg = text.partition(" ")
    cmd = cmd.split("@")[0].lower()
    try:
        if cmd in ("/whitelist", "/lista"):
            send(f"📋 <code>{esc(rcon('whitelist list'))}</code>")
        elif cmd == "/quitar" and NAME_OK.match(arg.strip()):
            send(f"🗑️ <code>{esc(remove_player(arg.strip()))}</code>")
        elif cmd in ("/agregar",) and NAME_OK.match(arg.strip()):
            kind, out = add_player(arg.strip())
            send(f"✅ ({kind}) <code>{esc(out)}</code>")
        elif cmd in ("/ayuda", "/help", "/start"):
            send("🤖 Whitelist de Minecraft\n"
                 "/whitelist — ver la lista\n"
                 "/agregar &lt;nombre&gt; — agregar (Bedrock con prefijo «.»)\n"
                 "/quitar &lt;nombre&gt; — quitar\n"
                 "Además te aviso cuando alguien fuera de la lista intente entrar.")
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
            p = {"timeout": 50, "allowed_updates": ["callback_query", "message"]}
            if offset is not None:
                p["offset"] = offset
            for u in tg("getUpdates", **p).get("result", []):
                offset = u["update_id"] + 1
                if "callback_query" in u:
                    handle_callback(u["callback_query"])
                elif "message" in u:
                    handle_message(u["message"])
        except Exception as e:  # noqa: BLE001
            log("error en getUpdates:", e)
            time.sleep(5)


if __name__ == "__main__":
    log("bot de whitelist iniciado; RCON", RCON_HOST, RCON_PORT)
    threading.Thread(target=follow_log, daemon=True).start()
    poll_updates()
