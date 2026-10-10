# Bitácora de uso (una línea por tarea; sirve para ver qué falta promover)

| Fecha | Tarea | Llamadas | Qué faltó | Qué se agregó |
|-------|-------|----------|-----------|---------------|
| 2026-10-10 | (antes de la skill) metaDL colgados en Radarr | 18 | ubicarse, API key, jq | — |
| 2026-10-10 | (antes de la skill) limpiar importados | 18 | cruce cola/historial a mano | — |
| 2026-10-10 | Sacar atascados, eliminar TorrentDownload, re-buscar | 12 | filtro por indexer, esperar búsquedas, grabs por indexer | `requeue`, `wait-search`, `grabs`, `torrents --max-age`, nombres con `html.unescape` |
| 2026-10-10 | Descargas al 100 % sin importar | ~14 | cruce qBittorrent/cola/historial; leer logs rotados de qBittorrent | `unimported` con diagnóstico de cola de movimientos trabada; hechos de logs y cola FIFO |
