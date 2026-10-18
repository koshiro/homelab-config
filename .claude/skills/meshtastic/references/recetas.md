# Recetas

`T=~/.claude/skills/meshtastic/mt.py`

## Instalación limpia de un nodo (la receta base)

1. Conectar por USB → `$T puertos` → `$T estado --port <p>` (confirmar placa y `pio`).
2. `$T respaldo --port <p>` (red de seguridad; no se restaura).
3. `$T fw <nodo>` → archivo verificado + pasos de su MCU. Flashear (pedir confirmación: borra todo):
   - ESP32-S3: `cd <dir> && ./device-install.sh -p <p> -f firmware-<pio>-<ver>.factory.bin`.
   - nRF52: `--enter-dfu` → copiar el `factory_erase` de la SoftDevice de `INFO_UF2.TXT` → DFU otra vez → `.uf2`.
4. `$T provisionar <nodo> --port <p>` (dry-run) → `--apply`: región → llaves → id/pubkey a `flota.yaml` → canales
   (`--seturl` con lora deseada) → `--set` → dueño → respaldo.
5. `$T diff <nodo>` debe decir «coincide». Desde otro nodo, `$T estado` debe oírlo.
6. Commit del `flota.yaml` con el id/pubkey nuevos.

Orden en la flota: **admins primero** (Dnto_L1, Laptop, AcevedoRoof): el resto nace con sus llaves en `admin_key`.
Un nodo provisionado antes que los admins: `$T aplicar <nodo> --apply` cuando existan.

Actualizar sin borrar (ESP32 por WiFi): `meshtastic --host <ip> --ota-update <firmware-<pio>-<ver>.bin>`.

## Tras un reset o percance

- No admin: flashear si hace falta y `$T provisionar <nodo> --apply`. Nada más.
- Admin: igual, y después agregar su llave nueva a los demás desde otro admin:
  `$T aplicar <nodo> --dest '!id' --apply` por cada uno (la llave vieja queda; quitarla con
  `meshtastic --dest '!id' --set security.admin_key 0` + las válidas, **en un solo comando**).

## Cambiar de firmware fijado

1. Aviso de la vigilancia o `$T upstream` → estudiar commits/notas → anotar en `firmware.md`.
2. `firmware:` en `flota.yaml` → `$T fw <nodo> --solo-bajar` para todas las placas (el nightly desaparece al día
   siguiente: archivar ya).
3. Canario (CarTracker) 24–48 h → resto. ESP32 con WiFi: OTA sin borrar.

## Cambio de radio en toda la flota (preset, región, slot, nombre del canal primario)

1. Editar `flota.yaml`.
2. Por remoto, **del nodo más lejano al más cercano**: `$T aplicar <nodo> --dest '!id' --apply`. Cada uno deja de
   oírse al aplicar.
3. El nodo conectado al final. Los que no se alcanzaron: por USB.
4. Un preset que la región no permite se rechaza entero por admin remoto.

## Canal privado (rotar PSK)

1. `$T secretos --generar-canal --forzar` (nueva PSK de 32 B).
2. Cada nodo por USB/TCP directo: `$T aplicar <nodo> --apply` (los canales no se comparan en remoto). Mientras
   tanto, los nodos ya rotados no se entienden con los pendientes.

## Administrar un nodo remoto

1. Conectar a un admin (Dnto_L1, Laptop o AcevedoRoof por TCP).
2. `$T diff <nodo> --dest '!id'` (pide la config por radio: 10–60 s por sección).
3. `$T aplicar <nodo> --dest '!id' --apply`, o `meshtastic --dest '!id' --set …`.
4. Telemetría bajo demanda: `meshtastic --request-telemetry --dest '!id'`; posición: `--request-position`.

## Nodo del techo al WiFi

1. `secretos.yaml`: `wifi_ssid`, `wifi_psk` (≥8 caracteres). Reserva DHCP para la MAC WiFi del XIAO.
2. Va dentro de `provisionar AcevedoRoof` (perfil `base`). BLE se apaga.
3. `meshtastic --host <ip> --info` debe responder. Anotar la IP en `hechos.md`.

## Revisar novedades

1. `$T upstream` → para cada NUEVA: leer notas (GitHub release / blog) o commits (nightly).
2. Anotar en `firmware.md` lo que cambia **para esta flota**; CLI con protobufs nuevos → reinstalar (cli.md).
3. `$T upstream --marcar`.
