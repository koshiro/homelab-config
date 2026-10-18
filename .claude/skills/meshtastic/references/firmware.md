# Firmware: qué cambió y qué significa para esta flota

Revisado: 2026-10-18 (`mt.py upstream --marcar` registra la fecha en `versiones.json`). Al leer una release nueva:
agregar arriba una sección con *qué cambia para esta flota*, no copiar el changelog.

## Build fijado: nightly 2.8.2.fad52bb (decisión 2026-10-18)

`develop` del 2026-10-17, 97 commits sobre v2.8.1.8e6a88d. Se publica en `https://nightly.meshtastic.org`
(`index.json` + archivos sueltos, sin zips) y **se reemplaza a diario**: archivado con md5 en
`~/.cache/meshtastic-fw/2.8.2.fad52bb/<pio>/` (`mt.py fw --solo-bajar`). Respaldo si se pierde: artefactos de GitHub
Actions del commit (`gh run download`, ~90 días). No hace falta compilar.

Arreglos sobre 2.8.1 que importan a esta flota:
- #12088 / #12090: relays de NodeInfo/NeighborInfo ya no reescriben el payload (rompía firmas).
- #12076: USB serial (HWCDC) trabado en ESP32-S3 (Heltec tracker, XIAO S3) → CLI más estable.
- #12131: crash de light sleep en ESP32 (tormenta de ISR en DIO1). #12141/#12160: light sleep con consola USB.
- #12168: crash al activar Store & Forward. #11930: guardados diferidos de NodeDB que se perdían.
- #12098: X25519/Ed25519 en el CC310 del nRF52840 (T1000-E, Wio L1). #12095: clamp de llave privada importada.
- #12145: `ls_secs` sobrevive la ida y vuelta por la app. #12039: quita el clamp de precisión de posiciones
  retransmitidas. #11765: ventana de dedup de posición a 6 h.
Riesgo: capa de radio muy cambiada (LBT CAD-to-RX #11137, RX en tarea FreeRTOS #11983, preámbulo #12125, AGC #12072)
sin pasar por release → canario 24–48 h.
Pendiente en develop (sin merge al 2026-10-18): #12180 *CLIENT_BASE: fill in broadcasts for favorited neighbors*
(afecta a AcevedoRoof).

## Releases vigentes (2026-10-18)

| Tag | Estado | Uso |
|-----|--------|-----|
| v2.8.1.8e6a88d (2026-10-01) | Alpha, única release 2.8 válida | vuelta atrás desde el nightly |
| v2.8.0.47db0e3 / v2.8.0.7239fe8 | Revocadas | nunca; firma incompatible con 2.8.1 |
| v2.7.26.54e0d8d (2026-06-24) | Beta con badge "Latest" | no: la flota usa funciones 2.8 (AEAD, firma) |

Fuentes: https://github.com/meshtastic/firmware/releases · https://meshtastic.org/blog/lets-talk-about-2-8/ ·
docs 2.8 (https://meshtastic.org/docs/configuration/radio/lora/ y .../security/).

## 2.8: cambios que afectan a esta flota

- **Número de nodo = `crc32(public_key)`** (antes: MAC). Verificado 2026-10-18 en los 4 nodos. Un full erase da
  llave y número nuevos (la flota se reinstala así a propósito); si es un admin, actualizar `admin_key` en los demás. NodeInfo de nodos remotos
  trae MAC `00:00:…` (normal).
- **Firma de paquetes** (XEdDSA, con la llave de identidad). `security.packet_signature_policy`:
  `COMPATIBLE` (defecto, acepta sin firma) · `BALANCED` (exige firma a quien ya firmó) · `STRICT` (solo verificados
  y DMs PKC; corta nodos 2.7 y STM32WL y puede hacer ver ACKs como no entregados). Firma inválida se descarta siempre.
  Los ACK llevan `ack_proof`.
- **Privacidad**: posición y telemetría apagadas por defecto en canales públicos (PSK por defecto); posición
  precisa prohibida en canales de llave conocida. La posición sale por el canal de índice más bajo con precisión > 0 (`findPositionChannel`); con el público en 0,
  va solo por el privado.
- **Presets**: LONG_TURBO es el defecto **solo** para nodos US cuya región se elige por primera vez en pantalla;
  actualizar no cambia el preset. Nuevos: MEDIUM_TURBO, LITE_*, NARROW_*, TINY_*, SF5/6 en SX126x/LR11xx. Un preset
  que la región no permite: localmente se reemplaza por el defecto de la región; **por admin remoto se rechaza
  todo el cambio**. Cambios LoRa se aplican sin reiniciar.
- **Canales AEAD**: `channel.use_aead` (AES-CCM autenticado), activo en el canal privado (toda la flota en 2.8.x).
  MeshMonitor lo descifra desde v4.17.1-rc6.
- **Long name** recortado a 24–25 bytes (el blog dice 24, la release 25: usar ≤24). Emojis cuentan 4 bytes.
- **Traffic management** (deduplicación, límites de tasa, hop limit variable con la congestión) y NodeDB
  dimensionada según la RAM de cada placa. Módulo nuevo `mesh_beacon`.
- **Filesystem cambió de formato**: tras actualizar, revisar la config; si hay bootloop → full erase + restaurar.
- Arreglos útiles: posición fija se emite bien (2.7.24–2.7.26 mandaban 0,0); corrupción de flash en nRF52 que borraba
  región/canales/llaves (error crítico #13); ACK de DM llega aunque no se comparta canal.
- Eliminado: nRF52832, región UA_868, compresión unishox2 de ATAK.

## Placas de la flota en 2.8.1

| Nodo | Placa (pioEnv) | MCU | Flasheo |
|------|----------------|-----|---------|
| CarTracker | heltec-wireless-tracker (V1.1) | esp32s3 | `device-install.sh` (esptool) o OTA WiFi |
| AcevedoRoof | seeed-xiao-s3 (+ Wio-SX1262) | esp32s3 | `device-install.sh` o `--ota-update` por WiFi |
| CatTracker | tracker-t1000-e | nrf52840 (LR1110) | UF2; la 2.8.0.7239fe8 se revocó por fallar el LR1110 del T1000-E |
| Dnto_L1 | seeed_wio_tracker_L1 | nrf52840 | UF2 |

Ninguna nota de 2.8.x menciona problemas específicos de estas placas (salvo el T1000-E en la 2.8.0 revocada).

## Historial de builds en la flota

- 2026-10-18: CarTracker tenía `2.8.1.43479aa`, build de desarrollo del 2026-09-21 (17 commits **antes** de la
  release 8e6a88d, no publicada). Probable causa de los problemas de la actualización manual → reflashear la release.
