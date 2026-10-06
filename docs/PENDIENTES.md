# Pendientes del homelab

Última revisión: 2026-10-01. Orden sugerido: **1 → 2 → 3**; el resto cuando el cluster esté estable.

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
4. [ ] Si el enlace queda limpio y se sigue usando NCQ off: hacerlo persistente (regla udev o `libata.force=4.00:noncq`).
   - **2026-10-03 — opción B ejecutada.** SMART largo sin errores (disco sano, daño solo lógico). Antes de destruir: copiados y verificados por checksum a `respaldo/rescate/{comfyui,webodm-db}` la config y las 2 164 imágenes de ComfyUI (sin modelos: lista en `MODELOS-NO-COPIADOS.txt`) y la BD vieja de WebODM; RAW verificados en `respaldo/rescate/media` (100 074/100 075: **`Raws/2016/January/16/_KOR3587.NEF` ilegible en el pool, recuperarlo de la copia externa**). Descartados a pedido: Time Machine, biblioteca vieja de Plex, PhotoPrism, `backup_cleanup`, `cluster-config`, OpenClaw, proyectos de WebODM y la media de *arr (6,2 TB, se vuelve a descargar). Lista de lo descargado: `nvme/k8s/backups/arr-config/20261002/arr-descargado-20261003.json` y `series-descargadas-20261003.md` (77 series; se agregan a mano en Sonarr; las 316 películas siguen monitoreadas en Radarr).
   - Pool nuevo: `zpool create` sobre el disco entero (ashift 12, lz4, recordsize 1M, xattr sa, posixacl), **sin SLOG ni cache** (el WD 2 TB `sdd` queda libre con la etiqueta vieja de log). Datasets `media` (RAW, restaurado con `zfs send` desde `@verificado-20261002`), `k8s-media-library` (config de qBittorrent, Prowlarr y Bazarr desde el tar + carpetas vacías) y `comfyui`. `zfs-import@homelab-storage.service` habilitado. Exportado por NFS desde Proxmox (`proxmox/etc/k8s.exports`).
   - [x] PV/PVC de `media-library-pvc` (6 namespaces) y `comfyui-workspace-pvc` recreados contra 192.168.1.100; borrados los huérfanos `plex-media`, `bazarr-media`, `prowlarr-media` (2026-10-03). Suite *arr y Plex con `replicas: 1`. Marcador `.pool-recreado-20261003` en `media/{peliculas,series}`: con la raíz vacía Radarr/Sonarr no actualizan nada (failsafe «root folder is empty»). Radarr: 346 películas monitoreadas faltantes, «Search All Missing» lanzado. Sonarr: sin búsqueda (las series se agregan a mano desde la lista).
   - [ ] ComfyUI sigue en `replicas: 0`: falta volver a descargar los modelos (`MODELOS-NO-COPIADOS.txt`).
   - 2026-10-03: **Overseerr → Seerr 3.5.0** (Overseerr archivado en 2026-02). Misma URL, namespace y PVC; migración automática de la BD (1 usuario, 472 solicitudes); Radarr, Sonarr y Plex probados OK. Respaldo previo: `nvme/k8s/backups/overseerr/overseerr-config-pre-seerr-20261003.tar.gz`. Suite *arr y Plex verificadas en su última versión.
   - qBittorrent nunca persistió su cola (`BT_backup` iba al contenedor: `XDG_CONFIG_HOME` sin `XDG_DATA_HOME`). Corregido en el repo (`XDG_DATA_HOME=/data/config/qbittorrent/data`); se aplica al levantar la suite.
5. [ ] Scrub completo y decidir futuro del pool: segundo disco para mirror, o migrar TrueNAS → ZFS directo en Proxmox.
6. [ ] Rescatar el resto con espacio nuevo: `k8s-media-library` (6.2 TB), `media` (1.7 TB), `timemachine` (476 GB), `comfyui` (78 GB), `webodm` (8 GB), `backups`.
7. [ ] Habilitar `qemu-guest-agent` en la VM 101.

## 2. Rescate de minecraft, immich y pingvin ✅ (2026-09-30)

