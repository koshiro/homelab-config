# Pendientes del homelab

Última revisión: 2026-10-14. Orden sugerido: **1 → 2 → 3**; el resto cuando el cluster esté estable.

Arquitectura objetivo y plan por fases: [ARQUITECTURA.md](ARQUITECTURA.md). Este archivo detalla las tareas.

## 1. Pool `homelab-storage` (TrueNAS)

**Estado (2026-09-30):** VM 101 (`truenas-core`) **detenida y con `onboot: 0`**. El pool está importado **en solo lectura en el host Proxmox** (`/mnt/rescue/homelab-storage`). No arrancar la VM 101 mientras el pool esté importado en el host (doble import = corrupción): antes `zpool export homelab-storage`.

**Diagnóstico:**
- `homelab-storage` = **un solo disco** Seagate ST12000NT001 12 TB (`sdc`, serial ZRT0164N), log en WD 2 TB (`sdd`), cache en SSD WD 120 GB (`sdb`). Sin redundancia. 8.4 TB usados.
- SMART del 12 TB limpio. Los errores (`Unaligned write command` en lecturas, resets de `ata4`, enlace a 1.5 Gbps) vienen de **NCQ + cable/puerto**: con NCQ desactivado (`echo 1 > /sys/block/sdc/device/queue_depth`, no persiste tras reinicio) los errores bajan de ~120/minuto a esporádicos.
- Pool **DEGRADED** con errores permanentes desde el scrub de junio 2026: `media/Raws/2016/January/16/_KOR3587.NEF` y 3 objetos de `timemachine`. Durante el rescate fallaron además 2 previews de Immich (`thumbs/`, regenerables).
- Controladora Intel SATA en **modo RAID** (debería ser AHCI).
- WD 3 TB (`sde`) fuera de la VM; 1 sector reasignado, 6 errores CRC.
- ⚠️ El dataset `minecraft-server` estaba **vacío** y tapaba la carpeta homónima del dataset raíz donde vivían los datos reales: **los snapshots automáticos de Minecraft nunca respaldaron nada**. Lo mismo aplica a `immich-library` (carpeta en el dataset raíz, sin snapshots propios).

**Pasos:**
1. [x] Cambiar cable SATA + cable de poder del 12 TB (2026-10-01; ahora en SATA6G_3 = `ata3`).
2. [x] BIOS: controladora SATA en AHCI (2026-10-01). Revisado además: Restore AC Power Loss = Power On, ErP off, VT-x on, Aggressive LPM off. Microcode B4 de la BIOS → `intel-microcode` lo sube a 0xF8 al arrancar.
3. [x] Verificar enlace: `ata3` a 6.0 Gbps con NCQ y 0 errores tras el arranque (2026-10-01). Confirmar bajo carga con el scrub.
   - ⚠️ **2026-10-02 00:51 — import RW fallido.** VM 101 deshabilitada (discos del pool desasignados, `protection: 1`, config previa en `/root/vm101-config-antes-fase1.txt`). `zpool import -f -N homelab-storage` (lectura-escritura) provocó `VERIFY0(dmu_buf_hold_array(...)) failed (5) / PANIC at dmu.c:1342:dmu_write()` en `txg_sync` → `spa_flush_metaslabs` → `space_map_write`: EIO leyendo un *space map* (metadato de espacio libre dañado, probablemente por las escrituras con el enlace inestable). El primer txg no llegó a confirmarse, así que el estado en disco debería ser el previo. El import queda colgado con el lock global de ZFS: `zpool`/`zfs` (pvestatd, sanoid, syncoid, restic) se bloquean hasta reiniciar el host. `nvme` y los servicios siguen funcionando. **No reintentar import RW**; tras reiniciar solo `-o readonly=on`.
   - 2026-10-02 01:57: el reinicio se colgó esperando los procesos ZFS bloqueados; lo resolvió el watchdog de systemd. Import `-o readonly=on` OK: pool DEGRADED, errores permanentes solo en 1 RAW (`_KOR3587.NEF`) y 3 objetos de `timemachine`; cache (SSD retirado) UNAVAIL. Copia en curso de `homelab-storage/media` (1,72 TB: `Raws` 1,6 TB + `mami` 126 GB) → `respaldo/rescate/media` (unidad `rescate-media`, log `/root/rescate-media.log`, ~100 MB/s). **No hay otra copia de los RAW a mano**: no tocar el pool en RW hasta verificarla.
   - Diagnóstico `zdb -e -mm` (solo lectura, `/root/zdb-mm.txt`): los 816 metaslabs y sus space maps se leen sin errores (rc=0) → el EIO del import RW pudo ser transitorio; candidato a un reintento RW controlado tras verificar la copia.
   - El pool importado tiene `cachefile=default` (no se puede cambiar en solo lectura) y `/etc/zfs/zpool.cache` se vacía al arrancar; aun así, **exportar `homelab-storage` antes de reiniciar** para que nunca se importe RW en el arranque.
   - 2026-10-02 08:05: copia de `media` verificada (100 074/100 075 archivos; muestra de 300 sha256 idénticos; `_KOR3587.NEF` ilegible por completo, perdido). Congelada: `respaldo/rescate/media@verificado-20261002`, `readonly=on`.
   - 2026-10-02 08:10: **segundo intento RW (con `zfs_recover=1`) → mismo PANIC en `space_map_write`**. Falla determinista: el pool no admite escrituras. Solo usable en solo lectura. Queda colgado otra vez hasta reiniciar.
   - 2026-10-02 08:29: reinicio con drenado + apagado de invitados + SysRq `s`/`b` (evita esperar al watchdog con el import colgado; <1 min). `homelab-storage` no se importa al arrancar. Disco 12 TB: SMART PASSED, 0 reasignados/pendientes/irrecuperables, log de errores vacío → daño **lógico** (escrituras corruptas por el cable/puerto). **Autotest SMART largo en curso** (`smartctl -t long`, termina ~2026-10-03 04:08; ver con `smartctl -l selftest /dev/disk/by-id/ata-ST12000NT001-3LX101_ZRT0164N`). Decisión pendiente tras el test: (A) segundo disco 12 TB → copiar el pool en solo lectura a un pool nuevo y luego espejo; (B) recrear el pool en el mismo disco y que *arr vuelva a descargar; (C) mantener solo lectura. Además: copia externa de los RAW (hoy solo en `respaldo`, WD 3 TB con 1 sector reasignado).
   - Incidente menor: un `zfs unmount -a` desmontó por unos minutos `nvme/k8s/{immich,backups}`, la raíz del LXC `nas` y `respaldo/*`; remontados + `exportfs -ra`, sin archivos escritos debajo de los puntos de montaje. Nunca usar `-a` con varios pools.
   - Configuración persistente respaldada en `nvme/k8s/backups/arr-config/20261002/` (entra en sanoid/syncoid/restic): `sonarr`, `radarr`, `prowlarr`, `bazarr`, `overseerr`, `plex` (5,5 GB) desde los PVC `local-path` de k3s-node-1; `k8s-media-library/config` (qBittorrent y configs antiguas); `backups/` del pool; e `inventario-k8s-media-library.tsv` (8 219 archivos de `media/` y `downloads/` con tamaño y fecha). Si la media de *arr se pierde: restaurar configs, escalar las apps y lanzar «Search All Missing» en Sonarr/Radarr.
