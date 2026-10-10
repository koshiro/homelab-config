# Bitácora de uso (una línea por tarea; sirve para ver qué falta promover)

| Fecha | Tarea | Llamadas | Qué faltó | Qué se agregó |
|-------|-------|----------|-----------|---------------|
| 2026-10-10 | (antes de la skill) metaDL colgados en Radarr | 18 | ubicarse, API key, jq | — |
| 2026-10-10 | (antes de la skill) limpiar importados | 18 | cruce cola/historial a mano | — |
| 2026-10-10 | Sacar atascados, eliminar TorrentDownload, re-buscar | 12 | filtro por indexer, esperar búsquedas, grabs por indexer | `requeue`, `wait-search`, `grabs`, `torrents --max-age`, nombres con `html.unescape` |
| 2026-10-10 | Descargas al 100 % sin importar | ~30 | cruce qBittorrent/cola/historial; logs rotados; causa raíz NFS (mountstats, prueba con cp) | `unimported` detecta cola trabada y scratch en NFS 4.2; fix PV scratch a 4.1; hechos y receta |
