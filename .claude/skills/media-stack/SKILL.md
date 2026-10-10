---
name: media-stack
description: Administrar la suite arr (Sonarr, Radarr, Prowlarr, Bazarr), qBittorrent, Plex, Seerr y FlareSolverr del cluster k3s - cola de qBittorrent, torrents atascados (metaDL/stalled/moving), descargas sin importar, limpieza, indexers, perfiles de calidad y tamaños, actualizaciones, logs, seeding y rendimiento. Usar SIEMPRE que la tarea toque cualquiera de esas apps, antes de explorar el repo o los pods. La skill es progresiva - al cerrar cada tarea se amplía con lo aprendido.
---

# Suite arr + qBittorrent

Objetivo: resolver con pocas llamadas y sin explorar. **No leer manifiestos ni listar pods para "ubicarse"**: el mapa
está abajo y `references/` tiene el resto. Primera llamada casi siempre: `$M status` (o el subcomando de la receta).

```bash
M="python3 -I .claude/skills/media-stack/media.py"   # desde la raíz del repo o del worktree; `$M -h` lista todo
$M status                          # pods, versión vs última, salud *arr, qBittorrent, discos, último filtro
$M torrents [--state RE] [--name s] [--min-age H] [--max-age H] [--limit N]
$M queue [sonarr|radarr] [--all]   # cola *arr: solo ítems con problema salvo --all
$M unimported [--paths]            # al 100 % sin importar: moving (detecta cola de movimientos trabada), avisos, huérfanos
$M stuck [--hours 2] [--states metaDL,stalledDL] [--apply [--orphans]]
$M requeue --indexer RE|--title RE [--apply]   # quitar de cola con blocklist → el *arr busca otro release
$M wait-search                     # esperar a que terminen las búsquedas de los *arr
$M grabs [--minutes 60] [-v]       # releases tomados recientemente, por indexer
$M imported [--apply]              # completos, fuera de cola e importados → borrar con archivos
$M prefs [regex]   |   $M profiles radarr|sonarr [--sizes]   |   $M logs <app> [--since 6h] [--grep RE]
$M update <app…|all> [--apply]     # rollout restart (imágenes :latest, pullPolicy Always)
$M api <sonarr|radarr|prowlarr> <ruta> [-X M] [-d JSON|@archivo] | jq …   # crudo; ruta sin /api/vN
$M qb <ruta> [-d 'form=urlencoded']                                      # qBittorrent API v2 cruda
```

- Todo lo que borra o reinicia es **dry-run sin `--apply`**. Borrados masivos (`imported`, `--orphans`): mostrar
  conteo/GB y pedir confirmación antes (el clasificador del modo auto ya lo bloqueó una vez; la regla global es
  detenerse y preguntar).
- Cada comando es una llamada simple: pasa la guarda del worktree. Lógica extra → script en `$CLAUDE_JOB_DIR/tmp`
  que haga `sys.path.insert(0, ".claude/skills/media-stack"); import media` y reutilice `media.arr`, `media.qb`,
  `media.colas`, `media.importados`, `media.quitar_de_cola`. Nunca `sleep` encadenado: `wait-search` o un script en
  background.

## Mapa

| App | ns = deploy = contenedor | API | Config |
|-----|--------------------------|-----|--------|
| Sonarr | `sonarr` | 8989 v3 | PVC `sonarr-config-pvc` (`/config/config.xml` con ApiKey) |
| Radarr | `radarr` | 7878 v3 | PVC `radarr-config` |
| Prowlarr | `prowlarr` | 9696 **v1** | `media-library/config/prowlarr` |
| Bazarr | `bazarr` | svc 80 | `media-library/config/bazarr/config/config.yaml` |
| qBittorrent 5.x | `qbittorrent` | 8080, sin login (localhost y 10.42.0.0/16) | conf y logs en el pod: `/config/qBittorrent/` |
| Plex | `plex` | 32400 | PVC `plex-config-pvc` |
| Seerr | `overseerr` (`cluster/05-services/`) | svc 80 | |

Manifiestos en `cluster/04-media-stack/<app>/`. Todo corre en `k3s-node-1`. Biblioteca y descargas en NFS `/data`
(hardlinks); incompletos en `/incomplete` (pool `scratch`). Detalle, configuración decidida y trampas conocidas:
**`references/hechos.md`**. Procedimientos por tipo de tarea: **`references/recetas.md`** (leer la receta que
corresponda antes de actuar).

## Ciclo de aprendizaje (obligatorio al cerrar cada tarea)

La skill crece con el uso. Antes de dar la tarea por terminada, revisar qué hizo falta fuera de `media.py`:

1. **¿Usaste un script ad hoc, un `jq` sobre `api`/`qb`, o más de 2 llamadas crudas para un mismo objetivo?**
   Si es general (se repetiría con otros datos) → promoverlo a subcomando de `media.py` siguiendo sus convenciones:
   salida compacta (una línea por ítem, `nombre()`/`cut()`, conteos con `Counter`), dry-run salvo `--apply`, ayuda
   en el parser y una línea en el bloque de comandos de arriba. Si es específico pero reusable → `scripts/<nombre>.py`
   importando `media`. Si fue de una sola vez → no agregar nada.
2. **¿Descubriste un hecho no obvio** (ruta, clave de config, bug, causa raíz, decisión del usuario)? → una línea en
   `references/hechos.md`, con fecha. Corregir o borrar lo que resultó falso.
3. **¿Tipo de tarea nuevo o receta que falló?** → crear o ajustar la receta en `references/recetas.md`.
4. **Registrar** una línea en `references/bitacora.md`: fecha | tarea | llamadas | qué faltó | qué se agregó.
5. Probar lo nuevo contra el cluster (dry-run) y versionarlo: en el PR de la tarea, o en uno
   `chore(media-stack): …` si la tarea no tocó el repo. Mantener este archivo por debajo de ~100 líneas: el detalle
   va a `references/`.
