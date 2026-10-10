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
| `etc/sysctl-99-swappiness.conf` | `/etc/sysctl.d/99-swappiness.conf` (`sysctl -p <archivo>`) |
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

## VMs del cluster k3s

Configuración que se aparta de los valores por defecto de Proxmox (`qm config <vmid>`):

| VM | Nombre | `cpu` | `cores` | `memory` | Disco | Notas |
|---|---|---|---|---|---|---|
| 102 | `k3s-node-1` | `host` | 6 (antes 8, 2026-10-10) | 24 GB | 100 GB | GPU RTX 3070 (`hostpci`): con passthrough la RAM queda fija entera en el host, sin balloon. Con 8 vCPU usaba los 8 hilos del host y le quitaba CPU a nfsd, ZFS y las otras VMs |
| 103 | `k3s-node-2` | `host` (aplicado 2026-10-10) | 4 | 8 GB | 50 GB | Antes sin `cpu:` → `kvm64`, sin x86-64-v2 |
| 104 | `k3s-node-3` | `host` (aplicado 2026-10-10) | 6 | 12 GB (antes 16, bajada 2026-10-10) | 50 GB | Igual que 103 |

Las tres usan `scsihw: virtio-scsi-single` (con `virtio-scsi-pci` el `iothread=1` del disco no tiene efecto) y
`scsi0: …,iothread=1,discard=on,ssd=1`, para que el `fstrim.timer` semanal del invitado devuelva espacio al zvol (sin
`discard` el zvol de node-1 ocupaba 81 GB para un disco de 80). Todas tienen `agent: 1` con `qemu-guest-agent`
instalado en el invitado. Los discos se agrandan en caliente: `qm resize <vmid> scsi0 +NG` y en el invitado
`growpart /dev/sda 1 && resize2fs /dev/sda1` (2026-10-10: node-1 80→100 GB, node-2/3 30→50 GB).

**Presupuesto de RAM del host (64 GB):** VMs 102–104 = 44 GB + LXC 110 = 1 GB + ARC hasta 8 GB + host. La VM 105
(`opencontracts-lab`, 12 GB, temporal) deja el host con ~8 GB libres; con 16 GB en node-3 el host llegó a llenar sus 8
GB de swap con memoria de node-2/3. Antes de subir la RAM de una VM, revisar `free -m` y `swapon --show` en el host:
el swap debe quedar cerca de 0. Para vaciarlo con RAM libre suficiente: `swapoff -a && swapon -a`.

`cpu` y `memory` no se cambian en caliente: `qm set` los deja como cambio pendiente (`qm pending <vmid>`, en naranjo en
la interfaz web) hasta el próximo **stop/start desde Proxmox** (`qm shutdown` + `qm start`, `qm reboot`, el botón
*Reboot* de la interfaz o `playbook_graceful_shutdown_cluster.yml`). **Un `reboot` dentro del invitado no lo aplica**:
la VM sigue con el mismo proceso QEMU. Procedimiento por nodo: `kubectl drain <nodo> --ignore-daemonsets
--delete-emptydir-data`, `qm shutdown <vmid> && qm start <vmid>`, `kubectl uncordon <nodo>`. Si el nodo tiene el
primario de Postgres (`kubectl -n postgresql get cluster homelab-postgres -o jsonpath='{.status.currentPrimary}'`),
moverlo antes con `kubectl -n postgresql patch cluster homelab-postgres --subresource=status --type=merge -p
'{"status":{"targetPrimary":"<otra instancia>"}}'`. `playbook_graceful_shutdown_cluster.yml` y
`playbook_startup_cluster.yml` avisan si alguna VM tiene cambios pendientes.

### Presupuesto de RAM del host

El host tiene 62 GB. **La suma de la `memory` de las VMs encendidas no debe pasar de ~50 GB**: el resto es para el ARC
(`zfs_arc_max` 8 GB), el LXC `nas`, nfsd y el propio host. Hoy el cluster usa 44 GB (102: 24, 103: 8, 104: 12), así que
**una VM extra de laboratorio (p. ej. la 105, 12 GB) no cabe con el cluster encendido** sin achicar otra.

Por qué importa: los invitados llenan su RAM con caché de páginas NFS y el host no la recupera, así que con la RAM
sobrecomprometida el swap del host se llena (estuvo al 100 % del 2026-10-08 al 10-10). Con presión de memoria, nfsd del
kernel 7.0 reduce los *slots* de la sesión NFSv4.1 de cada cliente, y el cliente 5.15 de los workers no la vuelve a
agrandar: k3s-node-1 quedó con 1 slot (todo su I/O NFS en serie) y algunas escrituras quedaron reintentándose para
siempre. Así terminó qBittorrent con un hilo en estado D que no se podía matar.

Diagnóstico y salida, sin reiniciar el nodo:

```bash
# En el host: slots por cliente ("session target slots" muy por debajo de "session slots" = sesión encogida)
for f in /proc/fs/nfsd/clients/*/info; do grep -E "^name|session slots|target slots" $f | tr "\n" " "; echo; done
# En el worker: RPC NFS encolados (filas en "ForeChannel Slot table" o "delayq" que no bajan)
sudo mount -t debugfs none /sys/kernel/debug 2>/dev/null; sudo cat /sys/kernel/debug/sunrpc/rpc_clnt/*/tasks
```

1. Bajar la presión de memoria (apagar la VM de sobra) y vaciar el swap: `swapoff -a && swapon -a`.
2. Si el cliente sigue con pocos slots, forzar una sesión nueva desde el host, después de detener los pods que escriben
   mucho (qBittorrent): `echo expire > /proc/fs/nfsd/clients/<id>/ctl`. El cliente reabre sus archivos solo; los locks
   POSIX no se recuperan (`Lock reclaim failed` en `dmesg`), así que conviene revisar los pods con SQLite en NFS.
3. Un proceso que ya quedó en estado D sobre NFS se libera con `umount -f <montaje del pod>` en el worker (aborta los
   RPC pendientes de ese montaje).

La alerta `SwapHostProxmox` avisa cuando el swap del host pasa del 50 %.

## Pools ZFS al arrancar

`nvme` es el pool raíz (lo importa el initramfs, `cachefile=none`). **`/etc/zfs/zpool.cache` queda vacío en cada arranque**, así que `zfs-import-cache` se salta: `respaldo` se importa con `zfs-import@respaldo.service` (habilitado 2026-10-01), que no depende del cache. `homelab-storage` (recreado 2026-10-03 en el disco de 12 TB) se importa con `zfs-import@homelab-storage.service`. El `boot-pool` de TrueNAS desapareció con la VM 101 (2026-10-10). Si se recrea el cache: `update-initramfs -u -k all`.

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
