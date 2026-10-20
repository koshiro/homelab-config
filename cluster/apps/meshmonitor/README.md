# MeshMonitor

Panel web de la flota Meshtastic (mapa, nodos, mensajes, telemetría, admin remoto). Configuración de la flota y
decisiones: skill `meshtastic` (`flota.yaml`, `references/arquitectura.md`).

| | |
|---|---|
| Imagen | `ghcr.io/yeraze/meshmonitor:4.17.0` (actualizar a mano; `mt.py upstream` avisa versiones nuevas) |
| Web | `https://meshmonitor.danielriquelme.cl`, detrás de la app de Cloudflare Access «Homelab admin» |
| Fuente | TCP a AcevedoRoof `192.168.1.105:4403` (sembrada por `MESHTASTIC_NODE_IP` solo en el primer arranque) |
| Nodo virtual | `192.168.1.15:4404` (cualquier nodo k3s), solo LAN/tailnet; **se activa en la UI** (abajo) |
| Datos | PVC local-path `meshmonitor-data` en `/data` (SQLite); respaldo `config-backup-meshmonitor` 02:47 |
| Secreto | `secret.sops.yaml`: `SESSION_SECRET` |

El firmware del nodo atiende **un solo cliente TCP**: con MeshMonitor arriba, el CLI y las apps van al nodo virtual
(`meshtastic --host 192.168.1.15:4404`), no a `192.168.1.105:4403` (eso desconecta a MeshMonitor).

## Primer arranque (una vez)

1. Entrar a la web: usuario `admin`, clave `changeme` → **cambiarla** (menú de usuario).
2. Dashboard → Sources → fuente AcevedoRoof → Edit → Virtual Node: activar, puerto `4404`, «Allow admin commands» activo
   (el puerto no sale de LAN/tailnet) → Save.
3. Probar: `meshtastic --host 192.168.1.15:4404 --nodes`.

## Bot de Telegram (`bot/`)

`meshmonitor-bot`: bot propio (BotFather), no el de Alertmanager/whitelist, porque `getUpdates` no admite dos
consumidores con el mismo token. Lee `/api/v1/sources/{id}/nodes` con un token de API de MeshMonitor; no habla con
el nodo. Solo responde al chat de `TELEGRAM_CHAT_ID`.

| Comando | Qué hace |
|---|---|
| `/donde` | ubicación (mapa) de los nodos con `tracker: true` en `NODOS`, con edad de la posición, saltos, SNR y batería |
| `/donde <alias>` | un nodo: `akira`, `gato`, `auto`, `techo`, `l1`, … (alias en `NODOS` del Deployment) |
| `/flota` | cuándo oyó AcevedoRoof a cada nodo; ⚠️ si pasaron más de `FUERA_MIN` (120) minutos |

Secreto `bot/secret.sops.yaml`: `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`, `MM_TOKEN` (token de API creado en la UI de
MeshMonitor). Nodo nuevo en la flota → agregarlo a `NODOS`.
