# Arquitectura de la flota

Decisiones con fecha y porqué. Cambiar una decisión = editar aquí, en `flota.yaml` y en `plan.md` si está en curso.

## Uso

Malla privada para seguir 3 trackers (auto + 2 mascotas), con base fija en el techo, nodo personal (Dnto_L1, que
además administra a los demás), nodo del laptop y algunos extras. También sirve para hablar con otras personas en
la malla pública en caso de emergencia.

## Radio (2026-10-18)

- Región `ANZ` (915–928 MHz, 30 dBm): la de Chile según la tabla oficial de Meshtastic.
- Preset `LONG_FAST`. Se evaluó LONG_TURBO: +25 % de velocidad (1,34 vs 1,07 kbps, CR 4/8) a cambio de −3 dB
  (~30 % menos alcance), y no lo usa la malla pública.
- **Frecuencia pública**: `channel_num 0` + canal primario sin nombre → slot por hash de "LongFast" = slot 20
  (~919,875 MHz) de 52 en ANZ. La frecuencia sale **solo del nombre del canal primario** (`RadioInterface.cpp`,
  `channels.getName(channels.getPrimaryIndex())`); los secundarios la heredan. Antes la flota usaba primario
  `DNTGPS` → slot 38 (~924,4 MHz), aislada de la malla pública.
- Hop limit 3. Firma `COMPATIBLE` mientras se reinstala; `BALANCED` al terminar (STRICT cortaría a la malla pública).

## Canales

| Índice | Nombre | PSK | Precisión | Para qué |
|--------|--------|-----|-----------|----------|
| 0 primario | "" (LongFast) | `AQ==` pública | 0 | malla pública: NodeInfo, mensajes de emergencia |
| 1 secundario | privado | 32 B nueva, `use_aead` | 32 | posiciones precisas y mensajes de la flota |

- 2.8 envía la posición por el canal de **índice más bajo con precisión > 0** (`findPositionChannel`), y nunca
  precisa por un canal de llave pública. Con precisión 0 en el público, los trackers solo emiten por el privado.
- La telemetría de dispositivo sale por el primario (público) y en 2.8 viene apagada: dejarla apagada y pedirla por
  DM (PKC) cuando haga falta (`--request-telemetry --dest`).
- NodeInfo (nombre, hw, llave pública) sí se ve en la malla pública: nombres sin datos personales.
- Nombre y URL del canal privado solo en `~/.config/meshtastic-fleet/secretos.yaml`.

## Roles

| Nodo | Rol | Rebroadcast | Por qué |
|------|-----|-------------|---------|
| CarTracker, CatTracker, 2.º tracker | TRACKER | NONE | prioriza su posición; no gasta batería ni aire retransmitiendo tráfico público |
| AcevedoRoof | CLIENT_BASE | ALL | base personal con energía fija: siempre retransmite a sus **favoritos** (toda la flota) y el resto como CLIENT |
| Dnto_L1, laptop | CLIENT | ALL | móviles; aportan a la malla pública |
| SolarT114 | CLIENT | ALL | repetidor solar; firmware sin apagado por batería baja (System OFF no revive en el T114) |

No usar ROUTER/REPEATER: la documentación lo desaconseja salvo en sitios estratégicos.

## Llaves y administración

- Las llaves nacen en cada nodo al fijar la región (instalación limpia, 2026-10-18). ID = `crc32(pubkey)`.
- `security.admin_key` en todos = pubkeys de `admins` (Dnto_L1, AcevedoRoof, laptop; máx. 3). Por eso los admins
  se provisionan **antes** que el resto.
- Si un admin se resetea: su llave cambia → actualizar `flota.yaml` y `aplicar` en los demás por remoto desde otro
  admin. Si se resetea un no-admin: `provisionar` y listo.
- Claude administra con `mt.py` por USB, o por TCP al techo + `--dest`. Sin MCP: el CLI por Bash basta. Un MCP propio
  tendría sentido solo para administrar desde claude.ai sin terminal (encima de la API REST de MeshMonitor).
- `is_managed` apagado (si el admin remoto falla, bloquea la configuración desde apps).

## Homelab

```
 [trackers, Dnto_L1, laptop] ~~LoRa~~ [AcevedoRoof XIAO S3] --WiFi--> LAN --TCP 4403--> MeshMonitor (k3s)
                                                                                        ├─ web UI (Cloudflare Access)
                                                                                        ├─ nodo virtual 4404 (LAN/tailnet) ← CLI, apps
                                                                                        └─ API REST /api/v1 (token)
```

- AcevedoRoof por WiFi con IP fija (reserva DHCP). En ESP32, WiFi activo apaga BLE. Su cable USB a pve es solo de
  energía (2026-10-18: no enumera nada en pve) → no sirve como puente serial.
- MeshMonitor (`ghcr.io/yeraze/meshmonitor`, chart Helm `https://meshmonitor.org/charts`) como única conexión TCP al
  nodo (el firmware atiende un cliente API a la vez); multiplexa con su nodo virtual. "Allow admin commands" solo si
  4404 no sale de LAN/tailnet. AEAD lo descifra desde v4.17.1-rc6.
- Contrato de apps del homelab: skill **homelab**, receta *app nueva*.
- MQTT no hace falta (MeshMonitor lee por TCP). `map_reporting` apagado.
- Bot de Telegram `meshmonitor-bot` (`cluster/apps/meshmonitor/bot`): `/donde` y `/flota` desde la API REST de
  MeshMonitor (token de API). Bot propio: el de Alertmanager comparte token con el de la whitelist de Minecraft.
- Aviso semanal de firmware: CronJob en k3s → Telegram con el bot de Alertmanager (plan, fase 7).
