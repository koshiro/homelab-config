# Configuración del host Proxmox (pve, 192.168.1.100)

Copia versionada de lo que vive en el host. Fuente de verdad: este directorio; al cambiar algo en el host, actualizar aquí.

| Archivo del repo | Ruta en el host |
|---|---|
| `bin/notify-telegram` | `/usr/local/bin/notify-telegram` |
| `bin/restic-offsite.sh`, `bin/check-backups.sh`, `bin/textfile-metrics.sh` | `/usr/local/sbin/` |
| `systemd/*.service`, `systemd/*.timer` | `/etc/systemd/system/` |
| `systemd/drop-ins/sanoid-notify.conf` | `/etc/systemd/system/sanoid.service.d/notify.conf` |
| `systemd/drop-ins/syncoid-respaldo-notify.conf` | `/etc/systemd/system/syncoid-respaldo.service.d/notify.conf` |
| `etc/sanoid.conf` | `/etc/sanoid/sanoid.conf` |
| `etc/k8s.exports` | `/etc/exports.d/k8s.exports` (`exportfs -ra`) |
| `etc/zfs.conf` | `/etc/modprobe.d/zfs.conf` (ARC 8 GB; `update-initramfs -u`) |
| `etc/smartd.conf` | `/etc/smartd.conf` |
| `etc/prometheus-node-exporter.default` | `/etc/default/prometheus-node-exporter` (paquete Debian `prometheus-node-exporter`, :9100; lo lee VictoriaMetrics del cluster) |
| `etc/smartd-run.d-20telegram` | `/etc/smartmontools/run.d/20telegram` |
| `etc/zed-all-telegram.sh` | `/etc/zfs/zed.d/all-telegram.sh` |
| `etc/logind-10-boton-encendido.conf` | `/etc/systemd/logind.conf.d/10-boton-encendido.conf` (ignora pulsación corta del botón; la larga es corte por hardware) |
| `lxc-110-nas/110.conf` | `/etc/pve/lxc/110.conf` (+ `root:1000:1`, `root:3000:3` en `/etc/subuid` y `/etc/subgid`) |
| `lxc-110-nas/smb.conf` | `/etc/samba/smb.conf` dentro del LXC 110 |
| `lxc-110-nas/samba-timemachine.sops.yaml` | Contraseña Samba de `timemachine` (aplicar con `smbpasswd -s timemachine` en el LXC 110; leer con `sops -d`) |
| `lxc-110-nas/samba-daniel.sops.yaml` | Contraseña Samba de `daniel` (share `archivo`, RAW; aplicar con `smbpasswd -s daniel` en el LXC 110; en el Mac está en el Llavero, servidor `nas`) |

## Pools ZFS al arrancar

`nvme` es el pool raíz (lo importa el initramfs, `cachefile=none`). **`/etc/zfs/zpool.cache` queda vacío en cada arranque**, así que `zfs-import-cache` se salta: `respaldo` se importa con `zfs-import@respaldo.service` (habilitado 2026-10-01), que no depende del cache. `homelab-storage` (recreado 2026-10-03 en el disco de 12 TB) se importa con `zfs-import@homelab-storage.service`; el `boot-pool` de TrueNAS se ve en `zpool import` pero **no** se importa solo (a propósito). Si se recrea el cache: `update-initramfs -u -k all`.

## Acceso fuera de banda (NanoKVM PCIe)

NanoKVM **PCIe** dentro del servidor, conectado al panel frontal (botones de encendido/reset) y a la salida de video. Firmware 2.5.0.

| | |
|---|---|
| Web | `http://kvm-7267` (tailnet) · `192.168.1.25` (cable) · usuario `admin`, contraseña `vault_kvm_admin_password` |
| MCP | `http://kvm-7267/api/mcp`, cabecera `Authorization: Bearer <vault_kvm_mcp_key>`. Herramientas: `cube_screenshot`, `cube_type_text`, `cube_press_keys`, `cube_click_mouse`, `cube_move_mouse`, `cube_scroll_mouse` (sin control de energía) |
| Energía (ATX) | API web: `GET /api/vm/gpio` (estado de LEDs `pwr`/`hdd`); `POST /api/vm/gpio` para pulsar power/reset. Requiere sesión web |

Login por API: el frontend cifra la contraseña con CryptoJS AES (frase `nanokvm-sipeed-2024`, formato OpenSSL `Salted__`, MD5) y la URL-codifica; equivalente:
`printf %s "$PASS" | openssl enc -aes-256-cbc -md md5 -salt -pass pass:nanokvm-sipeed-2024 -base64 -A` → `POST /api/auth/login {"username":"admin","password":"<urlencoded>"}` → token en cookie `nano-kvm-token`.

Claude Code: servidor MCP `nanokvm` en `.mcp.json` (raíz del repo). La cabecera la genera `headersHelper` leyendo la clave del Llavero de macOS (servicio `nanokvm-mcp`) al conectar; no depende de variables de entorno. Para rotar la clave: generar otra en el NanoKVM, actualizar el vault y `security add-generic-password -U -s nanokvm-mcp -a $USER -w`.

Uso típico: si el host se cuelga al apagar (pasó el 2026-10-01 con los snapshots bloqueados por el bug de ZFS 2.3.3), ver la consola por `cube_screenshot` y, si no responde, reset por ATX.

## Secretos (no versionados)

En `/root/.secrets/` (modo 600). Copia maestra en `ansible/vars/vault.yml`:

| Archivo en el host | Contenido | Clave en el vault |
|---|---|---|
| `restic-r2.env` | Credenciales S3 de R2 (derivadas del token: ID del token y SHA-256 del token) y repositorio | `vault_cloudflare_api_token` |
| `restic-r2.password` | Contraseña del repositorio restic. **Sin ella el respaldo offsite es ilegible** | `vault_restic_r2_password` |
| `telegram.env` | `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID` | `vault_telegram_bot_token` |
| `monitor.env` | `MONITOR_URL`, `HEARTBEAT_TOKEN` del Worker `cloudflare/monitor` | `vault_monitor_heartbeat_token` |

## Tareas programadas

| Hora | Tarea |
|---|---|
| cada 5 min | `textfile-metrics.sh`: pools ZFS, datasets y SMART → `/var/lib/prometheus/node-exporter/homelab.prom` |
| cada 15 min | sanoid: snapshots de `nvme/k8s/*` y poda de `respaldo/k8s/*` |
| 02:40–02:47 | (k8s) `config-backup-*`: config y bases de datos de las apps con PVC local-path → `nvme/k8s/backups/apps/<app>` |
| 03:15 | (k8s) dump Postgres de Immich → `nvme/k8s/backups/postgres` (5 días) |
| 03:30 | syncoid `nvme/k8s` → `respaldo/k8s` (excepto `victoria-metrics`: métricas, se pueden perder) |
| 04:30 | restic → Cloudflare R2 (`homelab/restic`): immich, minecraft, backups, webs; sin lo regenerable; retiene 3 diarios + 2 semanales (objetivo < 10 GB, nivel gratuito) |
| 08:00 | verificación de frescura de todos los respaldos (alerta Telegram; resumen los lunes) y ping al monitor externo (`cloudflare/monitor`, avisa si falta > 26 h) |
| 00:30 / 12:30 | (k8s) copia de snapshots de etcd de pibot |

Restaurar desde R2: `set -a; . /root/.secrets/restic-r2.env; set +a; restic snapshots; restic restore latest --target /tmp/restore --include /nvme/k8s/immich`.