4. [x] ~~NCQ off persistente~~: no hace falta. Tras el cambio de cable el disco trabaja con NCQ (`queue_depth` 32) y el pool recreado está ONLINE sin errores (2026-10-10).
   - **2026-10-03 — opción B ejecutada.** SMART largo sin errores (disco sano, daño solo lógico). Antes de destruir: copiados y verificados por checksum a `respaldo/rescate/{comfyui,webodm-db}` la config y las 2 164 imágenes de ComfyUI (sin modelos: lista en `MODELOS-NO-COPIADOS.txt`) y la BD vieja de WebODM; RAW verificados en `respaldo/rescate/media` (100 074/100 075: **`Raws/2016/January/16/_KOR3587.NEF` ilegible en el pool, recuperarlo de la copia externa**). Descartados a pedido: Time Machine, biblioteca vieja de Plex, PhotoPrism, `backup_cleanup`, `cluster-config`, OpenClaw, proyectos de WebODM y la media de *arr (6,2 TB, se vuelve a descargar). Lista de lo descargado: `nvme/k8s/backups/arr-config/20261002/arr-descargado-20261003.json` y `series-descargadas-20261003.md` (77 series; se agregan a mano en Sonarr; las 316 películas siguen monitoreadas en Radarr).
   - Pool nuevo: `zpool create` sobre el disco entero (ashift 12, lz4, recordsize 1M, xattr sa, posixacl), sin cache (el WD 2 TB `sdd` perdió su etiqueta vieja de log con `zpool labelclear`). **Actualizado 2026-10-10:** SLOG en `sda4` (32 GB del SSD de arranque GIGABYTE) y `sdc`+`sdd` forman el pool desechable `scratch` (stripe, incompletos de qBittorrent). Los nombres `sdX` cambian entre arranques: hoy el 12 TB es `sdb`; usar `/dev/disk/by-id/`. Datasets `media` (RAW, restaurado con `zfs send` desde `@verificado-20261002`), `k8s-media-library` (config de qBittorrent, Prowlarr y Bazarr desde el tar + carpetas vacías) y `comfyui`. `zfs-import@homelab\x2dstorage.service` habilitado (corregido 2026-10-15: sin escapar el `-` no importaba). Exportado por NFS desde Proxmox (`proxmox/etc/k8s.exports`).
   - [x] PV/PVC de `media-library-pvc` (6 namespaces) y `comfyui-workspace-pvc` recreados contra 192.168.1.100; borrados los huérfanos `plex-media`, `bazarr-media`, `prowlarr-media` (2026-10-03). Suite *arr y Plex con `replicas: 1`. Marcador `.pool-recreado-20261003` en `media/{peliculas,series}`: con la raíz vacía Radarr/Sonarr no actualizan nada (failsafe «root folder is empty»). Radarr: 346 películas monitoreadas faltantes, «Search All Missing» lanzado. Sonarr: sin búsqueda (las series se agregan a mano desde la lista).
   - [x] ComfyUI de vuelta con sus modelos (`replicas: 1`, más SwarmUI y smartgallery; dataset `homelab-storage/comfyui` 86 GB).
   - 2026-10-03: **Overseerr → Seerr 3.5.0** (Overseerr archivado en 2026-02). Misma URL, namespace y PVC; migración automática de la BD (1 usuario, 472 solicitudes); Radarr, Sonarr y Plex probados OK. Respaldo previo: `nvme/k8s/backups/overseerr/overseerr-config-pre-seerr-20261003.tar.gz`. Suite *arr y Plex verificadas en su última versión.
   - qBittorrent nunca persistió su cola (`BT_backup` iba al contenedor: `XDG_CONFIG_HOME` sin `XDG_DATA_HOME`). Corregido en el repo (`XDG_DATA_HOME=/data/config/qbittorrent/data`); se aplica al levantar la suite.
