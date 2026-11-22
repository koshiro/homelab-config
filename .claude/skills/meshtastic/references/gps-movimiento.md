# GPS según movimiento (parche propio, candidato a upstream)

Estado (2026-11-22): rama local `feat/gps-motion-aware-scheduling` en `~/git/meshtastic-firmware` (clon de
`meshtastic/firmware`, sobre `develop`). Sin fork en GitHub ni PR todavía. Los trackers siguen en firmware oficial.

## Problema

- `gps_update_interval` es fijo: con 60 s, en movimiento la posición sale ~1/min aunque `broadcast_smart_minimum_interval_secs`
  sea 15 s (el smart broadcast solo actúa con un fix nuevo).
- Quieto, el GPS sigue despertando cada 60 s sin necesidad.
- El acelerómetro del T1000-E (QMA6100P, INT en P1.02) solo llamaba `wakeScreen()`, y el T1000-E no tiene pantalla.

## Upstream

- Issue abierto **meshtastic/firmware#8383** (2025-10, `help wanted`): "Dynamic GPS activation based on accelerometer".
  Idea en los comentarios: el acelerómetro despierta el GPS; la velocidad/posición del GPS decide cuándo bajarlo.
- PR **#8515** (borrador, fifieldt) + protobufs **#749**: *GPS Profile* (peatón, vehículo, fijo). fifieldt dijo que el
  acelerómetro podría integrarse con los perfiles. El parche no toca protobufs para no chocar con eso.
- Reglas: firmar el CLA (cla-assistant.io/meshtastic/firmware), PR contra `develop`, `trunk fmt`, plantilla con
  pruebas en hardware (T1000-E está en la lista), "Allow edits by maintainers". Recomiendan avisar en el issue antes.

## Diseño

- `src/motion/MotionActivity.{h,cpp}`: guarda la última vez que un sensor reportó movimiento. Cada sondeo del hilo
  del acelerómetro es un *heartbeat*; si pasan 10 s sin heartbeat (hilo apagado en caliente) se considera que no hay
  sensor. El primer heartbeat cuenta como movimiento (al encender, se asume en movimiento).
- `MotionSensor::wakeScreen()` (lo llaman todos los drivers al detectar movimiento) llama `MotionActivity::noteMotion()`.
  BMX160 y BMM150 (solo brújula) declaran `reportsMotion() = false`.
- `GPSUpdateScheduling::updateIntervalMs()` reemplaza a `gps_update_interval` en `msUntilNextSearch()` y en `GPS::down()`/fix hold:
  - Se activa solo con sensor reportando + `display.wake_on_tap_or_motion` + `position_broadcast_smart_enabled`.
    Sin eso, igual que hoy (opt-in con un campo existente; en T1000-E viene apagado).
  - **En movimiento** (movimiento en los últimos 5 min): `min(gps_update_interval, max(smart_minimum_interval, 15 s))`.
    Con los valores por defecto (120 s / 300 s) no cambia nada.
  - **Quieto**: `max(gps_update_interval, min(position_broadcast_secs, 1 h))`.
  - Un movimiento adelanta la próxima búsqueda: el hilo del GPS revisa cada 5 s cuando está apagado.
- **Bug del driver QMA6100P** (T1000-E): la interrupción queda enganchada (INT_CFG con latch) y en la ruta por
  interrupción nunca se leía `INT_ST0`, así que probablemente solo llegaba el primer movimiento tras encender. El parche
  lee el estado tras cada interrupción y cada 1 s (como BMA423 desde #11758). **Sin verificar en hardware.**

## Para los trackers de la flota (cuando se pruebe)

- `display.wake_on_tap_or_motion: true`, `gps_update_interval: 60`, `broadcast_smart_minimum_interval_secs: 15`,
  `position_broadcast_secs: 900` → en movimiento GPS cada 15 s, quieto cada 15 min.
- Airtime: en movimiento hasta ~4 posiciones/min por el canal privado; vigilar `channel_utilization`.

## Prueba en AkiraGPS (2026-11-22)

- Build `2.8.3.f584291` + parche (`.pio/build/tracker-t1000-e/firmware-tracker-t1000-e-2.8.3.f584291.uf2`) copiado sin borrar.
  Arranca bien: ID, llaves y config intactos, responde admin remoto por el techo.
- **Con este build el USB no enumera** (ni serie ni disco DFU, tampoco con botón al conectar; "reiniciar en DFU" desde la
  app vuelve a la 2.8.3 sin montar disco). Volver atrás: OTA por BLE desde la app.
  Análisis: el **bootloader** (que el UF2 no toca) tampoco aparece, y entre d5f1619 y develop solo cambió el drenado
  de la consola USB antes de un reset por assert (#12294, #12376), nada del arranque del USB. Apunta a la conexión
  física (cable magnético o el hub USB-C donde estaba, `usbmodem11201`), no al firmware. Sin confirmar.
- `display.wake_on_tap_or_motion: true` activado desde la app (en flota.yaml). Verificación pendiente: frecuencia de
  posiciones en MeshMonitor paseando (~15–30 s) vs quieto (~15 min).
- Bluetooth desde la Mac imposible: macOS mata al Python de Homebrew (TCC, falta `NSBluetoothAlwaysUsageDescription`).

## Pendiente

1. Probar en un T1000-E (UF2 sin borrar): log por USB de `GPS: moving/stationary` y conteo de movimientos.
2. Medir batería con y sin parche (días quieto en casa y un paseo).
3. Comentar el diseño en #8383, firmar el CLA, fork + PR contra `develop` (lo publica Daniel o con su OK).
