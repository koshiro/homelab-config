# Plan: reinstalación limpia de la flota (acordado 2026-10-18)

Estado: marcar `[x]` al cerrar cada paso. La fase en curso es la primera con pasos sin marcar.

## Decisiones (2026-10-18)

| Tema | Decisión | Por qué |
|------|----------|---------|
| Firmware | nightly **2.8.2.fad52bb** fijo (develop, 2026-10-17), archivado con md5 | arreglos de firma en relays, USB serial ESP32-S3, S&F, NodeDB sobre la 2.8.1 alpha |
| Vigilancia | revisión semanal de commits/releases; aviso por Telegram solo si hay razón para cambiar de build | el nightly se reemplaza a diario y no tiene notas |
| Frecuencia | **pública** ANZ LONG_FAST (slot 20, primario sin nombre + `AQ==`) + canal secundario privado | poder hablar con otros en emergencias y que nodos públicos retransmitan |
| Llaves | nacen en cada nodo (instalación limpia, IDs nuevos) | tras un reset, reprovisionar es un solo comando y no hay llaves privadas fuera del nodo |
| Canal privado | PSK nueva de 32 B, `use_aead true`, `position_precision 32` | máxima protección; la posición sale por el canal de índice más bajo con precisión > 0 |
| Homelab | AcevedoRoof por WiFi + MeshMonitor | el cable USB a pve es solo de energía (verificado: no enumera) |

## Fase 1: preparar (Claude, ~1 h)

- [x] `mt.py fw` con soporte para nightly (`nightly.meshtastic.org`) y archivo local; bajar fad52bb de las 4 placas.
- [x] Archivar fad52bb para el Laptop (XIAO S3, mismo archivo que el techo).
- [ ] Archivar el firmware del segundo tracker (hardware por confirmar).
- [x] `flota.yaml` con el diseño nuevo (sin IDs; canales y perfiles) y `mt.py provisionar <nodo>`:
      región → llaves → anotar id/pubkey en flota.yaml → canales → perfil → admin_key → respaldo.
- [x] Corregir `arquitectura.md`, `recetas.md` (orden admins primero) y el PR #118.

## Fase 2–3: nodos en mano (cambio de orden 2026-10-18: el techo va al final para tener la lista completa de favoritos)

- [x] Dnto_L1 `!185e9038`, Laptop `!0404f6d2`, CarTracker `!ddb5828c` (con `power.sds_secs 300`) en 2.8.2.fad52bb,
      provisionados y coincidiendo con flota.yaml. Canal privado AEAD probado (mensajes en canal 1) y admin remoto
      PKC probado (Laptop → CarTracker por radio).
- [ ] CarTracker 24–48 h en uso: GPS, posición por el canal privado, que despierte al cargar tras batería baja.

## Fase 4: resto y techo

- [x] CatTracker `!1e945bee` y AkiraGPS `!66f2bcce` (T1000-E) en 2.8.2.fad52bb, provisionados.
- [x] T1000-E despierta de System OFF al conectar el USB → trackers con `is_power_saving false`.
- [x] Extras: BlackHeltecV3 `!6de158c2`, OrangeHeltecV3 `!583acc8e` (Heltec V3).
- [x] AcevedoRoof `!918d5bf9` (venía en la 2.8.0 **revocada**) reinstalado con WiFi: 192.168.1.105, MAC 80:b5:4e:f1:0d:fc.
      TCP 4403 accesible desde la Mac, pve y k3s-node-1. Contactos con llave de los 7 nodos cargados (`mt.py favoritos`).
- [x] Favoritos verificados en el techo (7). Ya oye ~25 nodos de la malla pública de Santiago.
- [ ] Reserva DHCP de 192.168.1.105 en el router (usuario).
- [ ] Agregar la llave del techo a todos (Laptop ya la tiene): `aplicar <nodo> --dest '!id' --apply` desde Dnto_L1 o Laptop.

## Fase 5: ajuste (~30 min)

- [ ] Favoritos en AcevedoRoof (toda la flota). Firma `BALANCED` en todos.
- [ ] Probar admin remoto: Mac → TCP techo → `--dest` a un tracker.
- [ ] Respaldo de todos.

## Fase 5b: MQTT (PR #123, decidido 2026-10-18 para unir un nodo solar con WiFi en Temuco)

- [x] Broker Mosquitto en k3s (`cluster/apps/mqtt`): TLS 8883, usuarios `roof`/`temuco`, DDNS `mqtt.danielriquelme.cl`.
- [ ] Merge del PR #123 y verificar el pod.
- [ ] Router (usuario): WAN TCP 8883 → 192.168.1.15:8883 (ver `cluster/apps/mqtt/README.md`).
- [ ] `aplicar AcevedoRoof --host 192.168.1.105 --apply` (MQTT + uplink/downlink del canal privado) y ver tráfico en
      `mosquitto_sub`. `config_ok_to_mqtt` al resto de la flota con `aplicar` (USB o remoto).
- [ ] Nodo de Temuco: perfil `base` con `gateway: true`, `mqtt.address mqtt.danielriquelme.cl`, usuario `temuco`.

## Fase 6: homelab (1–2 h, PR)

- [ ] MeshMonitor en k3s (Flux, contrato de apps), fuente TCP al techo, nodo virtual solo LAN/tailnet,
      UI tras Cloudflare Access.

## Fase 7: vigilancia (~1 h, PR)

- [ ] CronJob semanal en k3s: commits de develop y releases desde el build fijado; aviso por Telegram (bot de
      Alertmanager) si hay release nueva, el build fijado fue revocado, o commits que tocan placas/funciones de la
      flota (esp32s3, nrf52, T1000-E/LR1110, Wio L1, XIAO, Heltec tracker, firma, PKC, TRACKER, CLIENT_BASE, crash).
- [ ] Al llegar un aviso: Claude estudia los commits, decide y anota en `firmware.md`.