5. [x] Scrub completo del pool recreado (2026-10-11): 8 h 30 min, 0 B reparados, 0 errores, pool ONLINE. Los 4 pools sanos (`zpool status -x`). Decidido: ZFS directo en Proxmox (hecho). Sigue abierto: segundo disco de 12 TB para espejo.
6. [x] ~~Rescatar el resto~~: resuelto con la opción B (2026-10-03): lo valioso se copió y restauró, el resto se descartó o se vuelve a descargar.
7. [x] ~~`qemu-guest-agent` en la VM 101~~: obsoleto; la VM 101 se destruyó el 2026-10-10 (ver § 4).

## 2. Rescate de minecraft, immich y pingvin ✅ (2026-09-30)

- Copiados con `rsync -aHAX` a datasets ZFS en Proxmox: `nvme/k8s/{minecraft,immich,pingvin}` (868 MB, 6.1 GB, 19.9 GB). Log: `/root/rescue-rsync.log` en Proxmox.
- Servidos por NFS desde Proxmox (`/etc/exports.d/k8s.exports`, solo `192.168.1.0/24`).
- Manifiestos apuntando a `192.168.1.100:/nvme/k8s/<app>`: `apps/minecraft/deployment.yml` (volumen inline), `apps/immich/01-storage.yaml`, `05-services/pingvin/pvc.yml` (StorageClass `nfs-proxmox`, PV estáticos `Retain`).
- Los manifiestos de pingvin estaban **vacíos** en el repo; reconstruidos desde el estado vivo del cluster.
- [x] Snapshots locales con **sanoid** en Proxmox (`/etc/sanoid/sanoid.conf`): horarios 24, diarios 14, semanales 4, mensuales 6 para `nvme/k8s/*` (2026-10-01).
- [x] Copia fuera del mirror NVMe: resuelto de otra forma. `syncoid-respaldo` replica `nvme/k8s` a `respaldo/k8s` cada noche y `restic-offsite` lo sube a R2.
- [x] Minecraft actualizado a 26.2 + plugins y datapacks al día + terreno sin cambios regenerado (detalle en `cluster/apps/minecraft/DATA-SAFETY.md`).
- [ ] **Minecraft → 26.3: esperar a que Geyser soporte Java 26.3.** Estado 2026-10-02: Paper 26.3 solo BETA (build 143; 26.2 STABLE build 129); Geyser 2.11.3-b1247 usa `mcprotocollib = 26.2` (ver `gradle/libs.versions.toml` en GeyserMC/Geyser); Revisado 2026-10-10: Geyser `master` sigue en `mcprotocollib = 26.2`. Floodgate b141, ViaVersion/ViaBackwards 5.12.0, Simple Voice Chat bukkit-2.6.24 y SkinsRestorer 15.12.6 ya soportan 26.3. Al subir: snapshot `zfs snapshot nvme/k8s/minecraft@pre-26.3` → `VERSION: "26.3"` en `deployment.yml` → aplicar → probar cliente Java y Bedrock → datapacks Vanilla Tweaks 26.3 → anotar en `DATA-SAFETY.md`.
- [x] Base de datos de Immich en CloudNative-PG (`local-path`). `homelab-postgres-2` (k3s-node-3) divergió tras el apagado del 2026-10-01 (`pg_rewind` fallaba); recreada el 2026-10-02 borrando PVC + pod → `homelab-postgres-5`. Cluster 3/3 (primario `-4`, réplicas `-1` y `-5` en streaming).

## 3. Limpieza del cluster ✅ (2026-10-01)

- [x] PVs huérfanos eliminados (12).
- [x] Recursos huérfanos eliminados (2026-10-01): Ingress `immich-manual-ingress` (el `immich-ingress` del repo pasó a entrypoint `web` sin TLS, igual que el resto), Service `immich-postgresql` (ExternalName), secret `immich-secrets`, `truenas-node-exporter` y servicios `truenas-exporter`/`truenas-node-exporter`, ns `traefik` vacío.
- [x] Montajes NFS a TrueNAS (`/mnt/homelab-storage`, `/mnt/pool_medios`, `/mnt/pool_downloads`) comentados en `/etc/fstab` de los 3 workers (respaldo `/etc/fstab.bak-truenas-20261001`).
- [x] Repo: manifiestos vacíos de Overseerr y namespaces/services/Ingress de la suite *arr y Plex reconstruidos desde el cluster (sin diff contra lo vivo).
- [x] Dataset `openclaw` en TrueNAS: desapareció al recrear el pool (2026-10-03).

