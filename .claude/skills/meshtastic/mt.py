#!/Users/daniel/.local/pipx/venvs/meshtastic/bin/python -I
"""mt.py: flota Meshtastic de Daniel (estado, respaldo, diff/aplicar contra flota.yaml, novedades upstream).

Ejecutable directo (el shebang usa el python del venv pipx del CLI, que trae la librería meshtastic):
    ~/.claude/skills/meshtastic/mt.py <subcomando> -h

Conexión: --port /dev/cu.x | --host <ip> (TCP 4403) | nada = el único puerto USB detectado.
Nodo remoto: --dest !xxxxxxxx (vía PKC, el nodo conectado debe estar en su security.admin_key).
Todo es lectura salvo `aplicar --apply`.
"""
import argparse
import base64
import datetime as dt
import glob
import json
import os
import shlex
import subprocess
import sys
import urllib.request
from pathlib import Path

AQUI = Path(__file__).resolve().parent
FLOTA = AQUI / "flota.yaml"
VERSIONES = AQUI / "references" / "versiones.json"
PRIVADO = Path.home() / ".config" / "meshtastic-fleet"
SECRETOS = PRIVADO / "secretos.yaml"
RESPALDOS = PRIVADO / "backups"
CLI = str(Path.home() / ".local" / "bin" / "meshtastic")
PATRONES_USB = ["/dev/cu.usbmodem*", "/dev/cu.usbserial*", "/dev/cu.SLAB_USBtoUART*", "/dev/cu.wchusbserial*"]


# ---------- utilidades ----------

def yaml_load(path):
    import yaml  # viene con la librería meshtastic
    with open(path) as f:
        return yaml.safe_load(f) or {}


def puertos_usb():
    return sorted({p for pat in PATRONES_USB for p in glob.glob(pat)})


def args_conexion(a):
    """Argumentos del CLI `meshtastic` equivalentes a la conexión pedida."""
    if a.host:
        out = ["--host", a.host]
    else:
        out = ["--port", resolver_puerto(a)]
    return out + (["--dest", a.dest] if getattr(a, "dest", None) else [])


def resolver_puerto(a):
    if a.port:
        return a.port
    ps = puertos_usb()
    if len(ps) != 1:
        sys.exit(f"Puertos USB candidatos: {ps or 'ninguno'}. Usa --port o --host.")
    return ps[0]


def conectar(a):
    if a.host:
        from meshtastic.tcp_interface import TCPInterface
        return TCPInterface(hostname=a.host, timeout=a.timeout)
    from meshtastic.serial_interface import SerialInterface
    return SerialInterface(devPath=resolver_puerto(a), timeout=a.timeout)


def hace(ts):
    if not ts:
        return "nunca"
    s = int(dt.datetime.now().timestamp() - ts)
    for u, n in (("d", 86400), ("h", 3600), ("m", 60)):
        if s >= n:
            return f"{s // n}{u}"
    return f"{s}s"


def norm(v):
    """Normaliza para comparar valores del YAML con los del protobuf."""
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, float) and v.is_integer():
        return str(int(v))
    return str(v)


def leer_campo(cfg_local, cfg_modulos, clave):
    """Lee `seccion.campo` del protobuf (con defaults), enum como nombre, bytes como base64."""
    sec, campo = clave.split(".", 1)
    raiz = cfg_local if sec in cfg_local.DESCRIPTOR.fields_by_name else cfg_modulos
    if sec not in raiz.DESCRIPTOR.fields_by_name:
        raise KeyError(f"sección desconocida: {sec}")
    msg = getattr(raiz, sec)
    fd = msg.DESCRIPTOR.fields_by_name.get(campo)
    if fd is None:
        raise KeyError(f"campo desconocido: {clave}")
    val = getattr(msg, campo)
    if fd.enum_type is not None:
        return fd.enum_type.values_by_number[val].name
    if not isinstance(val, (str, bytes, int, float, bool)):  # repetido (protobuf ≥5 no expone fd.label)
        return [base64.b64encode(x).decode() if isinstance(x, bytes) else x for x in val if x not in (b"", 0)]
    return val


# ---------- estado deseado ----------

def secretos():
    if not SECRETOS.exists():
        return {}
    if SECRETOS.stat().st_mode & 0o077:
        sys.exit(f"{SECRETOS} debe ser chmod 600")
    return yaml_load(SECRETOS)


