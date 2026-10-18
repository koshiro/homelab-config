# Recetas

`T=~/.claude/skills/meshtastic/mt.py`

## Reflasheo de un nodo (full erase, conservando identidad)

1. Conectar por USB → `$T puertos` → `$T estado --port <p>` (confirmar nodo y `pio`).
2. `$T respaldo --port <p>` (deja `.yaml` y `.cfg` con la llave privada).
3. `$T fw <nodo>` → descarga, verifica md5 e imprime los pasos de su MCU.
4. Flashear según lo impreso:
   - ESP32-S3: `./device-install.sh -p <p> -f firmware-<pio>-<ver>.factory.bin` (borra todo). Pedir confirmación.
   - nRF52: `--enter-dfu` → copiar el `factory_erase` de la SoftDevice de `INFO_UF2.TXT` → DFU otra vez → copiar `.uf2`.
5. Restaurar: `meshtastic --port <p> --configure <respaldo>.yaml` (trae `security.private_key`, región y canales).
6. `$T estado` → el id debe ser el mismo de antes (`crc32(pubkey)`). Si cambió, la llave no se restauró: repetir 5.
7. `$T diff <nodo>` → `$T aplicar <nodo> --apply` para quedar igual a `flota.yaml`.
8. Desde otro nodo: `$T estado` debe oírlo (puede tardar hasta un NodeInfo; forzar con `--sendtext` o reinicio).

Sin respaldo posible (nodo que no arranca): flashear, configurar desde `flota.yaml` con `aplicar`, y luego agregar
su llave nueva en `flota.yaml` (pubkey, id) y en `admin_key` de los demás si es admin.

Actualizar sin borrar (ESP32 por WiFi): `meshtastic --host <ip> --ota-update <firmware-<pio>-<ver>.bin>`.

## Reflashear toda la flota a una versión

1. `$T upstream` y leer las notas; actualizar `firmware:` en `flota.yaml`.
2. Orden: primero un nodo de prueba accesible por USB (CarTracker), verificar 24 h; luego trackers, Dnto_L1, laptop
   y al final AcevedoRoof (es la puerta de entrada del homelab).
3. Mientras convivan versiones: firma `COMPATIBLE`, sin `use_aead`.

## Cambio de radio en toda la flota (preset, región, slot, nombre del canal primario)

1. Editar `flota.yaml`.
2. Por remoto, **del nodo más lejano al más cercano**: `$T aplicar <nodo> --dest '!id' --apply`. Cada uno deja de
   oírse al aplicar: no esperar ACK de los siguientes pasos.
3. El nodo conectado al final. Los que no se alcanzaron: por USB.
4. Recordar: un preset que la región no permite se rechaza entero por admin remoto.

## Alta de nodo nuevo

1. Flashear `firmware` de `flota.yaml` (receta de arriba, paso 3–4).
2. Por USB: `meshtastic --set lora.region ANZ` (genera llaves) → `$T estado` → anotar `id`, `hw`, `pio`, `pubkey`
   en `flota.yaml` con su perfil.
3. `meshtastic --seturl "$(canal_url de secretos.yaml)"` y `$T aplicar <nodo> --apply`.
4. Si será admin: agregarlo a `admins` y `aplicar` en todos los demás. En AcevedoRoof: `--set-favorite-node '!id'`.
5. `$T respaldo`.

## Administrar un nodo remoto

1. Conectar a un nodo cuya llave esté en el `admin_key` del destino (Dnto_L1, AcevedoRoof o laptop).
2. `$T diff <nodo> --dest '!id'` (pide la config por radio: 10–60 s por sección).
3. `$T aplicar <nodo> --dest '!id' --apply`, o `meshtastic --dest '!id' --set …`.
4. Error de sesión/timeout: acercar o subir `--timeout`; el CLI renueva la passkey de sesión solo.

## Nodo del techo al WiFi (paso previo a MeshMonitor)

1. Reservar IP en el router para la MAC WiFi del XIAO S3 (`--info` → `macaddr`).
2. `secretos.yaml`: `wifi_ssid`, `wifi_psk` (≥8 caracteres).
3. `$T aplicar AcevedoRoof --apply` (perfil `base` activa WiFi; BLE se apaga).
4. `meshtastic --host <ip> --info` debe responder. Anotar la IP en `hechos.md`.

## Revisar novedades

1. `$T upstream` → para cada NUEVA: leer notas (GitHub release / blog).
2. Anotar en `firmware.md` lo que cambia **para esta flota**; si hay CLI nuevo con protobufs, reinstalar (cli.md).
3. `$T upstream --marcar`.
