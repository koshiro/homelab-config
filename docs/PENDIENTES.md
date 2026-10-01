# Pendientes del homelab

Última revisión: 2026-09-30. Orden sugerido: **1 → 2 → 3**; el resto cuando el cluster esté estable.

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
1. [ ] Cambiar cable SATA + cable de poder del 12 TB (cables encargados). Probar otro puerto.
2. [ ] BIOS: controladora SATA en AHCI.
3. [ ] Verificar enlace: `dmesg -T | grep ata4` → 6.0 Gbps sin resets, con NCQ activado.
4. [ ] Si el enlace queda limpio y se sigue usando NCQ off: hacerlo persistente (regla udev o `libata.force=4.00:noncq`).
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
- [ ] Base de datos de Immich está en CloudNative-PG (`local-path`), no en TrueNAS. Revisar `homelab-postgres-3` (CrashLoop en k3s-node-1) — recrear la réplica: borrar su PVC + pod.

## 3. Limpieza del cluster ✅ (2026-10-01)

- [x] PVs huérfanos eliminados (12).
- [ ] Dataset `openclaw` en TrueNAS: borrar cuando el pool vuelva (app eliminada).

## 4. Seguridad

- [x] Immich: credenciales de DB desde el secret `homelab-postgres-app` (`DB_USERNAME`/`DB_PASSWORD`), sin contraseña en el manifiesto (2026-10-01).
- [x] Secret `homelab-postgres-app` regenerado sin salto de línea (2026-10-01).
- [ ] `/root/truenas-rescate/freenas-v1.db` en Proxmox contiene configuración y secretos cifrados de TrueNAS: borrar tras retirar TrueNAS (fase 3).
- [ ] TrueNAS tenía un kubeconfig de admin en `/root/.kube` (zvol de la VM 101): se elimina con `qm destroy 101`.

- [x] Contraseña del vault rotada (2026-10-01): `ansible-vault rekey`, nueva contraseña fuera del repo en `~/.config/homelab/ansible-vault-pass` (guardarla también en el gestor de contraseñas), `.vault_password.txt` eliminado de git e ignorado. El historial solo contiene una versión antigua del vault con `vault_truenas_password` (TrueNAS se retira).
- [ ] `.truenas-api-key`: sigue versionado; eliminar al retirar TrueNAS (fase 3).
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
- [ ] Ventana de mantención: `playbook_graceful_shutdown_cluster.yml -e apagar_proxmox=false` → `apt full-upgrade` en Proxmox (9.0.3 → 9.2, ZFS 2.3.3 → 2.4.4, kernel 6.14.11) → `reboot` → `playbook_startup_cluster.yml`. **No** ejecutar `zpool upgrade` (no es necesario y no se puede revertir).
- [ ] Tras reiniciar: borrar snapshots `@restic-offsite` y `nvme/k8s/webs@prueba-mount`, lanzar `restic-offsite.service` y verificar en R2.

## 4c. VMs k3s-node-2/3 con CPU kvm64

VM 103 y 104 no tienen `cpu:` en Proxmox → QEMU usa `kvm64` (sin x86-64-v2). Immich ML v3 lo exige, por eso está fijado a k3s-node-1 (`cpu: host`).
- [ ] En la próxima mantención: `qm set 103 --cpu x86-64-v2-AES` y `qm set 104 --cpu x86-64-v2-AES` (requiere reiniciar cada VM) y quitar el `nodeSelector` de Immich ML.

## 5. Monitoreo — plan Grafana (después de estabilizar)

**Estado actual:**
- ns `grafana`: `grafana/grafana:latest` aplicado a mano, **sin volumen** (dashboards/usuarios se pierden al reiniciar), sin manifiestos en el repo.
- ns `monitoring`: `pve-exporter`, `speedtest-exporter`, `truenas-node-exporter` corriendo, pero **no hay Prometheus** que los scrapee.
- Repo `cluster/03-monitoring/monitoring/`: `HelmRelease` kube-prometheus-stack 61.1.0 (requiere Flux) + `secret-generator.yaml` (KSOPS, era ArgoCD). Capa comentada en `cluster/kustomization.yml`.

**Plan:**
1. Instalar Flux (sección 6) — el HelmRelease ya existe.
2. kube-prometheus-stack en ns `monitoring` con Grafana incluido; valores mínimos para Raspberry + 3 workers: retención 7d, PVC `local-path` 10 Gi para Prometheus (luego NFS de Proxmox), Alertmanager desactivado al inicio.
3. Actualizar chart a versión actual y fijar imagen de Grafana (no `latest`).
4. Scrape configs para los exporters existentes (`additionalScrapeConfigs` o `ServiceMonitor`); reemplazar `truenas-node-exporter` según el destino de TrueNAS.
5. Dashboards como ConfigMaps con label `grafana_dashboard: "1"` (ya hay 2 de TrueNAS en el repo).
6. Secretos (`secret-grafana`, `secret-proxmox`, `secret-truenas-credentials`) vía SOPS con Flux (`decryption.provider: sops`), eliminar `secret-generator.yaml`.
7. Migrar/eliminar el Grafana manual del ns `grafana` y su Ingress.
8. Retomar `security-audit` (secret `midas-cookies`, ya eliminado del cluster) junto al monitoreo si hace falta.

## 6. GitOps con Flux

- [ ] `flux bootstrap github --owner=koshiro --repository=homelab-config --path=cluster --private`.
- [ ] Clave age en el cluster (`sops-age` secret en `flux-system`) y `decryption` en las Kustomizations.
- [ ] Completar `cluster/kustomization.yml` para que refleje TODO lo desplegado. Hoy faltan: `04-media-stack/{plex,sonarr,radarr,prowlarr,bazarr,qbittorrent}`, `apps/{immich,minecraft,postgresql}`, `03-monitoring`.
- [ ] Hasta entonces el flujo real es `kubectl apply -k` / `kubectl apply -f`. `kubectl kustomize cluster` compila (verificado 2026-09-30).

## 7. IoT (`cluster/07-iot/`)

- [ ] Configurar y desplegar `mosquitto`, `meshtastic`, `meshtastic-dashboard` (no desplegados). Guía: `docs/guides/10_meshtastic_setup.md`.

## 8. Documentación

- [ ] Rehacer `docs/` cuando el cluster esté estable: `docs/guides` tiene numeración duplicada (09_, 10_), varias guías describen estado antiguo (ArgoCD, TrueNAS). Estructura propuesta: `docs/arquitectura.md`, `docs/operacion/` (apagado, respaldos, SOPS), `docs/apps/<app>.md`, `docs/runbooks/`.
- [ ] Revisar `docs/RESILIENCIA-POST-APAGON-ANALISIS.md`, `docs/RESUMEN-ACCIONES-RESILIENCIA.md`, `docs/OVERSEERR-INTERMITENCIA-SOLUCION.md`, `docs/storage_optimization_audit.md` → integrar o eliminar.
- [ ] `scripts/check-resilience-status.sh` referencia `quick-resilience-fix.sh` (eliminado).

## 9. Otros

- [x] **webodm**: se mantiene con una sola instancia (webapp, worker, broker, db y un nodo de procesamiento `node-odx-1`, todos con 1 réplica). Los 3 PVC `local-path` (db, media, nodeodm) son necesarios; los 3 PV viejos de NFS se borran con el paso 3.
- [ ] Plex, ComfyUI y la suite *arr: `replicas: 0` hasta tener NFS. (Ollama + Open WebUI reactivados 2026-09-30; usan local-path.)