## 4. Seguridad

- [x] Immich: credenciales de DB desde el secret `homelab-postgres-app` (`DB_USERNAME`/`DB_PASSWORD`), sin contraseña en el manifiesto (2026-10-01).
- [x] Secret `homelab-postgres-app` regenerado sin salto de línea (2026-10-01).
- [x] `/root/truenas-rescate/` (con `freenas-v1.db`, configuración y secretos cifrados de TrueNAS) borrado de Proxmox (2026-10-10). Los scripts que contenía están en el historial de git.
- [x] `qm destroy 101` (con sus zvols `nvme/vm-101-disk-*` ~57 GB, el `boot-pool` y el kubeconfig de admin que tenía en `/root/.kube`) y `qm destroy 9001` (`truenas-template`) el 2026-10-10. `zpool import` ya no muestra pools huérfanos.

- [x] Contraseña del vault rotada (2026-10-01): `ansible-vault rekey`, nueva contraseña fuera del repo en `~/.config/homelab/ansible-vault-pass` (guardarla también en el gestor de contraseñas), `.vault_password.txt` eliminado de git e ignorado. El historial solo contiene una versión antigua del vault con `vault_truenas_password` (TrueNAS se retira).
- [x] `.truenas-api-key` fuera del índice de git (2026-10-01); sigue en el historial. La VM 101 ya no existe, así que la key quedó inválida.
- [x] Contraseña del rol `immich` rotada (2026-10-01); `homelab-postgres-superuser` (secret de bootstrap de CNPG) alineado con la misma.
- [x] `WO_SECRET_KEY` de WebODM rotada (2026-10-01); `secret.sops.yml` ahora incluye `namespace: webodm`.
- [ ] Cookies movidas a `~/git/security-assessment/evidence/from-homelab-config/` — **no están ignoradas allí** (siguen sin trackear al 2026-10-10); decidir si se cifran o borran antes de commitear en ese repo.
- [x] ~~TrueNAS por tailnet~~: obsoleto, TrueNAS retirado (el pool vive en Proxmox).
- [x] **qBittorrent:** WebUI de vuelta en `qbittorrent.danielriquelme.cl` tras Cloudflare Access (2026-10-10, PR #31); NodePort 30808 queda para LAN/tailnet. `networkpolicy.yml` no está aplicado (solo `allow-arr-suite-communication`). Sin login desde la red de pods (`WebUI\AuthSubnetWhitelist=10.42.0.0/16`, lo fija el init container del Deployment; 2026-10-10, PR #40): Access es la única barrera pública. La contraseña sigue para clientes fuera de esa red.
- [x] Cloudflare Access para apps de administración: la app «Homelab admin» cubre grafana, comfyui, swarmui, galeria, chat, sonarr, radarr, prowlarr, bazarr y qbittorrent (verificado por API 2026-10-10). Recordatorio: el comodín `*.danielriquelme.cl → traefik` hace público todo Ingress; agregar a Access cada app de administración nueva.

## 4b. Postgres — respaldo PITR ✅ (2026-10-15)

- **Garage v2.4.1** (S3 local; MinIO Community está archivado desde 2026) en pve: `proxmox/etc/garage.toml`,
  `proxmox/systemd/garage.service`, datos en `nvme/k8s/garage` (quota 50G; entra en sanoid, syncoid a `respaldo` y
  restic a R2). API S3 en `192.168.1.100:3900`, bucket `cnpg-backups`, llave `cnpg` (secretos en `/etc/garage/`).
- **cert-manager v1.21.2** y **plugin Barman Cloud v0.15.1** (`cluster/00-infrastructure/`).
- `cluster/apps/postgresql/`: ObjectStore `garage` (retención 30 días, gzip), `plugins:` en el Cluster (WAL continuo;
  aplicarlo reinicia las 3 instancias por turno) y ScheduledBackup diario 06:20 UTC (03:20 Chile). Secreto
  `02-garage-secret.sops.yaml`. El manifiesto del Cluster se limpió del `status` volcado bajo `spec`.
- Verificado: WAL archivado en ~0,5 s; respaldo base de 76 MiB en 23 s; **restauración de prueba** (cluster
  `pitr-prueba` desde Garage) idéntica a producción (170 MB, 3 290 assets). `check-backups.sh` vigila el WAL (≤ 6 h) y
  los snapshots/réplica de `garage`.
- Se mantiene el `pg_dump` diario de immich como segunda vía (formato lógico, restaurable en otra versión).
- [ ] CNPG 1.27.0 está atrasado (1.29.3/1.30.1 al 2026-10-14): actualizar el operador, idealmente vía Renovate.

## 4b2. Mantención urgente de Proxmox (bug de ZFS)

2026-10-01 09:07: el primer respaldo restic disparó `VERIFY(avl_find(...) == NULL) failed / PANIC at avl.c:625:avl_add()` en `zfsctl_snapshot_mount` (automount de `.zfs/snapshot`, bug de OpenZFS 2.3.3). Los datos están intactos (pools sanos), pero quedan hilos del kernel colgados en estado D y el montaje/desmontaje de snapshots bloqueado hasta reiniciar.
- [x] `restic-offsite.sh` ya no usa `.zfs/snapshot`: monta el snapshot explícitamente en solo lectura.
- [x] Mantención 2026-10-01: Proxmox 9.0.3 → **9.2.21**, ZFS **2.4.4**, kernel **7.0.14** (6.14.11 queda como respaldo en el menú de arranque). El apagado ordenado funcionó; el reinicio se colgó desmontando los snapshots bloqueados y requirió reset por KVM. Tras arrancar, `respaldo` no se importó (`zpool.cache` vacío): se registraron `nvme` y `respaldo` en el cache. No se ejecutó `zpool upgrade`.
- [x] Snapshots colgados borrados y primer respaldo restic lanzado con el script nuevo (sin PANIC).

## 4b3. Swap del host con RAM libre (bug ZFS 2.4 + kernel 7.0)

Desde el kernel 7.0, `vmalloc` intenta primero un bloque de orden alto y, si falla, despierta a `kswapd`. ZFS 2.4 lo
hace al crecer sus caches de bloques de 1M (`recordsize=1M` en todo `homelab-storage`): kswapd recupera memoria con
15–20 GB libres, encoge el ARC (baja a ~2,4 GB) y manda a swap RAM fría de las VMs. Confirmado 2026-10-10 con un
histograma sobre `vmscan:mm_vmscan_wakeup_kswapd`: 49/49 despertares en 4 min eran orden 10 desde
`spl_cache_grow_work → __vmalloc`. El swap del host crecía ~4–5 GB al día, en ráfagas (respaldos, reinicios de pods).
Mismo cuadro que [openzfs#18893](https://github.com/openzfs/zfs/issues/18893) (PVE 9.2, kernel 7.0.14, ZFS 2.4.4, 62 GB).

- [x] 2026-10-10: swap vaciado (`swapoff -a && swapon -a`) y `systemctl set-property qemu.slice MemorySwapMax=0`
  (versionado en `proxmox/systemd/drop-ins/qemu-slice-sin-swap.conf`). Mitiga el swap, no la causa: kswapd sigue
  despertando y el ARC sigue oscilando.
- [x] Comprobado 2026-10-14: `memory.swap.current` de 102/103/104 en 0. El swap del host (1,1 GB de 8 GB) es todo de
  `system.slice` (demonios Perl de PVE fríos: pveproxy, pvedaemon, pve-ha-*), sin swap-out activo. ARC en ~2,2 GB
  de 6 GB: sigue encogido, como se esperaba hasta el arreglo definitivo.
- [x] Alerta `SwapOutHostProxmox` (2026-10-14): swap-out del host > 256 MiB/h durante 15 min, además de
  `SwapHostProxmox` al 50 %. Con 100 MiB/h sonaría casi a diario: la línea base es 0–60 MiB/h con ráfagas de
  0,4–1,7 GB/h (13-10 08:00 y 14-10 desde las 19:00) que vuelven a entrar, por eso el uso total se queda en ~1 GB.
- Estado 2026-10-14: PR #19276 sigue en borrador; el host tiene `proxmox-kernel-7.0.14-20` y está disponible el
  7.0.14-23 (sin el fix).
- [ ] **Arreglo definitivo** (elegir uno y programarlo en una ventana de mantención):
  - ZFS con el fix: seguir [PR #19276](https://github.com/openzfs/zfs/pull/19276) (borrador al 2026-10-10; quita
    `__GFP_KSWAPD_RECLAIM` del intento de orden alto en `kv_alloc`). Cuando llegue a un `zfs` 2.4.x de Proxmox o a
    `proxmox-kernel-7.0`, actualizar, reiniciar el host y retirar el drop-in de `qemu.slice`. Revisar los changelogs
    con `apt-get changelog proxmox-kernel-7.0.<x>-pve-signed` (el 7.0.14-23 no lo trae).
  - Kernel donde `vmalloc` no despierte kswapd: los reportes dicen que empezó al pasar de 6.17 a 7.0. Un kernel
    6.17 de Proxmox con ZFS ≥ 2.4 serviría. **No sirve el 6.14.11 instalado**: trae ZFS 2.3.4 y `homelab-storage`
    tiene activa `block_cloning_endian` (feature de 2.4), así que importaría en solo lectura.
  - **Aplicado 2026-10-15 14:34 (reinicio de pve):** `spl_kmem_cache_obj_per_slab=1` en `proxmox/etc/zfs.conf`
    (copiado a `/etc/modprobe.d/`, dentro del initramfs) y kernel **7.0.14-24** (tampoco trae el fix). Tras arrancar
    `spl_kmem_cache_obj_per_slab` = 1.
    - [ ] Repetir el histograma de `mm_vmscan_wakeup_kswapd` y mirar `SwapOutHostProxmox` y el ARC unos días
      (~2026-10-18). Plan original: probar
    `spl_kmem_cache_obj_per_slab=1` en
    `proxmox/etc/zfs.conf` (baja esas peticiones de orden 10 a orden ≤8) y, si el ARC sigue desplomándose,
    `zfs_arc_shrinker_limit` (hoy 0; el issue sugiere ~1300 para 64 GB).
- No ejecutar `zpool upgrade` mientras tanto: cada feature nueva cierra la vuelta a versiones anteriores de ZFS.
- Descartado: el balloon con free-page-reporting y THP no son la causa (en el foro de Proxmox VMs con `balloon: 0`
  también caían a swap); `vm.swappiness` no influye; `vm.watermark_boost_factor=0` solo calla kswapd unos minutos.

## 4c. VMs k3s-node-2/3 con CPU kvm64

VM 103 y 104 no tenían `cpu:` en Proxmox → QEMU usa `kvm64` (sin x86-64-v2: NumPy reciente, Immich ML v3, PyTorch
fallan). Immich ML está fijado a k3s-node-1 (`cpu: host`) por eso.
- [x] 2026-10-08: `cpu: host` puesto en 103 y 104 **como cambio pendiente** (sin reiniciar; ver `proxmox/README.md` § VMs del cluster k3s).
- [x] 2026-10-10: stop/start de 103 y 104 hecho (drain + `qm shutdown`/`qm start`); `sse4_2` y `avx2` presentes, `qm pending` limpio.
- [x] 2026-10-10: Immich ML sin `nodeSelector`; server y ML prefieren k3s-node-3 (con Redis) y excluyen pibot. Tabla de nodos de `docs/DISENO-APPS.md` actualizada.

## 4d. Sitios estáticos independientes de Proxmox

- [x] josekast.cl y noledigasanadie corren en pibot con contenido en su disco (`/var/lib/homelab-<sitio>`), NodePort 30890/30891 y respaldo diario al NAS (2026-10-06).
- [x] **Túnel `pibot-webs`** (id `e09353d9-9758-46ad-9305-1b924e3e4a45`, creado por API 2026-10-06): conector `cloudflared-webs` en pibot, `josekast.cl`/`www` → `:30890`, `noledigasanadie.danielriquelme.cl` → `:30891` (CNAME propio, gana al comodín). Verificado: los 3 hostnames responden 200 y las peticiones pasan por los conectores de pibot. Las reglas `josekast.cl` del túnel `pve` y los Ingress quedan como vuelta atrás (devolver el CNAME al túnel `pve`).
- [ ] Simulacro de caída en una ventana de mantención: escalar a 0 `cloudflared` (túnel `pve`) y Traefik un minuto y confirmar que los sitios estáticos siguen respondiendo (corta Immich y el resto mientras dura).

## 4e. pibot: volver a 1800 MHz con un cable USB-C nuevo

1800 MHz con `over_voltage=2` rinde +15–22 % (detalle en `pibot/README.md`), pero con carga sostenida baja el voltaje
pasado el primer minuto con todos los cables probados (2026-10-06); el problema quedó aislado en los cables. El único
que funciona bien es el del laptop. Mientras tanto pibot va a 1500 MHz de serie (`arm_freq`/`over_voltage` comentados
en `config.txt`).
- [ ] Comprar un cable USB-C bueno (corto, 3–5 A) para la fuente de 50 W.
- [ ] Con el cable nuevo: descomentar `arm_freq=1800` y `over_voltage=2` en `/boot/firmware/config.txt` y en
  `pibot/boot/config.txt`, reiniciar y correr `pibot/vtest.sh` (~11 min). Aceptar solo con 0 muestras con bajo voltaje
  en la fase de carga; si no, volver a 1500.

## 5. Monitoreo — VictoriaMetrics + Grafana

Decisión 2026-10-08: **VictoriaMetrics single-node** en vez de kube-prometheus-stack. Usa PromQL y los mismos exporters y dashboards, pero ocupa ~5–10× menos RAM y disco (~0,5 GB en total contra 1,5–2,5 GB), no necesita operador, CRDs ni Helm. Desde 2026-10-16 lo aplica Flux (Kustomization `monitoring`, sin HelmRelease).

**Componentes** (`cluster/03-monitoring/monitoring/`, ns `monitoring`):
- `victoria-metrics`: base de métricas y scraper a la vez (`scrape.yml`), retención 90 días, datos en el dataset ZFS `nvme/k8s/victoria-metrics` (quota 30G, NFS; sin syncoid ni restic, 2 snapshots diarios). Prefiere node-2; nunca pibot.
- `node-exporter` (DaemonSet en los 4 nodos, cada 15 s), `kube-state-metrics`, cAdvisor y kubelet (volúmenes); `pve-exporter` (API de Proxmox) y `speedtest-exporter` (1 por hora).
- `grafana` 13 con base SQLite en `local-path` (respaldo `config-backup-grafana`), datasource y dashboards provisionados desde `dashboards/` (Node Exporter Full, Kubernetes Views, Proxmox, Speedtest, VictoriaMetrics). `grafana.danielriquelme.cl` tras Cloudflare Access.
- `vmalert` (reglas en `alert-rules.yml`, cada 30 s) → `alertmanager` → Telegram (mismo bot que `notify-telegram`). Críticas se repiten cada 2 h, el resto cada 12 h.
- Host Proxmox: `prometheus-node-exporter` (Debian, :9100, job `pve-host`) + `textfile-metrics.sh` cada 5 min (pools ZFS, datasets, SMART con `-n standby`).
- Login: JWT de Cloudflare Access (`Cf-Access-Jwt-Assertion`, app «Homelab admin»): entras con tu correo, sin contraseña. `admin` del secret queda de emergencia vía port-forward.
- Secretos: `secret-grafana.sops.yaml`, `secret-proxmox.sops.yaml`, `secret-alertmanager-telegram.sops.yaml` (entran por `solo-flux/`; los descifra Flux).

**Hecho (2026-10-08):**
- [x] Manifiestos y dashboards en el repo; capa `03-monitoring` activa en `cluster/kustomization.yml`. Eliminados HelmRelease/HelmRepository de kube-prometheus-stack y los `ServiceMonitor`.
- [x] `pve-exporter` arreglado: nunca autenticó (no expande `${PVE_*}` en `pve.yml`, y el token del secret vivo daba 401). Ahora usa `PVE_TOKEN_NAME`/`PVE_TOKEN_VALUE` y el token versionado (válido). Imagen fijada en 3.10.1.
- [x] Speedtest de cada 2 min a 1 por hora (cada prueba satura el enlace).
- [x] Host Proxmox: dataset `nvme/k8s/victoria-metrics` (quota 30G), `k8s.exports`, `sanoid.conf`, `syncoid-respaldo.service` y `check-backups.sh` copiados. ACL del token: `pveum acl modify / --tokens 'monitoring@pve!monitoring-token' --roles PVEAuditor` (tiene `privsep=1`; el rol solo estaba en el usuario → 403 `Sys.Audit`).
- [x] Borrado el Grafana manual (ns `grafana`) y el secret huérfano `monitoring/truenas-api-credentials`.
- [x] Verificado: todos los targets `up` (speedtest al primer scrape de la hora), ~17 k series, stack completo ~510 MiB de RAM (Grafana ~330, VictoriaMetrics ~60).

- [x] Exporters del host Proxmox (2026-10-08): `node_exporter` del paquete Debian y `proxmox/bin/textfile-metrics.sh` en vez de `zfs_exporter`/`smartctl_exporter` (no están en trixie; el script usa `smartctl -n standby` y no despierta discos).
- [x] Alertas (2026-10-08): 17 reglas en 3 grupos (disponibilidad, recursos, almacenamiento); circuito Alertmanager → Telegram probado con una alerta de prueba.
- [x] Dashboard propio «Homelab — resumen» (`dashboards/resumen.py` → `cluster/resumen.json`), home de Grafana.
- [x] Login de Grafana con el JWT de Cloudflare Access (todos los correos de la política entran como admin).

**Pendiente:**
- [x] Revisado 2026-10-14: 530 M filas, 196 MB de datos (215 MB con snapshots) en ~6 días ≈ 33 MB/día → ~3 GB a 90 días, 10 % de la quota. Sin cambios de retención ni drops.
- [x] Alertas de la primera semana revisadas (2026-10-14). Todas respondieron a hechos reales: `NodoCaido`/`TargetCaido` y
  `DeploymentIncompleto` (cloudflared, pingvin, node-odx-1) por el cambio planificado 104 → 105 del 2026-10-11 09:52–11:06;
  `SwapHostProxmox` antes del drop-in de `qemu.slice`; `DiscoSectoresNuevos` en `sdd` (WD 2 TB de ~89 500 h, pool
  `scratch`) por `Current_Pending_Sector` 0 → 1 el 2026-10-13. Único ajuste: `DiscoCaliente` en HDD/SSD de 50 a 55 °C
  (en el scrub llegaron a 51–53 °C, dentro de especificación).
- [ ] Vigilar `sdd`: si `Current_Pending_Sector` sigue subiendo o pasa a reasignados, sacarlo de `scratch` (recrear el pool
  solo con `sdc`; es desechable).
- [ ] Retomar `security-audit` (secret `midas-cookies`, ya eliminado del cluster) si hace falta; no es parte del monitoreo.

## 6. GitOps con Flux

Plan completo en fases: `docs/PLAN-FLUX.md` (2026-10-15).

- [x] Flux 2.9.6 instalado (2026-10-16, fase 3): instalación propia en `cluster/flux/flux-system` con deploy key de
  solo lectura, no `flux bootstrap`.
- [x] `sops-age` en `flux-system` y `decryption` en las 9 Kustomizations con secretos (Component `solo-flux/`).
- [x] Adopción (2026-10-16, fase 4): 28/28 Kustomizations activas, una por carpeta hoja de `cluster/`. Un merge a
  `main` es el despliegue; `kubectl apply -k` ya no se usa.
- [x] Fase 5 de `docs/PLAN-FLUX.md` (2026-10-16): errores de Flux a Telegram, estado en los commits de GitHub y
  `FluxSinReconciliar` en vmalert.
- [ ] Fases 6–8 de `docs/PLAN-FLUX.md`: prueba de fallas, prune y automerge, `hl.py inventario`.
- [ ] Decidir si se borran `cluster/kustomization.yml` y los `kustomization.yaml` de capa (`00-infrastructure/`…): son
  de la época de `kubectl apply -k`, Flux no los usa y la raíz no incluye immich, minecraft, claude-remote ni
  postgresql (el CI los valida igual).

## 6b. Actualizaciones con Renovate (2026-10-15)

`renovate.json` en la raíz: PR los sábados (06–12, hora de Chile), agrupados en `monitoreo`, `utilidades`,
`cloudflare`, `immich`, `media` y `cnpg-respaldos`; los saltos mayores llevan la etiqueta `mayor` y nunca se proponen
saltos mayores de Postgres. CUDA, el device plugin y WebODM (por digest) son mensuales. **Sin automerge** hasta la fase 7
de Flux; mergear un PR de Renovate ya es desplegarlo (Flux lo aplica).
Dry-run local (Node 24+ o `npm_config_engine_strict=false`):
`npx --package renovate@44 -- renovate --platform=local --dry-run=full` (solo lee archivos con commit).

- [x] Las 17 imágenes `latest`/sin tag fijadas a la versión que corría (resuelta por digest); WebODM por digest.
- [x] GitHub App de Renovate instalada en `koshiro/homelab-config` (2026-10-15).
- [x] Tags fijos aplicados (2026-10-15): 17 Deployments reiniciados con la misma versión; 0 pods con problema y sitios públicos en 200.
- [x] Primera tanda (2026-10-15, corrida manual): monitoreo (VictoriaMetrics/vmalert v1.154.0, Grafana 13.2.4) y
  cloudflared-webs 2026.10.1 mergeados y aplicados. Pendiente de revisar: #69 (digest nuevo de WebODM) y el resto
  del Dependency Dashboard (#72).
- [x] La app de Mend funciona (2026-10-15 19:34: PR #73–#84). Fuera del horario del sábado los PR se piden
  marcando su casilla en el Dependency Dashboard (#72); en horario los abre sola. El merge sigue siendo manual
  (automerge en la fase 7 de Flux); desde 2026-10-16 lo aplica Flux al mergear.
- [ ] Fase 7 de Flux: automerge de `monitoreo`, `utilidades` y `cloudflare` en parches y menores.
- [x] El operador CNPG está versionado como HelmRelease `cnpg` (chart 0.26.0 = CNPG 1.27.0, 2026-10-16).
- [ ] Renovate todavía no lo ve: el manager `flux` solo mira `gotk-components.yaml` por defecto. Sumar
  `cluster/00-infrastructure/cnpg/helmrelease.yaml` a su `managerFilePatterns` (y probar con el dry-run local).

## 7. IoT

- [ ] Mosquitto/Meshtastic: no hay manifiestos en el repo (la carpeta `cluster/07-iot/` ya no existe). Si se retoma, partir de cero.

## 8. Documentación

- [ ] Rehacer `docs/` cuando el cluster esté estable: `docs/guides` tiene numeración duplicada (09_, 10_), varias guías describen estado antiguo (ArgoCD, TrueNAS). Estructura propuesta: `docs/arquitectura.md`, `docs/operacion/` (apagado, respaldos, SOPS), `docs/apps/<app>.md`, `docs/runbooks/`.
- [ ] Revisar `docs/RESILIENCIA-POST-APAGON-ANALISIS.md`, `docs/RESUMEN-ACCIONES-RESILIENCIA.md`, `docs/OVERSEERR-INTERMITENCIA-SOLUCION.md`, `docs/storage_optimization_audit.md` → integrar o eliminar.
- [ ] Los docs de `docs/guides/` (salvo `08_plex_remote_access_setup.md`), `docs/runbooks/`, `docs/security/` y los análisis de resiliencia/Overseerr **no están versionados**: `~/.gitignore_global` ignora `docs`. Decidir qué se versiona (`git add -f`) y qué se archiva.
- [x] Limpieza 2026-10-01: eliminados playbooks de TrueNAS/one-off (`*truenas*`, `create_vms`, `mount_nfs`, `revert_nvidia_driver`, `shutdown_proxmox`, `resize_vm_disks`), 15 scripts obsoletos (TrueNAS, resiliencia, Plex one-off), manifiestos sin uso (`nfs-csi-driver`, HelmRelease de Traefik, dashboards/exporter/secret de TrueNAS, KSOPS) y restos Helm de Immich.

## 9. Otros

- [x] **webodm**: se mantiene con una sola instancia (webapp, worker, broker, db y un nodo de procesamiento `node-odx-1`, todos con 1 réplica). Los 3 PVC `local-path` (db, media, nodeodm) son necesarios; los 3 PV viejos de NFS se borran con el paso 3.
- [x] Plex y la suite *arr levantados sobre el pool nuevo (2026-10-03). ComfyUI de vuelta con modelos. (Ollama + Open WebUI reactivados 2026-09-30; usan local-path.)
