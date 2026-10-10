---
name: media-stack
description: Administrar la suite arr (Sonarr, Radarr, Prowlarr, Bazarr), qBittorrent, Plex, Seerr y FlareSolverr del cluster k3s - cola de qBittorrent, torrents atascados en metaDL/stalled, limpieza de importados, perfiles de calidad y tamaños, indexers, actualizaciones de imagen, logs, seeding y rendimiento. Usar SIEMPRE que la tarea toque cualquiera de esas apps, antes de explorar el repo o los pods.
---

# Suite arr + qBittorrent

Objetivo: resolver con pocas llamadas. **No explorar el repo ni los pods para "ubicarse"**: todo lo necesario está
aquí. Primera llamada casi siempre: `media status`.

```bash
M="python3 -I .claude/skills/media-stack/media.py"   # desde la raíz del repo o del worktree
$M status                         # pods, versión vs última, salud *arr, qBittorrent, discos, último filtro
$M torrents [--state RE] [--name s] [--min-age H] [--limit N]
$M queue [sonarr|radarr] [--all]  # solo ítems con problema salvo --all
$M stuck [--hours 2] [--states metaDL,stalledDL] [--apply [--orphans]]
$M imported [--apply]             # completos, fuera de cola e importados → borrar con archivos
$M prefs [regex]                  # preferencias de qBittorrent relevantes (o las que matcheen regex)
$M profiles radarr|sonarr [--sizes]   # perfiles, CF con puntaje, maximumSize del indexer, MB/min
$M logs <app> [--since 6h] [--grep RE]   # warn/error deduplicados
$M update <app…|all> [--apply]    # rollout restart (imágenes :latest, pullPolicy Always)
$M api <sonarr|radarr|prowlarr> <ruta> [-X M] [-d JSON|@archivo] | jq …   # crudo, ruta sin /api/vN
$M qb <ruta> [-d 'form=urlencoded']   # qBittorrent API v2 cruda; -d → POST
```

Todo lo que borra o reinicia es **dry-run sin `--apply`**. Cada comando es una sola llamada simple, así que pasa la
guarda del worktree (los compuestos con pipes/heredocs/`sops |` fueron rechazados en sesiones anteriores: si hace
falta lógica extra, escribirla en un script en `$CLAUDE_JOB_DIR/tmp` y correrlo con `python3 -I`).

## Mapa (no hace falta verificarlo)

| App | ns / deploy / contenedor | Puerto | Config | Notas |
|-----|--------------------------|--------|--------|-------|
| Sonarr | `sonarr` | 8989 v3 | PVC `sonarr-config-pvc` | API key en `/config/config.xml` |
| Radarr | `radarr` | 7878 v3 | PVC `radarr-config` | idem |
| Prowlarr | `prowlarr` | 9696 **v1** | `media-library/config/prowlarr` | idem; FlareSolverr en ns `flaresolverr` |
| Bazarr | `bazarr` | svc 80 | `media-library/config/bazarr/config/config.yaml` | |
| qBittorrent 5.x | `qbittorrent` | 8080 | `media-library/config/qbittorrent/qBittorrent/qBittorrent.conf` | Strategy Recreate; pod trae curl, jq, python3 |
| Plex | `plex` | 32400 | PVC `plex-config-pvc` | |
| Seerr | `overseerr` (`05-services/`) | svc 80 | | imagen `ghcr.io/seerr-team/seerr` |

- Manifiestos: `cluster/04-media-stack/<app>/` (Seerr en `cluster/05-services/overseerr/`). Todo en `k3s-node-1`
  (afinidad `media-worker`, toleración `p2p`), por eso un reinicio de node-1 baja toda la suite.
- Almacenamiento: NFS `192.168.1.100:/mnt/homelab-storage/k8s-media-library` montado en `/data` (HDD 12 TB + SLOG
  `sda4`); `/data/downloads` y biblioteca `/data/media/{movies,series}` en el mismo FS → hardlinks. Incompletos en
  `/incomplete` (pool `scratch` de pve, stripe sdc+sdd, `sync=disabled`, desechable, sin sanoid).
- Acceso API: `kubectl exec` al pod de cada app (key leída de `config.xml` adentro); qBittorrent sin login para
  `localhost` y `10.42.0.0/16` (Cloudflare Access protege el hostname público). **No usar sops, port-forward ni el
  Secret** para consultar; el Secret SOPS `qbittorrent/arr-api-keys` (SONARR/RADARR_API_KEY) es solo para el CronJob.
- NetworkPolicy real: `allow-arr-suite-communication` (ns con label `arr-suite=true` + kube-system).
  `qbittorrent/networkpolicy.yml` del repo **no está aplicado**. El ns `qbittorrent` no tiene egress restringido.
- Respaldo de config: CronJobs `config-backup-<app>` en cada ns (`cluster/00-infrastructure/backups/app-config-backup.yaml`).

