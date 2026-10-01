# Protección de datos – Minecraft

## Dónde están los datos

- **Única copia viva**: dataset ZFS `nvme/k8s/minecraft` en Proxmox (mirror NVMe), servido por NFS:
  `192.168.1.100:/nvme/k8s/minecraft` (volumen inline en `deployment.yml`).
- Kubernetes no crea ni borra ese almacenamiento: borrar el deployment o el namespace **no** borra el mundo.
- Copia antigua (solo lectura, versión 1.21.1, 2026-08-08): carpeta `minecraft-server` del dataset raíz de `homelab-storage` en TrueNAS.

## Respaldos

- **sanoid** en Proxmox (`/etc/sanoid/sanoid.conf`): snapshots horarios (24), diarios (14), semanales (4) y mensuales (6) de `nvme/k8s/*`.
- Snapshots manuales relevantes: `pre-minecraft-upgrade-20261001` (1.21.1 antes de actualizar), `pre-regen-20261001` (antes de regenerar terreno).
- Listar: `ssh root@192.168.1.100 'zfs list -t snapshot -r nvme/k8s/minecraft'`
- Restaurar un archivo: copiar desde `/nvme/k8s/minecraft/.zfs/snapshot/<snap>/...` en el host (no es visible por NFS).
- Restaurar todo: `kubectl -n minecraft scale deploy/minecraft --replicas=0` → `zfs rollback -r nvme/k8s/minecraft@<snap>` → escalar a 1.
- Pendiente: copia fuera del host (ver `docs/PENDIENTES.md`).

## Qué hace el deployment

1. **Cierre graceful**: `preStop` ejecuta `rcon-cli save-all`; luego el wrapper de la imagen envía `/stop`.
2. `terminationGracePeriodSeconds: 90` y estrategia `Recreate`: un solo pod escribe en el mundo.
3. Plugins gestionados por variables (`PLUGINS`, `MODRINTH_PROJECTS`); `REMOVE_OLD_MODS` borra los `.jar` viejos en cada arranque. No copiar plugins a mano: añadirlos a `MODRINTH_PROJECTS`.

## Qué no hacer

- No cambiar `server`/`path` del volumen sin snapshot previo.
- No escribir archivos en el volumen con otro UID: el servidor corre como **uid 1000**. Si algo queda con otro dueño: `ssh root@192.168.1.100 'chown -R 1000:1000 /nvme/k8s/minecraft/world'`.
- No subir `VERSION` sin snapshot: la conversión del mundo es irreversible.

## Historial

- **2026-10-01**: actualizado 1.21.1 → **26.2** (Paper 26.2-129, Java 25). Plugins a última versión. Datapacks Vanilla Tweaks a versiones 26.2 (las de 1.21 quedan en `world/datapacks-old-1.21/`).
- **2026-10-01**: regenerado el terreno sin cambios con MCA Selector 2.9: borrados los chunks con `InhabitedTime < 2 minutos` en overworld y nether (overworld 445 → 115 MB, nether 59 → 21 MB); se regeneran con la generación de 26.2 al explorarlos. End restaurado completo (portal de salida). Re-importados 2 chunks con portal del nether en x≈-288 z≈-1790.