def resolver(v, sec):
    if isinstance(v, str) and v.startswith("secreto:"):
        k = v.split(":", 1)[1]
        if k not in sec:
            sys.exit(f"Falta '{k}' en {SECRETOS}")
        return sec[k]
    return v


def deseado(nombre):
    """Une comun → perfil → nodo.set. Devuelve (nodo, {clave: valor}, admin_keys, secretos)."""
    f = yaml_load(FLOTA)
    nodos = f.get("nodos", {})
    if nombre not in nodos:
        sys.exit(f"Nodo '{nombre}' no está en flota.yaml. Hay: {', '.join(nodos)}")
    n = nodos[nombre]
    claves = dict(f.get("comun", {}))
    claves.update(f.get("perfiles", {}).get(n.get("perfil", ""), {}))
    claves.update(n.get("set", {}) or {})
    sec = secretos()
    claves = {k: resolver(v, sec) for k, v in claves.items()}
    admins = []
    for ref in f.get("admins", []):
        pk = nodos.get(ref, {}).get("pubkey")
        if pk:
            admins.append(pk)
    return n, claves, admins, sec


# ---------- subcomandos ----------

def cmd_puertos(a):
    ps = puertos_usb()
    print("\n".join(ps) if ps else "Sin puertos USB de radio (¿cable solo de carga? ¿nodo dormido?)")


def cmd_estado(a):
    iface = conectar(a)
    try:
        f = yaml_load(FLOTA) if FLOTA.exists() else {}
        por_pk = {v.get("pubkey"): k for k, v in f.get("nodos", {}).items() if v.get("pubkey")}
        me = iface.getMyNodeInfo()
        meta = iface.metadata
        lc = iface.localNode.localConfig
        print(f"{me['user']['longName']} ({me['user']['id']}) {me['user'].get('hwModel')} "
              f"pio {getattr(iface.myInfo, 'pio_env', '?')} "
              f"fw {getattr(meta, 'firmware_version', '?')} rol {leer_campo(lc, iface.localNode.moduleConfig, 'device.role')}")
        print(f"lora: {lc.lora.region and leer_campo(lc, iface.localNode.moduleConfig, 'lora.region')} "
              f"{leer_campo(lc, iface.localNode.moduleConfig, 'lora.modem_preset')} hop {lc.lora.hop_limit} slot {lc.lora.channel_num}")
        print(f"red: wifi {lc.network.wifi_enabled} ssid '{lc.network.wifi_ssid}' | bt {lc.bluetooth.enabled}")
        adm = [por_pk.get(base64.b64encode(k).decode(), base64.b64encode(k).decode()[:12] + "…")
               for k in lc.security.admin_key if k]
        print(f"admin_key: {adm or 'ninguna'} | firma: {leer_campo(lc, iface.localNode.moduleConfig, 'security.packet_signature_policy')}")
        for ch in iface.localNode.channels or []:
            if ch.role:
                print(f"canal {ch.index} {['DISABLED','PRIMARY','SECONDARY'][ch.role]} '{ch.settings.name}' "
                      f"psk {len(ch.settings.psk)}B precision {ch.settings.module_settings.position_precision} "
                      f"aead {ch.settings.use_aead}")
        print("nodos oídos:")
        for n in sorted(iface.nodes.values(), key=lambda x: -(x.get("lastHeard") or 0)):
            u = n.get("user", {})
            print(f"  {u.get('id','?'):10} {u.get('longName','?')[:18]:18} {u.get('hwModel','?')[:22]:22} "
                  f"{u.get('role','CLIENT'):12} hace {hace(n.get('lastHeard')):>5} snr {n.get('snr','-')} "
                  f"hops {n.get('hopsAway','-')}{' ★' if n.get('isFavorite') else ''}")
    finally:
        iface.close()


def cmd_respaldo(a):
    RESPALDOS.mkdir(parents=True, exist_ok=True)
    os.chmod(PRIVADO, 0o700)
    os.chmod(RESPALDOS, 0o700)
    iface = conectar(a)
    try:
        u = iface.getMyNodeInfo()["user"]
        from meshtastic.__main__ import export_config, export_profile
        base = RESPALDOS / f"{u['longName']}-{u['id'].lstrip('!')}-{dt.date.today()}"
        for ext, data in ((".yaml", export_config(iface).encode()), (".cfg", export_profile(iface))):
            p = base.with_suffix(ext)
            p.write_bytes(data)
            os.chmod(p, 0o600)
            print(f"{p} ({len(data)} B)")
    finally:
        iface.close()


