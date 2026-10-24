# Hechos de la suite (verificados; fecha = cuándo se confirmó)

## Infraestructura
- Todo en `k3s-node-1` (afinidad `node-role.kubernetes.io/media-worker`, toleración `p2p`): reiniciar node-1 baja la suite.
- `/data` = NFS `192.168.1.100:/mnt/homelab-storage/k8s-media-library` (HDD 12 TB + SLOG `sda4`). `/data/downloads` y
  la biblioteca `/data/media/{peliculas,series,anime,anime-peliculas}` están en el mismo FS → los *arr importan con hardlink.
- `/incomplete` = pool `scratch` de pve (stripe sdc+sdd, `sync=disabled`, desechable, sin sanoid). Al completar,
  qBittorrent **copia** (otro FS) a `/data/downloads`; mientras tanto el torrent está en `moving` y el *arr no importa.
- NetworkPolicy de qbittorrent: solo `allow-arr-suite-communication` (`networkpolicy-arr-suite.yml`: ns con label
  `arr-suite=true` + kube-system), que limita el ingress de todos los pods a esos orígenes; el egress queda libre. El viejo
  `networkpolicy.yml`, que nunca se aplicó, se borró del repo en la fase 1 de Flux. (2026-10-16)
- Acceso a APIs: `kubectl exec` al pod (ApiKey de `config.xml`; qBittorrent sin login en localhost). El Secret SOPS
  `qbittorrent/arr-api-keys` (SONARR/RADARR_API_KEY) es solo para el CronJob. No hace falta sops ni port-forward.
- Pod de qBittorrent trae curl, jq, python3. Los de Sonarr/Radarr traen curl (sin jq).
- Respaldo de config: CronJobs `config-backup-<app>` (`cluster/00-infrastructure/backups/app-config-backup.yaml`).
- Imágenes con tag fijo en git (Renovate abre los PR) y `imagePullPolicy: IfNotPresent` desde la adopción de Flux
  (2026-10-16): actualizar = PR que sube el tag; al mergear, Flux lo aplica. `rollout restart` solo reinicia, y sin
  `--field-manager` propio reinicia dos veces (Flux borra el `restartedAt`). (2026-10-16)

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
  reencola todos los `moving` al arrancar. `$M unimported` lo detecta. (2026-10-10)
- **Causa raíz de esos atascos (2026-10-10)**: con `/incomplete` y `/data` ambos en NFS 4.2 del mismo servidor,
  `copy_file_range` se vuelve un `COPY` asíncrono del lado del servidor; los datos se copian, pero el cliente nunca
  recibe el `CB_OFFLOAD` y la llamada queda colgada (hilo en S, no D). Se ve en `/proc/self/mountstats` del pod
  (`COPY` y `OFFLOAD_CANCEL` con errores en `/data`). Se reproduce con `timeout 120 cp <archivo>100M+> /data/…`.
  Arreglo: PV `qbittorrent-scratch-pv` con `nfsvers=4.1` (sin COPY). **No volver a 4.2 en scratch**, y ojo con
  cualquier otro par de montajes 4.2 entre los que se copien archivos grandes.

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
- 2026-10-11: Erai-raws nombra las segundas partes "San no Shou Part 2 - NN" y Sonarr las deja en "Unknown Series";
  en TVDB Fire Force S3 son 25 episodios continuos (Part 2 - NN = S3E(12+NN)). `manual --offset 12` lo resuelve.
- 2026-10-11: `manualimport?downloadId=…` sin serie conocida devuelve rechazo permanente "Unknown Series" y sin
  episodios; el POST `command` ManualImport acepta `seriesId`/`episodeIds` explícitos igual. Los CRC `[35D8E195]`
  parecen "E195": el número de episodio se toma solo de `SxxEyy` o ` - NN`.
- Prowlarr devuelve `magnetUrl`/`downloadUrl` como `http://localhost:9696/<indexer>/download?…`: desde qBittorrent
  hay que pedirlo a `prowlarr.prowlarr.svc.cluster.local:9696` (lo hace `agregar_torrent`). Con localhost,
  qBittorrent 5 responde `pending_count: 1` y lo descarta en silencio (2026-10-12, release de Knaben).

## Anime (decidido 2026-10-11)
- Preferir siempre **[Erai-raws]** y **[ToonsHub]** (traen subs en español latino). Custom formats de Sonarr
  `Anime: Erai-raws` (`^\[Erai-raws\]`, 100), `Anime: ToonsHub` (`^\[ToonsHub\]`, 100) y `Subs latino`
  (`SPA-LA|ES-LA|Latino|LatAm|Multi-Subs`, 10) en el perfil **`Anime` (id 7)**: grupos `Anime 1080p` (BD+WEB+HDTV) y
  `Anime 720p`, cutoff 1080p con `cutoffFormatScore 100`. Agrupar es lo que hace ganar al grupo: en Sonarr la calidad
  pesa antes que el puntaje CF, y un BD-1080p suelto le ganaría a un WEB de Erai. Toda serie tipo `anime` o con tag
  `erai` va con este perfil. Se borró el release profile "required Erai-raws en Nyaa" porque dejaba fuera a ToonsHub.
