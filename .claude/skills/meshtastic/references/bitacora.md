# Bitácora

| Fecha | Tarea | Llamadas | Qué faltó | Qué se agregó |
|-------|-------|----------|-----------|---------------|
| 2026-10-18 | Crear la skill: investigar 2.8.1, inventario, CLI con protobufs 2.8.1, arquitectura | ~45 | CLI de PyPI sin campos 2.8; CarTracker con build de desarrollo; sin `esptool` | skill completa, `mt.py` (puertos, estado, respaldo, diff, aplicar, fw, upstream), `flota.yaml`, respaldo de CarTracker |
| 2026-10-18 | Plan de reinstalación limpia: nightly fijado, frecuencia pública + privado AEAD, llaves en el nodo | ~40 | el nightly no tiene zips ni notas; urllib bloqueado por UA | `plan.md`, `provisionar`, `secretos`, `fw` con nightly, comparación de canales, vigilancia planificada |
| 2026-10-19 | GPS lento en T1000-E: leer GPS.cpp/GPSUpdateScheduling de develop | ~15 | — | 900 s aplicado y verificado en AkiraGPS y CatTracker (este tenía el GPS DISABLED); dato en `hechos.md` |