def comparar(a, nombre):
    n, claves, admins, sec = deseado(nombre)
    iface = conectar(a)
    try:
        if a.dest:
            node = iface.getNode(a.dest, requestChannels=False, timeout=a.timeout)
            from meshtastic.protobuf import localonly_pb2
            vistos = set()
            for k in claves:
                sec_name = k.split(".")[0]
                if sec_name in vistos:
                    continue
                vistos.add(sec_name)
                lf = localonly_pb2.LocalConfig.DESCRIPTOR.fields_by_name.get(sec_name)
                mf = localonly_pb2.LocalModuleConfig.DESCRIPTOR.fields_by_name.get(sec_name)
                node.requestConfig(lf or mf)
            if admins:
                node.requestConfig(localonly_pb2.LocalConfig.DESCRIPTOR.fields_by_name["security"])
            nodo_id = a.dest
            user = (iface.nodes or {}).get(a.dest, {}).get("user", {})
            url = None
        else:
            node = iface.localNode
            user = iface.getMyNodeInfo()["user"]
            nodo_id = user["id"]
            url = node.getURL()
        if n.get("id") and n["id"] != nodo_id:
            sys.exit(f"Conectado a {nodo_id}, pero flota.yaml dice que {nombre} es {n['id']}. Nada que comparar.")
        sets, diffs = [], []
        for k, v in claves.items():
            actual = leer_campo(node.localConfig, node.moduleConfig, k)
            if norm(actual) != norm(v):
                oculto = "***" if "psk" in k or "password" in k else None
                diffs.append(f"{k}: {oculto or actual!r} → {oculto or v!r}")
                sets += ["--set", k, norm(v)]
        actuales = set(leer_campo(node.localConfig, node.moduleConfig, "security.admin_key"))
        for pk in admins:
            if pk not in actuales:
                diffs.append(f"security.admin_key: falta {pk[:12]}…")
                sets += ["--set", "security.admin_key", f"base64:{pk}"]
        sobran = actuales - set(admins)
        if sobran:
            diffs.append(f"security.admin_key: sobran {[s[:12] + '…' for s in sobran]} (no se quitan solas)")
        owner = []
        if n.get("owner") and user.get("longName") != n["owner"]:
            diffs.append(f"owner: {user.get('longName')!r} → {n['owner']!r}")
            owner += ["--set-owner", n["owner"]]
        if n.get("owner_short") and user.get("shortName") != n["owner_short"]:
            diffs.append(f"owner_short: {user.get('shortName')!r} → {n['owner_short']!r}")
            owner += ["--set-owner-short", n["owner_short"]]
        canal = []
        if url is not None and sec.get("canal_url") and url != sec["canal_url"]:
            diffs.append("canales: la URL no coincide con secretos.yaml:canal_url")
            canal = ["--seturl", sec["canal_url"]]
        return diffs, sets, owner, canal
    finally:
        iface.close()


def mostrar_cmd(partes):
    out, ocultar = [], False
    for p in partes:
        out.append("***" if ocultar else shlex.quote(p))
        ocultar = p in ("network.wifi_psk", "mqtt.password", "--seturl")
    return " ".join(out)


def cmd_diff(a):
    diffs, sets, owner, canal = comparar(a, a.nodo)
    if not diffs:
        print(f"{a.nodo}: coincide con flota.yaml")
        return
    print(f"{a.nodo}: {len(diffs)} diferencia(s)")
    for d in diffs:
        print(f"  {d}")
    for grupo in (sets, owner, canal):
        if grupo:
            print("  $ meshtastic " + mostrar_cmd(args_conexion(a) + grupo))


def cmd_aplicar(a):
    diffs, sets, owner, canal = comparar(a, a.nodo)
    if not diffs:
        print(f"{a.nodo}: nada que aplicar")
        return
    for d in diffs:
        print(f"  {d}")
    # Canales primero (la URL trae lora), luego --set (una transacción), al final el dueño.
    for grupo in (canal, sets, owner):
        if not grupo:
            continue
        cmd = [CLI, "--timeout", str(a.timeout)] + args_conexion(a) + grupo
        print("$ " + mostrar_cmd(cmd))
        if a.apply:
            r = subprocess.run(cmd)
            if r.returncode:
                sys.exit(f"Falló (código {r.returncode}); los pasos siguientes no se ejecutaron.")
    if not a.apply:
        print("(dry-run: agrega --apply)")


