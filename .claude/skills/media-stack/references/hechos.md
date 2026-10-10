# Hechos de la suite (verificados; fecha = cuándo se confirmó)

## Infraestructura
- Todo en `k3s-node-1` (afinidad `node-role.kubernetes.io/media-worker`, toleración `p2p`): reiniciar node-1 baja la suite.
- `/data` = NFS `192.168.1.100:/mnt/homelab-storage/k8s-media-library` (HDD 12 TB + SLOG `sda4`). `/data/downloads` y
  la biblioteca `/data/media/{movies,series}` están en el mismo FS → los *arr importan con hardlink.
- `/incomplete` = pool `scratch` de pve (stripe sdc+sdd, `sync=disabled`, desechable, sin sanoid). Al completar,
  qBittorrent **copia** (otro FS) a `/data/downloads`; mientras tanto el torrent está en `moving` y el *arr no importa.
- NetworkPolicy real: `allow-arr-suite-communication` (ns con label `arr-suite=true` + kube-system).
  `qbittorrent/networkpolicy.yml` del repo **no está aplicado**. El ns `qbittorrent` no restringe egress.
- Acceso a APIs: `kubectl exec` al pod (ApiKey de `config.xml`; qBittorrent sin login en localhost). El Secret SOPS
  `qbittorrent/arr-api-keys` (SONARR/RADARR_API_KEY) es solo para el CronJob. No hace falta sops ni port-forward.
- Pod de qBittorrent trae curl, jq, python3. Los de Sonarr/Radarr traen curl (sin jq).
- Respaldo de config: CronJobs `config-backup-<app>` (`cluster/00-infrastructure/backups/app-config-backup.yaml`).
- Imágenes `:latest` (o sin tag) con pullPolicy Always: `rollout restart` = actualizar. No hay versión fija en el repo.

## qBittorrent (`qbittorrent/deployment.yml`, init container)
- El init reescribe `qBittorrent.conf` en cada arranque: **un cambio solo por API se pierde al reiniciar**. Persistir
  con `set_session <Clave> <valor>` (`[BitTorrent]`, prefijo `Session\`) o `set_webui`. `ExcludedFileNamesEnabled`
  va **sin** prefijo. Probar en vivo antes: `$M qb app/setPreferences -d 'json={"clave":valor}'`.
- Seeding: ratio 2 o 2880 min seedeando o 2880 min inactivo → **Stop**; los *arr (`removeCompletedDownloads=true`,
  verificado 2026-10-10) borran el torrent detenido y su hardlink en `downloads/`.
- Cola: `MaxActiveTorrents 50` (tope duro de libtorrent, cuenta los stalled), `MaxActiveDownloads 10`,
  `MaxActiveUploads 5`, `dont_count_slow_torrents`. Puerto BT fijo 6881 (hostPort). `TempPath /incomplete/` solo
  para torrents nuevos.
- `ExcludedFileNames` bloquea `.exe .scr .lnk .bat…` + CronJob `qbittorrent/arr-filtro-archivos` (cada 10 min) que
  saca de la cola *arr con blocklist los torrents con ejecutables o sin video. `DRY_RUN=1` para probar.
- Strategy `Recreate` + hostPort: nunca puede haber dos pods. El init no debe hacer `chown -R` sobre `downloads/`.
- Logs vigentes: `/config/qBittorrent/logs/qbittorrent.log*` (no los de `/data/config/qbittorrent/logs`, de 2025).
  Rotan cada pocos minutos por miles de "Performance alert: max outstanding piece requests reached"; leerlos con
  `cat $(ls -tr)` en ese directorio. (2026-10-10)
- **Movimientos de almacenamiento son una cola FIFO de a uno.** Si el job de cabeza no termina, nada más se mueve y
  todo queda en `moving` sin importarse. `setLocation` falla con "torrent is currently moving". Reiniciar qBittorrent
  reencola todos los `moving` al arrancar y la cola vuelve a correr. Caso real: el job de cabeza era un torrent de
  EZTV que luego se borró desde Sonarr; la cola quedó trabada ~3 h. `$M unimported` lo detecta. (2026-10-10)

## Radarr / Sonarr / Prowlarr
- Radarr: perfiles `HD-1080p +` (id 4, 1080p+2160p+Remux, ~275 películas) y `HD - 720p/1080p` (id 6). Tope absoluto
  por release: **Settings → Indexers → Maximum Size = 8192 MB** (`config/indexer.maximumSize`), no los MB/min de
  `qualitydefinition`. Cambiar un perfil: GET `qualityprofile/<id>` → modificar → PUT el objeto completo. (2026-10-10)
- Indexer **TorrentDownload eliminado** de Prowlarr (id 22) el 2026-10-10: daba magnets muertos (metaDL/stalledDL
  eternos). Borrar en Prowlarr lo quita solo de Sonarr/Radarr (sync de aplicaciones). No volver a agregarlo.
- `queue/bulk` DELETE con `removeFromClient=true&blocklist=true&skipRedownload=false` = quitar + blocklist + nueva
  búsqueda automática. Las búsquedas de ~20 películas tardan ~3-4 min (`wait-search`).
- Historial: `eventType=1` grab, `eventType=3` downloadFolderImported. `data.indexer` trae el indexer del grab.
- Salud persistente conocida: Radarr avisa "The Shadow's Edge removed from TMDb"; Prowlarr con indexers caídos
  (Internet Archive, kickasstorrents.ws, Magnet Cat). No son urgentes.