## Configuración ya decidida (versionada en `qbittorrent/deployment.yml`, init container)

El init reescribe `qBittorrent.conf` en cada arranque: **un cambio hecho solo por API se pierde al reiniciar**.
Para persistir: `set_session <Clave> <valor>` (sección `[BitTorrent]`, prefijo `Session\`) o `set_webui`.
`ExcludedFileNamesEnabled` va **sin** prefijo `Session\`. Para probar en vivo antes:
`$M qb app/setPreferences -d 'json={"max_active_downloads":10}'`.

- Seeding: ratio 2 o 2880 min seedeando o 2880 min inactivo → **Stop** (no Remove); Radarr/Sonarr con
  `removeCompletedDownloads` borran el torrent detenido y su hardlink en `downloads/`.
- Cola: `MaxActiveTorrents 50`, `MaxActiveDownloads 10`, `MaxActiveUploads 5`, `dont_count_slow_torrents`.
  `max_active_torrents` es tope duro de libtorrent que cuenta los stalled.
- Puerto BT fijo 6881 (hostPort, reenviado en el router). `TempPath /incomplete/` solo afecta torrents nuevos.
- `ExcludedFileNames` bloquea `.exe .scr .lnk .bat…`; el CronJob `qbittorrent/arr-filtro-archivos` (cada 10 min,
  `cronjob-arr-filtro-archivos.yml`) saca de la cola *arr con blocklist los torrents con ejecutables o sin video.
  Logs: `kubectl logs -n qbittorrent job/<último>`; prueba manual con `DRY_RUN=1`.
- Radarr: perfiles `HD-1080p +` (id 4, 1080p+2160p+Remux) y `HD - 720p/1080p` (id 6); tope absoluto por release en
  **Settings → Indexers → Maximum Size = 8192 MB** (`config/indexer.maximumSize`), no en los MB/min de
  `qualitydefinition`. Para cambiar un perfil: GET `qualityprofile/<id>` → modificar → PUT el objeto completo.

## Recetas

**Torrents colgados en metaDL / stalledDL**: `$M stuck --hours 2` → revisar resumen por indexer →
`$M stuck --hours 2 --apply`. Los quita vía el *arr (`queue/bulk` DELETE con `removeFromClient&blocklist`), así el
*arr busca otro release. Huérfanos (sin *arr) solo con `--orphans`. Historial: casi todos los metaDL muertos venían
del indexer **TorrentDownload**; si se repite, proponer deshabilitarlo en Prowlarr. Torrents recién agregados en
metaDL (<1 h) suelen ser los reemplazos: no tocarlos.

**Limpiar la cola de lo ya importado**: `$M imported` → **mostrar conteo y GB y pedir confirmación** (borrado masivo
con archivos; el clasificador del modo auto lo bloqueó la primera vez, y la regla global es detenerse y preguntar) →
`--apply`. Normalmente no hace falta: el límite de 2 días ya los detiene y los *arr los borran.

**"Caution: Found executable file" / importPending**: lo resuelve el CronJob; verificar su último log. Si un release
legítimo trae basura publicitaria (`.url`, `.txt`) no se blocklistea: el filtro solo mira ejecutables y ausencia de
video.

**Calidad / tamaño en Radarr o Sonarr**: `$M profiles radarr [--sizes]` y luego `$M api radarr … -X PUT -d @f.json`.
Releer después de escribir y comparar con lo pedido.

**Actualizar**: `$M status` dice si hay versión nueva de los *arr → `$M update <apps> --apply` (espera el rollout y
muestra versión antes → después). qBittorrent y Plex cortan descargas/streams: avisar. No hay versión fija que
editar en el repo (`:latest`), salvo que se decida fijar tags.

**Rendimiento lento / NFS**: primero `$M status` (velocidad, estados) y `$M prefs`; históricamente la causa fue la
cola de qBittorrent, no el NFS. NFS/ZFS del host: `proxmox/README.md` (no repetir el diagnóstico desde cero).

**qBittorrent no arranca / pod pegado**: es `Recreate` con `hostPort 6881`; un segundo pod no puede convivir. Revisar
`kubectl describe pod -n qbittorrent` y el init (`kubectl logs … -c setup-qbittorrent-unified`); el init no debe
hacer `chown -R` sobre `downloads/` (NFS, no termina).

## Cambios al repo

Solo si cambia un manifiesto: rama `feat|fix/…` desde `main`, editar `cluster/04-media-stack/<app>/…`,
`kubectl apply -k cluster/04-media-stack/<app>` (o `kubectl apply -f` del archivo), verificar con `$M`, PR y merge
(`AGENTS.md`). Ajustes que viven en la BD de los *arr (perfiles, indexers, tamaños) no se versionan: dejarlos
anotados en la respuesta. Si se aprende un hecho nuevo y estable, agregarlo a esta skill en el mismo PR.