def descargar(url, destino):
    if not destino.exists():
        destino.parent.mkdir(parents=True, exist_ok=True)
        print(f"descargando {url}")
        tmp = destino.with_suffix(".part")
        urllib.request.urlretrieve(url, tmp)
        tmp.rename(destino)
    return destino


def cmd_fw(a):
    """Prepara (descarga, extrae, verifica md5) los archivos de un nodo e imprime cómo flashear. No flashea."""
    import hashlib
    import zipfile
    f = yaml_load(FLOTA)
    ver = a.version or f["firmware"]
    n = f["nodos"].get(a.nodo) or sys.exit(f"Nodo '{a.nodo}' no está en flota.yaml")
    pio = n.get("pio") or sys.exit(f"{a.nodo} no tiene `pio` en flota.yaml (sale como pioEnv en `estado`)")
    base = Path.home() / ".cache" / "meshtastic-fw" / ver
    url = f"https://github.com/meshtastic/firmware/releases/download/v{ver}"
    targets = json.loads(descargar(f"{url}/firmware-{ver}.json", base / "firmware.json").read_text())["targets"]
    arch = next((t["platform"] for t in targets if t["board"] == pio), None) or sys.exit(f"{pio} no está en {ver}")
    z = zipfile.ZipFile(descargar(f"{url}/firmware-{arch}-{ver}.zip", base / f"firmware-{arch}.zip"))
    out = base / pio
    out.mkdir(exist_ok=True)
    meta = json.loads(z.read(f"firmware-{pio}-{ver}.mt.json"))
    nombres = [x for x in meta["files"] if not x["name"].endswith((".elf", ".hex"))]
    extra = ["device-install.sh"] if arch.startswith("esp32") else \
        [m for m in z.namelist() if m.startswith("Meshtastic_nRF52_factory_erase")]
    for x in nombres + [{"name": e} for e in extra]:
        dato = z.read(x["name"])
        if x.get("md5") and hashlib.md5(dato).hexdigest() != x["md5"]:
            sys.exit(f"md5 no coincide: {x['name']}")
        (out / x["name"]).write_bytes(dato)
    os.chmod(out / "device-install.sh", 0o755) if arch.startswith("esp32") else None
    print(f"{a.nodo}: {meta.get('displayName', pio)} ({arch}) {ver} → {out} (md5 verificado)")
    if arch.startswith("esp32"):
        print("Full erase + flash (borra llaves y config; restaurar el .cfg después):")
        print(f"  1. $T respaldo --port <puerto>")
        print(f"  2. cd {out} && ./device-install.sh -p <puerto> -f firmware-{pio}-{ver}.factory.bin")
        print("     (si no entra en modo descarga: mantener BOOT/PRG al conectar el USB, o --1200bps-reset antes)")
        print(f"  Sin borrar (actualización): meshtastic --host <ip> --ota-update {out}/firmware-{pio}-{ver}.bin")
    else:
        print("Full erase + flash (nRF52, unidad USB en modo DFU):")
        print("  1. $T respaldo --port <puerto>")
        print("  2. meshtastic --port <puerto> --enter-dfu   (o doble clic en reset; T1000-E: botón al conectar USB)")
        print("  3. Ver la SoftDevice en INFO_UF2.TXT de la unidad y copiar el erase que coincida:")
        for e in extra:
            print(f"       cp {out / e} /Volumes/<unidad>/")
        print("  4. Volver a entrar en DFU y copiar el firmware:")
        print(f"       cp {out}/firmware-{pio}-{ver}.uf2 /Volumes/<unidad>/")


def gh(url):
    req = urllib.request.Request(url, headers={"User-Agent": "mt.py", "Accept": "application/vnd.github+json"})
    tok = os.environ.get("GITHUB_TOKEN")
    if tok:
        req.add_header("Authorization", f"Bearer {tok}")
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.load(r)


