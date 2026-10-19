# Hechos estables y trampas

## Datos (con fecha)

- Respaldos privados: `~/.config/meshtastic-fleet/backups/<longName>-<id>-<fecha>.{yaml,cfg}` (700/600).
  Secretos: `~/.config/meshtastic-fleet/secretos.yaml` (600; claves `canal_privado_nombre`, `canal_privado_psk`, `wifi_ssid`, `wifi_psk`;
  `canal_url` = URL del diseño viejo, solo para volver atrás).
- Firmware descargado y verificado: `~/.cache/meshtastic-fw/<versión>/<pio>/`.
- CLI desde fuente: `~/.local/src/meshtastic-python` (master 0a183576, protobufs 2.8.1), venv
  `~/.local/pipx/venvs/meshtastic`. (2026-10-18)
- Repo viejo con experimentos MQTT/bridge: `~/git/meashtastic-router` (2025, no usado por la flota actual).
- CarTracker por USB en la Mac aparece como `/dev/cu.usbmodem101`. (2026-10-18)
- El cable USB largo de AcevedoRoof a pve es **solo de energía**: en pve no enumera nada (solo el NanoKVM) ni hay
  errores de enumeración en el kernel. (2026-10-18)
- Slots en ANZ con LONG_FAST: 52; malla pública ("LongFast") = slot 20 (~919,875 MHz); el viejo primario `DNTGPS`
  = slot 38. Hash djb2 del nombre del primario % 52. (2026-10-18)
- `!793a3263` "Meshtastic 3263" era el propio Dnto_L1 tras un reset (antes de ponerle nombre), no un nodo ajeno.
- Puertos en la Mac (2026-10-18, pueden cambiar): Laptop `/dev/cu.usbmodem101`, Dnto_L1 `/dev/cu.usbmodem11201`,
  CarTracker `/dev/cu.usbmodem11301`. Identificar siempre con `$T estado --port`.
- Wio Tracker L1: bootloader UF2 0.9.2, SoftDevice S140 7.3.0, unidad `TRACKER L1`. El erase v3 termina solo y
  vuelve a la unidad UF2 (~10 s). (2026-10-18)
- CarTracker (Heltec Wireless Tracker V1.1) se dormía para siempre con batería baja: el firmware entra en deep sleep
  por `power.sds_secs` (si es 0 o UINT32_MAX ≈ 50 días) y la placa no tiene pin que la despierte al cargar. Con
  `power.sds_secs 300` se revisa cada 5 min (`Power.cpp` `updateLowVoltageCounter`: <3,1 V, 10 lecturas, sin USB).
- AcevedoRoof: 192.168.1.105 (WiFi `WiFi_Mesh-532670`), MAC 80:b5:4e:f1:0d:fc, TCP 4403 abierto a la LAN; alcanzable
  desde pve y los workers k3s. (2026-10-18)