- Copiados con `rsync -aHAX` a datasets ZFS en Proxmox: `nvme/k8s/{minecraft,immich,pingvin}` (868 MB, 6.1 GB, 19.9 GB). Log: `/root/rescue-rsync.log` en Proxmox.
- Servidos por NFS desde Proxmox (`/etc/exports.d/k8s.exports`, solo `192.168.1.0/24`).
- Manifiestos apuntando a `192.168.1.100:/nvme/k8s/<app>`: `apps/minecraft/deployment.yml` (volumen inline), `apps/immich/01-storage.yaml`, `05-services/pingvin/pvc.yml` (StorageClass `nfs-proxmox`, PV estáticos `Retain`).
- Los manifiestos de pingvin estaban **vacíos** en el repo; reconstruidos desde el estado vivo del cluster.
- [x] Snapshots locales con **sanoid** en Proxmox (`/etc/sanoid/sanoid.conf`): horarios 24, diarios 14, semanales 4, mensuales 6 para `nvme/k8s/*` (2026-10-01).
- [ ] Copia fuera del mirror NVMe: `syncoid` de `nvme/k8s` hacia `homelab-storage` cuando el disco de 12 TB esté estable (ver sección 1).
- [x] Minecraft actualizado a 26.2 + plugins y datapacks al día + terreno sin cambios regenerado (detalle en `cluster/apps/minecraft/DATA-SAFETY.md`).
- [ ] **Minecraft → 26.3: esperar a que Geyser soporte Java 26.3.** Estado 2026-10-02: Paper 26.3 solo BETA (build 143; 26.2 STABLE build 129); Geyser 2.11.3-b1247 usa `mcprotocollib = 26.2` (ver `gradle/libs.versions.toml` en GeyserMC/Geyser); Floodgate b141, ViaVersion/ViaBackwards 5.12.0, Simple Voice Chat bukkit-2.6.24 y SkinsRestorer 15.12.6 ya soportan 26.3. Al subir: snapshot `zfs snapshot nvme/k8s/minecraft@pre-26.3` → `VERSION: "26.3"` en `deployment.yml` → aplicar → probar cliente Java y Bedrock → datapacks Vanilla Tweaks 26.3 → anotar en `DATA-SAFETY.md`.
- [x] Base de datos de Immich en CloudNative-PG (`local-path`). `homelab-postgres-2` (k3s-node-3) divergió tras el apagado del 2026-10-01 (`pg_rewind` fallaba); recreada el 2026-10-02 borrando PVC + pod → `homelab-postgres-5`. Cluster 3/3 (primario `-4`, réplicas `-1` y `-5` en streaming).

## 3. Limpieza del cluster ✅ (2026-10-01)

- [x] PVs huérfanos eliminados (12).
- [x] Recursos huérfanos eliminados (2026-10-01): Ingress `immich-manual-ingress` (el `immich-ingress` del repo pasó a entrypoint `web` sin TLS, igual que el resto), Service `immich-postgresql` (ExternalName), secret `immich-secrets`, `truenas-node-exporter` y servicios `truenas-exporter`/`truenas-node-exporter`, ns `traefik` vacío.
- [x] Montajes NFS a TrueNAS (`/mnt/homelab-storage`, `/mnt/pool_medios`, `/mnt/pool_downloads`) comentados en `/etc/fstab` de los 3 workers (respaldo `/etc/fstab.bak-truenas-20261001`).
- [x] Repo: manifiestos vacíos de Overseerr y namespaces/services/Ingress de la suite *arr y Plex reconstruidos desde el cluster (sin diff contra lo vivo).
- [ ] Dataset `openclaw` en TrueNAS: borrar cuando el pool vuelva (app eliminada).

## 4. Seguridad

- [x] Immich: credenciales de DB desde el secret `homelab-postgres-app` (`DB_USERNAME`/`DB_PASSWORD`), sin contraseña en el manifiesto (2026-10-01).
- [x] Secret `homelab-postgres-app` regenerado sin salto de línea (2026-10-01).
- [ ] `/root/truenas-rescate/freenas-v1.db` en Proxmox contiene configuración y secretos cifrados de TrueNAS: borrar tras retirar TrueNAS (fase 3).
- [ ] TrueNAS tenía un kubeconfig de admin en `/root/.kube` (zvol de la VM 101): se elimina con `qm destroy 101`.

- [x] Contraseña del vault rotada (2026-10-01): `ansible-vault rekey`, nueva contraseña fuera del repo en `~/.config/homelab/ansible-vault-pass` (guardarla también en el gestor de contraseñas), `.vault_password.txt` eliminado de git e ignorado. El historial solo contiene una versión antigua del vault con `vault_truenas_password` (TrueNAS se retira).
- [x] `.truenas-api-key` fuera del índice de git (2026-10-01); sigue en el historial. Revocar la key en TrueNAS si la VM 101 vuelve a arrancar antes de `qm destroy`.
- [x] Contraseña del rol `immich` rotada (2026-10-01); `homelab-postgres-superuser` (secret de bootstrap de CNPG) alineado con la misma.
- [x] `WO_SECRET_KEY` de WebODM rotada (2026-10-01); `secret.sops.yml` ahora incluye `namespace: webodm`.
- [ ] Cookies movidas a `~/git/security-assessment/evidence/from-homelab-config/` — **no están ignoradas allí**; decidir si se cifran o borran antes de commitear en ese repo.
- [ ] **TrueNAS por tailnet:** Ingress público `truenas.danielriquelme.cl` eliminado (vivía en ns `media-stack`). Al recuperar TrueNAS: instalar Tailscale en TrueNAS (app oficial) o publicar `192.168.1.0/24` con un subnet router en pibot (`tailscale up --advertise-routes=192.168.1.0/24`).
- [ ] **qBittorrent:** Ingress público eliminado; WebUI solo por LAN/tailnet en `http://k3s-node-0:30808`. Al reactivarlo: verificar login de la WebUI activo, y si se aplica `networkpolicy.yml`, permitir tráfico NodePort (hoy solo permite Traefik).
- [ ] Recordatorio: el túnel Cloudflare tiene comodín `*.danielriquelme.cl → traefik`; **todo Ingress es público**. Evaluar Cloudflare Access para apps de administración (sonarr, radarr, prowlarr, bazarr).

