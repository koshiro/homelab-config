# Bitácora

| Fecha | Tarea | Llamadas | Qué faltó | Qué se agregó |
|-------|-------|----------|-----------|---------------|
| 2026-10-18 | Crear la skill: investigar 2.8.1, inventario, CLI con protobufs 2.8.1, arquitectura | ~45 | CLI de PyPI sin campos 2.8; CarTracker con build de desarrollo; sin `esptool` | skill completa, `mt.py` (puertos, estado, respaldo, diff, aplicar, fw, upstream), `flota.yaml`, respaldo de CarTracker |
| 2026-10-18 | Plan de reinstalación limpia: nightly fijado, frecuencia pública + privado AEAD, llaves en el nodo | ~40 | el nightly no tiene zips ni notas; urllib bloqueado por UA | `plan.md`, `provisionar`, `secretos`, `fw` con nightly, comparación de canales, vigilancia planificada |
| 2026-10-19 | Bot de Telegram `/donde` y `/flota` (meshmonitor-bot) sobre la API REST de MeshMonitor | ~30 | token compartido Alertmanager/whitelist → bot nuevo; AkiraGPS y CatTracker sin posición en MeshMonitor (solo nodeinfo) | `cluster/apps/meshmonitor/bot` |
| 2026-10-20 | Agregar SolarT114 (T114 solar, sin MQTT) a la flota; responder cómo medir batería/panel | ~7 | el nodo es remoto (no USB); id/pubkey sacados del node DB del techo | entrada `SolarT114` en `flota.yaml`, hechos del nodo y del plan INA3221 (power metrics) |
| 2026-10-24 | Alta de XiaoNRF (XIAO nRF52840 kit): flasheo limpio, provisionar, favoritos en el techo | ~25 | parser de SoftDevice del XIAO; vnode 192.168.1.15 inalcanzable desde el Mac (port-forward) | fix en `flashear`, entrada `XiaoNRF` en `flota.yaml`, trampas en `hechos.md` |
| 2026-10-24 | MQTT Client Proxy en Laptop (USB) y Dnto_L1 (radio); usuarios del broker | ~20 | merge del broker bloqueado por el clasificador; diff remoto marcaba la clave (`sekrit`) | perfil `cliente_proxy`, usuarios `laptop`/`dnto`, `diff --dest` omite `sekrit` |
| 2026-10-26 | Alta de PapoRelay (XIAO S3, relay MQTT por WiFi en otra ciudad): usuario `papo` en el broker, flasheo, provisionar, favoritos | ~25 | el puerto USB cambia (`usbmodem8CBF…` → `usbmodem101`) al entrar en bootloader; `aplicar` con WiFi corta la transacción (reinicia) y hay que repetirlo | entrada `PapoRelay` en `flota.yaml` (WiFi propio vía `papo_wifi_*` en secretos) |