- Broker MQTT: `cluster/apps/mqtt` (PR #123). LAN `192.168.1.15:8883`, internet `mqtt.danielriquelme.cl:8883`, TLS
  autofirmado (copia en `~/.config/meshtastic-fleet/mqtt-ca.crt`), claves en `secretos.yaml` (`mqtt_pass_*`).
  Firmware (MQTT.cpp): `setInsecure()`; con broker de IP privada sube paquetes ajenos sin `ok_to_mqtt`. (2026-10-18)
- MeshMonitor (2026-10-19): `cluster/apps/meshmonitor`, conectado a AcevedoRoof 4403. Con él arriba, **no** conectar el CLI a
  `192.168.1.105:4403` (el ESP32 atiende un cliente TCP y desconecta a MeshMonitor): usar el nodo virtual
  `192.168.1.15:4404` (cuando esté activo en la UI). Web tras Cloudflare Access.
- Telegram del homelab: bot de Alertmanager (`cluster/03-monitoring/monitoring/secret-alertmanager-telegram.sops.yaml`).
- Respaldo CarTracker 2026-10-18: `bluetooth.fixed_pin 123456` (modo RANDOM_PIN), store&forward cliente activo,
  `canned_messages` Hi|Bye|Yes|No|Ok, MQTT apagado.

- GPS de los T1000-E (AG3335, fw 2.8.2.fad52bb): entre fixes queda en backup con VRTC (#11889) y conserva efemérides →
  hot start. Sin softsleep. Primera búsqueda tras encender o reactivar el GPS: hasta `position_broadcast_secs` (tope
  15 min). Si falla: espera `position_broadcast_secs` (tope 1 h) y reintenta ≤5 min. Triple clic = GPS off/on;
  al reactivarlo (`enable()` → `scheduling.reset()`) busca de inmediato sin backoff. Indoor no hay fix. (2026-10-19)
  CatTracker apareció con `gps_mode DISABLED` (triple clic accidental en el collar): si un tracker no da fix,
  revisar primero `diff --dest`. (2026-10-19)

## Trampas (`error → forma correcta`)

- Por el nodo virtual de MeshMonitor el firmware sale como `2.8.2.fad52bb-MM4.17.0`, sin `pio`, y el canal 0 como
  `LongFast` (no "") → mt.py lo trata como igual; no aplicar el `--seturl` que salga solo por eso.
- App web tras Cloudflare + Traefik con cookies `Secure` → login falla (CSRF mismatch): Traefik reenvía
  `X-Forwarded-Proto: http` → Middleware `customRequestHeaders X-Forwarded-Proto: https` (PR #126).

- `meshtastic --host <techo> --set mqtt.…` → «Writing mqtt configuration» pero no se guarda: el CLI cierra el TCP antes
  de que el firmware valide (prueba de conexión al broker) y guarde → `mt.py aplicar --host` escribe por la API y
  espera 15 s antes de cerrar. (2026-10-19)
- Mosquitto con `readOnlyRootFilesystem`: `mosquitto_passwd -U` necesita `/tmp` escribible (PR #124).

- Laptop (XIAO S3) deja de contestar la API por USB tras varias operaciones admin seguidas («Timed out waiting for
  connection completion») → `esptool --port <p> --after hard-reset chip-id` lo reinicia sin borrar nada. (2026-10-19)

- Heltec Wireless Tracker: `Failed to connect … No serial data received` tras un flasheo cortado → bootloader a mano
  (mantener USER/BOOT, pulsar RST, soltar BOOT), flashear, y después **RST solo**: el reset por RTS lo deja en modo
  descarga. (2026-10-19)

- **NUNCA `meshtastic --dest … --set <seccion2>` con más de una sección**: el CLI solo pide la primera sección y escribe
  las demás desde cero. 2026-10-19 dejó `admin_key` = [solo el techo] y `serial_enabled false` en 5 nodos (NAK
  `ADMIN_PUBLIC_KEY_UNAUTHORIZED` al Dnto_L1 después). Forma correcta: `mt.py aplicar <nodo> --dest` (API: lee todas
  las secciones, aborta si falta una). Recuperación: por el admin que quedó (el techo por TCP).
- Admin remoto (`addContactURL`, `setFavorite`, `writeConfig`) no espera confirmación: «ok» = enviado. Verificar
  leyendo de vuelta (`aplicar … --dest` sin `--apply`).

- CLI por USB colgado o «multiple access on port» → la app Meshtastic de macOS tiene tomado el puerto (`lsof /dev/cu.usbmodemXXX`): cerrarla o desconectarla del nodo. No matarla sin avisar. (2026-10-18)
- `aplicar --dest` contra un nodo apagado o fuera de alcance se queda esperando indefinidamente → confirmar antes con `estado` que se oye (hace < 15 min).

- esptool corta a mitad del borrado ("No more data to read") → el ESP32 queda sin firmware: pantalla apagada y solo el LED de carga. No está roto: `esptool --port <p> chip-id` lo confirma y se vuelve a flashear. (2026-10-18)

- Dos Heltec V3 (CP2102) a la vez: tras flashear uno, el otro perdió su `/dev/cu.usbserial-*` aunque el CP2102 seguía enumerado (mismo número de serie) → conectar uno por vez o reconectar el que falta. (2026-10-18)

- T1000-E tras el erase v3 queda como `T1000_E_BOOT` sin disco; a veces un toque a 1200 bps lo pasa a UF2 y a veces no → botón apretado al conectar el cable (LED) y copiar el `.uf2` (mt.py flashear lo intenta solo). Al reconectar, los puertos pueden intercambiarse: identificar con `estado`. (2026-10-18)

- `cp firmware.uf2 /Volumes/<UF2>/` → «fcopyfile failed: Input/output error»: inofensivo, el nodo reinicia antes de
  que macOS cierre la copia. Verificar con `$T estado` que el fw cambió.
- `aplicar` en ESP32 recién cambiado de canales/lora → el paso siguiente falla porque el nodo reinicia → `aplicar`
  reintenta una vez a los 20 s.
- Un admin con su propia llave en `admin_key` no sirve y gasta un cupo → mt.py la excluye.
- `--dest` + `requestConfig` → el CLI imprime cada sección recibida (llaves incluidas) → mt.py silencia stdout.

- `timeout 40 meshtastic …` → no existe `timeout` en macOS: usar `meshtastic --timeout 40`.
- `pipx install …` → «pipx needs uv>=0.9.17» → `pipx install --backend pip …`.
- `pip install git+https://github.com/meshtastic/python@sha` → falla el submódulo `http://github.com/meshtastic/protobufs`
  (puerto 80 bloqueado) → clon local con `submodule.protobufs.url` en https (ver cli.md).
- `fd.label == fd.LABEL_REPEATED` → protobuf ≥5 no lo tiene: detectar repetido por el tipo del valor.
- PyPI por WebFetch devuelve un desafío anti-bot → usar `https://pypi.org/pypi/meshtastic/json`.
- `urllib` contra nightly.meshtastic.org / release.meshtastic.org → 403 (Cloudflare bloquea el User-Agent por
  defecto) → `User-Agent: curl/8 …` (función `pedir` de mt.py).
- `--seturl` escribe canales **y** la config lora de la URL, y no borra canales sobrantes → mt.py arma la URL con la
  lora deseada y borra sobrantes con `--ch-index N --ch-del` de mayor a menor.
- `meshtastic --info` / `--export-config` → imprimen `privateKey` y la URL con PSK: filtrar
  `grep -v -i -e private -e psk` antes de mostrar.
- `--set security.packet_signature_policy COMPATIBLE` → hay que dar el nombre completo
  `PACKET_SIGNATURE_POLICY_COMPATIBLE`.