## 4b. Postgres — respaldo robusto (pendiente)

Hoy: `pg_dump` diario de `immich` (164 MB → dump 33 MB) a `nvme/k8s/backups/postgres`, con snapshots, réplica a `respaldo` y offsite R2 junto a Immich.
Objetivo: respaldo nativo de CloudNativePG (Barman Cloud plugin) a almacenamiento S3 (R2 o MinIO local) con WAL archiving → recuperación a un punto en el tiempo (PITR) y `ScheduledBackup`. La única base es `immich` (más la de sistema `postgres`).

## 4b2. Mantención urgente de Proxmox (bug de ZFS)

2026-10-01 09:07: el primer respaldo restic disparó `VERIFY(avl_find(...) == NULL) failed / PANIC at avl.c:625:avl_add()` en `zfsctl_snapshot_mount` (automount de `.zfs/snapshot`, bug de OpenZFS 2.3.3). Los datos están intactos (pools sanos), pero quedan hilos del kernel colgados en estado D y el montaje/desmontaje de snapshots bloqueado hasta reiniciar.
- [x] `restic-offsite.sh` ya no usa `.zfs/snapshot`: monta el snapshot explícitamente en solo lectura.
- [x] Mantención 2026-10-01: Proxmox 9.0.3 → **9.2.21**, ZFS **2.4.4**, kernel **7.0.14** (6.14.11 queda como respaldo en el menú de arranque). El apagado ordenado funcionó; el reinicio se colgó desmontando los snapshots bloqueados y requirió reset por KVM. Tras arrancar, `respaldo` no se importó (`zpool.cache` vacío): se registraron `nvme` y `respaldo` en el cache. No se ejecutó `zpool upgrade`.
- [x] Snapshots colgados borrados y primer respaldo restic lanzado con el script nuevo (sin PANIC).

## 4c. VMs k3s-node-2/3 con CPU kvm64

VM 103 y 104 no tienen `cpu:` en Proxmox → QEMU usa `kvm64` (sin x86-64-v2). Immich ML v3 lo exige, por eso está fijado a k3s-node-1 (`cpu: host`).
- [ ] En la próxima mantención: `qm set 103 --cpu x86-64-v2-AES` y `qm set 104 --cpu x86-64-v2-AES` (requiere reiniciar cada VM) y quitar el `nodeSelector` de Immich ML.

## 4d. Sitios estáticos independientes de Proxmox

- [x] josekast.cl y noledigasanadie corren en pibot con contenido en su disco (`/var/lib/homelab-<sitio>`), NodePort 30890/30891 y respaldo diario al NAS (2026-10-06).
- [ ] **Túnel `pibot-webs`:** hoy el tráfico público sigue entrando por el túnel `pve` → Traefik → CoreDNS, que corren en los workers; si cae Proxmox los sitios no son alcanzables aunque el pod viva. Falta:
  1. Zero Trust → Networks → Tunnels → *Create tunnel* `pibot-webs` (Cloudflared), copiar el token.
  2. Public hostnames de `pibot-webs`: `josekast.cl` y `www.josekast.cl` → `http://192.168.1.15:30890`; `noledigasanadie.danielriquelme.cl` → `http://192.168.1.15:30891`. Al guardarlos, Cloudflare reemplaza los CNAME de `josekast.cl`/`www` (hoy al túnel `pve`) y crea el de `noledigasanadie` (un registro específico gana al comodín).
  3. Conector en pibot: secret `cloudflared-webs-token` cifrado con SOPS + Deployment `cloudflared-webs` (`nodeName: pibot`, `dnsPolicy: Default` para resolver con el router y no con CoreDNS).
  4. Probar apagando lógicamente los workers (`kubectl cordon` + escalar Traefik/cloudflared del túnel `pve` a 0 un minuto) que ambos sitios siguen respondiendo.
  - Las reglas `josekast.cl` del túnel `pve` y los Ingress se dejan: volver atrás es devolver el CNAME al túnel `pve`.

