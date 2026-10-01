# Configuración del host Proxmox (pve, 192.168.1.100)

Copia versionada de lo que vive en el host. Fuente de verdad: este directorio; al cambiar algo en el host, actualizar aquí.

| Archivo del repo | Ruta en el host |
|---|---|
| `bin/notify-telegram` | `/usr/local/bin/notify-telegram` |
| `bin/restic-offsite.sh`, `bin/check-backups.sh` | `/usr/local/sbin/` |
| `systemd/*.service`, `systemd/*.timer` | `/etc/systemd/system/` |
| `systemd/drop-ins/sanoid-notify.conf` | `/etc/systemd/system/sanoid.service.d/notify.conf` |
| `systemd/drop-ins/syncoid-respaldo-notify.conf` | `/etc/systemd/system/syncoid-respaldo.service.d/notify.conf` |
| `etc/sanoid.conf` | `/etc/sanoid/sanoid.conf` |
| `etc/k8s.exports` | `/etc/exports.d/k8s.exports` (`exportfs -ra`) |
| `etc/zfs.conf` | `/etc/modprobe.d/zfs.conf` (ARC 8 GB; `update-initramfs -u`) |
| `etc/smartd.conf` | `/etc/smartd.conf` |
| `etc/smartd-run.d-20telegram` | `/etc/smartmontools/run.d/20telegram` |
| `etc/zed-all-telegram.sh` | `/etc/zfs/zed.d/all-telegram.sh` |
| `lxc-110-nas/110.conf` | `/etc/pve/lxc/110.conf` (+ `root:1000:1`, `root:3000:3` en `/etc/subuid` y `/etc/subgid`) |
| `lxc-110-nas/smb.conf` | `/etc/samba/smb.conf` dentro del LXC 110 |

## Secretos (no versionados)

En `/root/.secrets/` (modo 600). Copia maestra en `ansible/vars/vault.yml`:

| Archivo en el host | Contenido | Clave en el vault |
|---|---|---|
| `restic-r2.env` | Credenciales S3 de R2 (derivadas del token: ID del token y SHA-256 del token) y repositorio | `vault_cloudflare_api_token` |
| `restic-r2.password` | Contraseña del repositorio restic. **Sin ella el respaldo offsite es ilegible** | `vault_restic_r2_password` |
| `telegram.env` | `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID` | `vault_telegram_bot_token` |

## Tareas programadas

| Hora | Tarea |
|---|---|
| cada 15 min | sanoid: snapshots de `nvme/k8s/*` y poda de `respaldo/k8s/*` |
| 03:15 | (k8s) dump Postgres de Immich → `nvme/k8s/backups/postgres` |
| 03:30 | syncoid `nvme/k8s` → `respaldo/k8s` |
| 04:30 | restic → Cloudflare R2 (`homelab/restic`): immich, minecraft, backups |
| 08:00 | verificación de frescura de todos los respaldos (alerta Telegram; resumen los lunes) |
| 00:30 / 12:30 | (k8s) copia de snapshots de etcd de pibot |

Restaurar desde R2: `set -a; . /root/.secrets/restic-r2.env; set +a; restic snapshots; restic restore latest --target /tmp/restore --include /nvme/k8s/immich`.