- Nyaa.si (Prowlarr id 4): `sonarr_compatibility` y `strip_s01` **apagados a propósito**. El modo compatibilidad
  agrega "S01" a títulos sin temporada y rompe la numeración absoluta (" - NN") de las series tipo anime.
- Sonarr busca anime con la numeración de escena (TheXEM) y los títulos alternativos de sus servicios; no admite
  títulos ni mapeos propios. Si el grupo usa otro título u otra división de temporadas, la búsqueda vuelve vacía:
  `grab` + `manual`. Caso **GitS SAC (tvdb 73749)**: S3/S4 de TVDB = SAC_2045 T1/T2; XEM los junta como escena
  S3x1-24 y busca "Ghost in the Shell SAC_2045 18". Erai publica "Koukaku Kidoutai - SAC_2045 Season 2 - NN" (Sonarr
  no lo asocia a la serie) y "SAC_2045 S02E03" lo mapea a 2x3 (2nd GIG). Las búsquedas por temporada de esta serie
  tardan >5 min (episodio × título alternativo × indexer).
- **Link Click S1 (2026-10-13)**: TVDB mete el especial "Marrying by Contesting" como S0E1 (absoluto 6), y Sonarr
  (XEM) parsea `S01E06` de packs BD (Mehul) como S0E1; S1E6 queda vacío. El archivo es S1E6 (subs: "Search of the
  Child"): `DELETE episodefile` + `ManualImport` con `episodeIds` fijos. Ojo: el BD trae solo los 11 normales.
- **Link Click (tvdb 402033, 2026-10-12)**: TVDB S3 = Bridon Arc (precuela, 6 ep.) y S4 = la "Season 3" real.
  VARYG/CR nombran la S3 real "S03Exx" (el S4E1 entró como S3E1), Bridon sale como "Bridon Arc S01Exx" (Sonarr lo
  toma como 3x0N pero el import falla con "not found in the grabbed release") y Yameii/ToonsHub usan la numeración de
  TVDB. Tsundere-Raws (VOSTFR) mete todos los alias entre paréntesis: el alias que cuenta es el que va antes del
  número. Sonarr no permite cambiar la fuente de metadatos (solo TVDB vía Skyhook) ni mapeos propios: por eso
  existe `buscar`.
- GitS: revisado el 2026-10-11, ningún SAC_2045 pisó S1/S2 (títulos de TVDB = archivos). Pero con el perfil `Anime`
  un "[ToonsHub] … SAC_2045 S02E03" sumaría 110 y **reemplazaría 2x3 de 2nd GIG**; por eso S1-S3 (completas) quedaron
  **sin monitorear**. No volver a monitorearlas. Mismo riesgo en cualquier anime cuyas temporadas de TVDB no
  coincidan con las del grupo: dejar sin monitorear lo completo.
- Packs multi-temporada con subcarpetas "<Serie> S2/": Sonarr importa solo el primer archivo de cada carpeta y
  rechaza el resto con "Episode 2x06 was unexpected considering the … S2 folder name" (2026-10-11, Mushi-Shi Judas).
  El archivo importado queda con el nombre de la carpeta raíz y puede caer en un especial equivocado. Arreglo: receta
  § Importaciones manuales, paso 4b.
- Mushi-Shi (id 160): el pack Judas numera S1 26, S2 11, S3 10; TVDB S1 26, S2 20. Judas S2E11 ("Path of
  Overgrowth") = S00E02 "Path of Thorns"; Judas S03E01-10 = S02E11-20. Reimportado y renombrado el 2026-10-11.
- Renombrado global de Sonarr apagado (`renameEpisodes=false`): `rename?seriesId=` sale vacío. `$M rename` lo
  activa solo durante la operación.
- Initial D (Sonarr 159, TVDB 70900): pack Judas "Complete Series + Movies" repartido el 2026-10-11. Sonarr S01-S06 +
  S00E01/02 (Extra Stage partes 1-2); Radarr Third Stage (586), Battle Stage 1/2, Extra Stage 2, Legend 1-3.
  Desmonitoreados para no duplicar: Sonarr S03E01 (= Third Stage) y Radarr 592 (Extra Stage, son 2 archivos).
- Radarr `manualimport?downloadId=` sale vacío si el torrent está en categoría `tv-sonarr`: usar
  `manualimport?folder=<ruta urlencoded>` (devuelve `Unknown Movie`; se fija con `movieId`).
- Sin Tailscale (`/Applications/Tailscale.app/Contents/MacOS/Tailscale status` → stopped) `k3s-node-0` no resuelve:
  kubeconfig temporal con `server: https://192.168.1.15:6443` + `tls-server-name: k3s-node-0` y `KUBECONFIG=` (LAN).
- Las fechas de la API de los *arr y qBittorrent están en UTC; el usuario está en GMT-3 (Chile): reportar en hora
  local (2026-10-13).
- `manualimport?downloadId=` devuelve vacío si Sonarr ya no rastrea la descarga (fuera de cola): usar
  `folder=<content_path del torrent>` (2026-10-13).
- En zsh `$M …` no se separa en palabras: usar `alias M=…` o llamar `python3 -I …/media.py` directo.
- Plex (2026-10-12): monta la biblioteca como `/media/…` (no `/data/media`). Bibliotecas (2026-10-23): 1 Películas y
  2 Programas de TV (agentes nuevos de Plex), 3 Anime (`/media/anime`) y 4 Películas de anime
  (`/media/anime-peliculas`) con HAMA; `plex_seccion(ruta)` elige la que toca. Sonarr **no tiene conexión a Plex**: tras renombrar o importar a mano, Plex no se entera hasta su escaneo
  periódico; `rename --apply` y `plex --scan` lo piden. GitS SAC S4 (Erai) no salía en Plex por los nombres del grupo.
- Plex `TranscoderTempDirectory` (2026-10-18): debe quedar **vacío** (por defecto `/config/…/Cache/Transcode`, fuera del
  respaldo). Con una ruta relativa (`transcoding`) la reproducción cae a `TMPDIR=/run/plex-temp` y sigue andando, pero
  la detección de voz y las tareas de fondo fallan con `Error creating directory … Permission denied`: el cwd del
  proceso es la carpeta de s6, de root. Se cambia con `PUT /:/prefs?TranscoderTempDirectory=` (vive en el PVC, no en git).
- Transcoding de Plex por GPU (2026-10-18): `$M transcode` → nvdec + nvenc, pipeline completo, ~9× para HEVC 4K → 720p.
  `speed` de `/transcode/sessions` queda en 0 sin cliente; la velocidad real es `maxOffsetAvailable − minOffsetAvailable`
  sobre la espera. El transcoder no arranca con `start.m3u8`: hay que pedir el índice que esa lista enlaza.

## Plex: anime con HAMA (2026-10-23)
- El agente nuevo «Plex Series» no tiene muchas OVAs (Dream Hunter Rem, Gall Force, Megazone 23): «Match request …
  returned no metadata» y **ni crea la ficha** (`.plexmatch` con `tvdbid` no lo arregla). Las películas sí se crean
  como `local://` y se emparejan con `faltan --apply`. Que falle una película occidental conocida (Vesper) es un fallo
  puntual al agregarla, no de cobertura.
- Anime va a las bibliotecas HAMA: Sonarr raíz `/data/media/anime`, Radarr raíz `/data/media/anime-peliculas`; Seerr
  manda el anime nuevo de Sonarr a `/data/media/anime` (`activeAnimeDirectory`; Radarr en Seerr no separa anime).
  Criterio usado al trasladar: etiqueta Anime de TVDB o idioma japonés (series); japonés + Animation (películas);
  el live action japonés y la animación occidental se quedan donde estaban.
- Instalación: initContainer `install-hama` (`plex/deployment.yml`) con commits fijados. HAMA = PR #611 (fork bugale)
  porque `master` cfddf8f trae TVDB v4 con la clave `TODO` y no empareja nada (issue #610). Plex 1.43.4 aún carga
  agentes legacy, pero Plex anunció que los quita en 2026: **antes de subir Plex, revisar que siga existiendo
  `com.plexapp.agents.hama` en `system/agents`** y las notas de versión. Los reemplazos con el sistema nuevo
  (hama-modern, plex-anime-provider) estaban sin implementar en 2026-10.
- HAMA consulta `api.anidb.net:9001`: la NetworkPolicy de salida de Plex abre ese puerto (sin él, series sin metadatos).
- ID forzado: archivo `tvdb.id` en la carpeta de la serie (lo lee el Absolute Series Scanner al crear la ficha; si ya
  existe, emparejar con `library/metadata/<id>/match?guid=com.plexapp.agents.hama://tvdb-<id>?lang=en`). Películas:
  `…://tmdb-<id de Radarr>?lang=en`. Si no hay ID, ASS/HAMA buscan por título en AniDB (acierta casi siempre).
- Prefs de HAMA (en el PVC): `SerieLanguagePriority` y `EpisodeLanguagePriority` = `en, main, ja` (por defecto los
  títulos salen en romaji). Se cambian con `:/plugins/com.plexapp.agents.hama/prefs/set?<id>=<valor>`.
- Nombres del grupo («Part 2 - 01», «3rd Season - 02», «5.1», «#01» en la raíz) hacen que ASS apile archivos en un mismo
  episodio o los mande a la temporada 0: `rename "<serie>" --apply` (formato SxxEyy de Sonarr) lo arregla.
- Mover a otra biblioteca cambia el GUID: Plex pierde el visto. Guardar `viewCount` antes y repetir `:/scrobble` en
  la ficha nueva (solo la cuenta dueña del token; otros usuarios lo pierden).
- Sonarr `You're Under Arrest` (123) tiene la ruta dentro de la carpeta de `You're Under Arrest!` (124): moverla aparte
  rompe la otra; se mueve la 124 y a la 123 solo se le corrige la ruta sin `moveFiles`.
- Radarr: `renameMovies=false` (como Sonarr); para renombrar una película, activarlo solo durante el `RenameFiles`.