## 5. Monitoreo — plan Grafana (después de estabilizar)

**Estado actual:**
- ns `grafana`: `grafana/grafana:latest` aplicado a mano, **sin volumen** (dashboards/usuarios se pierden al reiniciar), sin manifiestos en el repo.
- ns `monitoring`: `pve-exporter`, `speedtest-exporter`, `truenas-node-exporter` corriendo, pero **no hay Prometheus** que los scrapee.
- Repo `cluster/03-monitoring/monitoring/`: `HelmRelease` kube-prometheus-stack 61.1.0 (requiere Flux) + `secret-generator.yaml` (KSOPS, era ArgoCD). Capa comentada en `cluster/kustomization.yml`.

**Plan:**
1. Instalar Flux (sección 6) — el HelmRelease ya existe.
2. kube-prometheus-stack en ns `monitoring` con Grafana incluido; valores mínimos para Raspberry + 3 workers: retención 7d, PVC `local-path` 10 Gi para Prometheus (luego NFS de Proxmox), Alertmanager desactivado al inicio.
3. Actualizar chart a versión actual y fijar imagen de Grafana (no `latest`).
4. Scrape configs para los exporters existentes (`pve-exporter`, `speedtest-exporter`) vía `ServiceMonitor`; añadir `node_exporter`/`zfs_exporter`/`smartctl_exporter` en el host Proxmox.
5. Dashboards como ConfigMaps con label `grafana_dashboard: "1"`.
6. Secretos (`secret-grafana`, `secret-proxmox`) vía SOPS con Flux (`decryption.provider: sops`).
7. Migrar/eliminar el Grafana manual del ns `grafana` y su Ingress.
8. Retomar `security-audit` (secret `midas-cookies`, ya eliminado del cluster) junto al monitoreo si hace falta.

## 6. GitOps con Flux

- [ ] `flux bootstrap github --owner=koshiro --repository=homelab-config --path=cluster --private`.
- [ ] Clave age en el cluster (`sops-age` secret en `flux-system`) y `decryption` en las Kustomizations.
- [ ] Completar `cluster/kustomization.yml` para que refleje TODO lo desplegado. Hoy faltan: `04-media-stack/{plex,sonarr,radarr,prowlarr,bazarr,qbittorrent}`, `apps/{immich,minecraft,postgresql}`, `03-monitoring`.
- [ ] Hasta entonces el flujo real es `kubectl apply -k` / `kubectl apply -f`. `kubectl kustomize cluster` compila (verificado 2026-09-30).

## 7. IoT

- [ ] Mosquitto/Meshtastic: no hay manifiestos en el repo (la carpeta `cluster/07-iot/` ya no existe). Si se retoma, partir de cero.

## 8. Documentación

- [ ] Rehacer `docs/` cuando el cluster esté estable: `docs/guides` tiene numeración duplicada (09_, 10_), varias guías describen estado antiguo (ArgoCD, TrueNAS). Estructura propuesta: `docs/arquitectura.md`, `docs/operacion/` (apagado, respaldos, SOPS), `docs/apps/<app>.md`, `docs/runbooks/`.
- [ ] Revisar `docs/RESILIENCIA-POST-APAGON-ANALISIS.md`, `docs/RESUMEN-ACCIONES-RESILIENCIA.md`, `docs/OVERSEERR-INTERMITENCIA-SOLUCION.md`, `docs/storage_optimization_audit.md` → integrar o eliminar.
- [ ] Los docs de `docs/guides/` (salvo `08_plex_remote_access_setup.md`), `docs/runbooks/`, `docs/security/` y los análisis de resiliencia/Overseerr **no están versionados**: `~/.gitignore_global` ignora `docs`. Decidir qué se versiona (`git add -f`) y qué se archiva.
- [x] Limpieza 2026-10-01: eliminados playbooks de TrueNAS/one-off (`*truenas*`, `create_vms`, `mount_nfs`, `revert_nvidia_driver`, `shutdown_proxmox`, `resize_vm_disks`), 15 scripts obsoletos (TrueNAS, resiliencia, Plex one-off), manifiestos sin uso (`nfs-csi-driver`, HelmRelease de Traefik, dashboards/exporter/secret de TrueNAS, KSOPS) y restos Helm de Immich.

## 9. Otros

- [x] **webodm**: se mantiene con una sola instancia (webapp, worker, broker, db y un nodo de procesamiento `node-odx-1`, todos con 1 réplica). Los 3 PVC `local-path` (db, media, nodeodm) son necesarios; los 3 PV viejos de NFS se borran con el paso 3.
- [x] Plex y la suite *arr levantados sobre el pool nuevo (2026-10-03). ComfyUI pendiente de modelos. (Ollama + Open WebUI reactivados 2026-09-30; usan local-path.)