def cmd_upstream(a):
    vis = json.loads(VERSIONES.read_text()) if VERSIONES.exists() else {}
    nuevo = {}
    rels = gh("https://api.github.com/repos/meshtastic/firmware/releases?per_page=8")
    print("Firmware (meshtastic/firmware):")
    for r in rels:
        etiqueta = "revocada" if "revoked" in (r["name"] or "").lower() else ("pre" if r["prerelease"] else "estable")
        marca = " ← NUEVA" if r["tag_name"] not in vis.get("firmware_vistas", []) else ""
        print(f"  {r['tag_name']:22} {r['published_at'][:10]} {etiqueta:9} {r['name']}{marca}")
    nuevo["firmware_vistas"] = sorted({r["tag_name"] for r in rels} | set(vis.get("firmware_vistas", [])))
    c = gh("https://api.github.com/repos/meshtastic/python/commits?per_page=10")
    print("CLI python (master):")
    for x in c:
        marca = " ← nuevo" if x["sha"] not in vis.get("cli_commits_vistos", []) else ""
        print(f"  {x['sha'][:8]} {x['commit']['committer']['date'][:10]} {x['commit']['message'].splitlines()[0][:80]}{marca}")
    nuevo["cli_commits_vistos"] = [x["sha"] for x in c]
    try:
        with urllib.request.urlopen("https://pypi.org/pypi/meshtastic/json", timeout=20) as r:
            pypi = json.load(r)["info"]["version"]
        print(f"  PyPI: {pypi}{' ← NUEVA' if pypi != vis.get('cli_pypi') else ''}")
        nuevo["cli_pypi"] = pypi
    except Exception as e:  # PyPI a veces responde con desafío anti-bot
        print(f"  PyPI: sin respuesta ({e})")
    mm = gh("https://api.github.com/repos/Yeraze/meshmonitor/releases?per_page=4")
    print("MeshMonitor:")
    for r in mm:
        marca = " ← NUEVA" if r["tag_name"] not in vis.get("meshmonitor_vistas", []) else ""
        print(f"  {r['tag_name']:16} {r['published_at'][:10]} {'pre' if r['prerelease'] else 'estable'}{marca}")
    nuevo["meshmonitor_vistas"] = sorted({r["tag_name"] for r in mm} | set(vis.get("meshmonitor_vistas", [])))
    if a.marcar:
        nuevo["revisado"] = str(dt.date.today())
        VERSIONES.write_text(json.dumps(nuevo, indent=1) + "\n")
        print(f"Marcado como revisado en {VERSIONES}")
    else:
        print("Leer las notas de lo NUEVO, actualizar references/firmware.md y luego `upstream --marcar`.")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)

    def con(sp, dest=False):
        sp.add_argument("--port")
        sp.add_argument("--host")
        sp.add_argument("--timeout", type=int, default=60)
        if dest:
            sp.add_argument("--dest", help="nodo remoto !xxxxxxxx (admin por PKC)")
        return sp

    sub.add_parser("puertos", help="puertos USB que parecen radios")
    con(sub.add_parser("estado", help="resumen del nodo conectado y de los nodos que oye"))
    con(sub.add_parser("respaldo", help=f"exporta .yaml y .cfg (con llave privada) a {RESPALDOS}"))
    sp = con(sub.add_parser("diff", help="compara un nodo con flota.yaml e imprime el comando que lo corrige"), dest=True)
    sp.add_argument("nodo")
    sp = con(sub.add_parser("aplicar", help="lleva un nodo al estado de flota.yaml (dry-run salvo --apply)"), dest=True)
    sp.add_argument("nodo")
    sp.add_argument("--apply", action="store_true")
    sp = sub.add_parser("fw", help="descarga y verifica el firmware de un nodo e imprime los pasos de flasheo")
    sp.add_argument("nodo")
    sp.add_argument("--version", help="por defecto: `firmware` de flota.yaml")
    sp = sub.add_parser("upstream", help="releases nuevas de firmware, CLI y MeshMonitor desde la última revisión")
    sp.add_argument("--marcar", action="store_true", help="registrar lo listado como revisado")
    a = p.parse_args()
    {"puertos": cmd_puertos, "estado": cmd_estado, "respaldo": cmd_respaldo, "diff": cmd_diff,
     "aplicar": cmd_aplicar, "fw": cmd_fw, "upstream": cmd_upstream}[a.cmd](a)


if __name__ == "__main__":
    main()
