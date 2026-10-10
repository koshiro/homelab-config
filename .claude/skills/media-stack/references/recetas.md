# Recetas (M = `python3 -I .claude/skills/media-stack/media.py`)

## Torrents colgados en metaDL / stalledDL
1. `$M stuck --hours 2` → mirar el resumen por indexer.
2. `$M stuck --hours 2 --apply` (los quita vía el *arr con blocklist y busca otro). Huérfanos solo con `--orphans`.
3. `$M wait-search` y `$M grabs --minutes 15` para confirmar reemplazos.
Los metaDL de menos de 1 h suelen ser los reemplazos recién tomados: no tocarlos. Si un indexer concentra los
atascos, proponer eliminarlo (receta siguiente).

## Eliminar un indexer y reemplazar lo que bajó
1. `$M api prowlarr indexer | jq -c '.[]|select(.name|test("X";"i"))|{id,name}'`
2. **Primero** `$M api prowlarr indexer/<id> -X DELETE` (si no, la nueva búsqueda puede volver a tomarlo); verificar
   que desapareció de `$M api radarr indexer` / `sonarr indexer`.
3. `$M requeue --indexer X` → `--apply` → `$M wait-search` → `$M grabs --minutes 15`.
Ojo: `requeue` también saca los que estaban bajando bien (se pierde el progreso); avisarlo.

## Descargas al 100 % que no se importan
1. `$M unimported --paths`. Grupos posibles:
   - **moving**: si dice "cola de movimientos trabada" → `$M update qbittorrent --apply` (corta descargas ~1 min) y
     verificar que los `moving` bajen (script en background con `$M torrents --state '^moving$' --limit 0`). Si la
     cola corre pero lento, es la copia /incomplete → /data: esperar.
   - **en cola con aviso** (`importPending`/`importBlocked`/`importFailed`): leer el mensaje; ejecutables o sin video
     → lo resuelve el CronJob del filtro; otros → `$M logs sonarr|radarr --grep 'Import'`.
   - **fuera de cola y sin import**: torrents agregados a mano o cuyo ítem se borró del *arr; preguntar antes de
     borrarlos o importarlos (Manual Import vía API `manualimport`).

## Limpiar la cola de lo ya importado
`$M imported` → mostrar conteo y GB → **pedir confirmación** → `--apply`. Normalmente innecesario: el límite de 2 días
ya los detiene y los *arr los borran.

## "Caution: Found executable file" / importPending con .exe
Lo resuelve el CronJob `arr-filtro-archivos`; revisar su último log (`$M status` muestra el último job). Releases
legítimos con basura publicitaria (`.url`, `.txt`) no se blocklistean.

## Calidad / tamaño
`$M profiles radarr [--sizes]` → editar el JSON del perfil → `$M api radarr qualityprofile/<id> -X PUT -d @f.json`
→ releer y comparar con lo pedido. Tope absoluto por release: `config/indexer.maximumSize`.

## Actualizar
`$M status` (muestra si hay versión nueva de los *arr) → `$M update <apps> --apply` (espera el rollout y muestra
versión antes → después). qBittorrent y Plex cortan descargas/streams: avisar antes.

## Rendimiento lento / NFS
`$M status` + `$M prefs` primero; históricamente la causa fue la cola de qBittorrent, no el NFS. NFS/ZFS del host:
`proxmox/README.md`.

## qBittorrent no arranca / pod pegado
`kubectl describe pod -n qbittorrent -l app=qbittorrent` y `kubectl logs -n qbittorrent deploy/qbittorrent -c
setup-qbittorrent-unified`. Recreate + hostPort 6881: nunca dos réplicas.

## Cambiar un manifiesto
Rama `feat|fix/…`, editar `cluster/04-media-stack/<app>/…`, `kubectl apply -k cluster/04-media-stack/<app>`,
verificar con `$M`, PR y merge (`AGENTS.md`). Ajustes que viven en la BD de los *arr (perfiles, indexers) no se
versionan: anotarlos en `hechos.md`.
