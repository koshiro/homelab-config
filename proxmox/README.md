# Configuración del host Proxmox (pve, 192.168.1.100)

Copia versionada de lo que vive en el host. Fuente de verdad: este directorio; al cambiar algo en el host, actualizar aquí.

| Archivo del repo | Ruta en el host |
|---|---|
| `bin/notify-telegram` | `/usr/local/bin/notify-telegram` |
| `bin/restic-offsite.sh`, `bin/check-backups.sh`, `bin/textfile-metrics.sh` | `/usr/local/sbin/` |
| `systemd/*.service`, `systemd/*.timer` | `/etc/systemd/system/` |
| `systemd/drop-ins/sanoid-notify.conf` | `/etc/systemd/system/sanoid.service.d/notify.conf` |
| `systemd/drop-ins/syncoid-respaldo-notify.conf` | `/etc/systemd/system/syncoid-respaldo.service.d/notify.conf` |
| `systemd/drop-ins/syncoid-replica-notify.conf` | `/etc/systemd/system/syncoid-replica.service.d/notify.conf` |
| `systemd/drop-ins/qemu-slice-sin-swap.conf` | `/etc/systemd/system.control/qemu.slice.d/50-MemorySwapMax.conf` (lo escribe `systemctl set-property qemu.slice MemorySwapMax=0`; en caliente) |
| `etc/sanoid.conf` | `/etc/sanoid/sanoid.conf` |
| `etc/k8s.exports` | `/etc/exports.d/k8s.exports` (`exportfs -ra`) |
| `etc/sysctl-99-swappiness.conf` | `/etc/sysctl.d/99-swappiness.conf` (`sysctl -p <archivo>`) |
| `etc/zfs.conf` | `/etc/modprobe.d/zfs.conf` (ARC 6 GB, `spl_kmem_cache_obj_per_slab=1`; `update-initramfs -u -k all`, efecto al reiniciar) |
| `etc/garage.toml`, `systemd/garage.service`, `bin/garagectl` | `/etc/garage.toml`, `/etc/systemd/system/garage.service`; binario `/usr/local/bin/garage` (v2.4.1, musl de garagehq.deuxfleurs.fr), usuario `garage`, secretos `/etc/garage/{rpc_secret,admin_token,cnpg-key.txt}` (0600); sus rutas van por variables de entorno en el unit. CLI: `garagectl status` (en `/usr/local/sbin/`) |
| `etc/smartd.conf` | `/etc/smartd.conf` |
| `etc/hdparm.conf` | `/etc/hdparm.conf` (HDD de `scratch` sin spindown, `sdc` con APM 254; lo aplica udev al detectar el disco, en vivo `hdparm -B 254 -S 0 <disco>`) |
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
| 102 | `k3s-node-1` | `host` | 6 (antes 8, 2026-10-10) | 24 GB | 150 GB | GPU RTX 3070 (`hostpci`): con passthrough la RAM queda fija entera en el host, sin balloon. Con 8 vCPU usaba los 8 hilos del host y le quitaba CPU a nfsd, ZFS y las otras VMs |
| 103 | `k3s-node-2` | `host` (aplicado 2026-10-10) | 4 | 8 GB | 80 GB | Antes sin `cpu:` → `kvm64`, sin x86-64-v2 |
| 104 | `k3s-node-3` | `host` (aplicado 2026-10-10) | 6 | 12 GB (antes 16, bajada 2026-10-10) | 80 GB | Igual que 103 |

Las tres usan `scsihw: virtio-scsi-single` (con `virtio-scsi-pci` el `iothread=1` del disco no tiene efecto) y
`scsi0: …,iothread=1,discard=on,ssd=1`, para que el `fstrim.timer` semanal del invitado devuelva espacio al zvol (sin
`discard` el zvol de node-1 ocupaba 81 GB para un disco de 80). Todas tienen `agent: 1` con `qemu-guest-agent`
instalado en el invitado. Los discos se agrandan en caliente: `qm resize <vmid> scsi0 +NG` y en el invitado
`growpart /dev/sda 1 && resize2fs /dev/sda1` (2026-10-10: node-1 80→100 GB, node-2/3 30→50 GB; 2026-10-18: node-1 →150 GB, node-2/3 →80 GB).
**Zvols sin `refreservation` desde el 2026-10-18** (`zfs set refreservation=none`): con reserva completa, cada
snapshot de sanoid cobraba de nuevo todo lo referenciado (~86 GB) al pool. La suma de `volsize` (310 GB) más
`nvme/k8s` sigue bajo los 461 GB útiles, así que no hay sobreasignación; el margen se vigila con `zfs list nvme`.

Evaluado y descartado (2026-10-10): **CPU pinning / `isolcpus` / `iothreadpin`**. El host tiene 4 núcleos (8 hilos) para
16 vCPU, y ZFS, nfsd y el LXC `nas` necesitan esos mismos núcleos: aislar núcleos les quitaría CPU, y el disco local de
las VMs casi no tiene I/O (la carga es NFS). **`aio`/caché**: ya está en lo óptimo por defecto (`aio=io_uring`,
`cache=none` → `direct`, zvol como dispositivo de bloque); `aio=native` no aporta sobre zvol.

**Presupuesto de RAM del host (64 GB):** VMs 102–104 = 44 GB + LXC 110 = 1 GB + ARC hasta 6 GB + host. La VM 105
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
(`zfs_arc_max` 6 GB, bajado de 8 el 2026-10-10 para dar margen tras reiniciar VMs), el LXC `nas`, nfsd y el propio host. Hoy el cluster usa 44 GB (102: 24, 103: 8, 104: 12), así que
**una VM extra de laboratorio (p. ej. la 105, 12 GB) no cabe con el cluster encendido** sin achicar otra.

Por qué importa: con la RAM sobrecomprometida el swap del host se llena (estuvo al 100 % del 2026-10-08 al 10-10).

**Swap con RAM libre (bug de ZFS 2.4 + kernel 7.0, [openzfs#18893](https://github.com/openzfs/zfs/issues/18893)):**
aunque sobren 15–20 GB, ZFS hace crecer sus caches de bloques de 1M (`spl_cache_grow_work` → `__vmalloc`) pidiendo
bloques de orden 10; desde el kernel 7.0 ese intento despierta a `kswapd`, y como el host casi no tiene caché de
páginas, kswapd encoge el ARC y manda a swap RAM fría de las VMs, que nunca vuelve. Mitigación desde 2026-10-10:
`qemu.slice` con `MemorySwapMax=0` (las VMs no van a swap; los daemons del host y el LXC sí). Contrapartida: ante
presión real el OOM killer actúa antes, por eso importa el presupuesto de arriba. Arreglo definitivo pendiente en
`docs/PENDIENTES.md` § 4b3. Verificación: `cat /sys/fs/cgroup/qemu.slice/memory.swap.max` (debe ser `0`).

Consecuencia antigua del swap lleno, por si vuelve a ocurrir: Con presión de memoria, nfsd del
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

`nvme` es el pool raíz (lo importa el initramfs, `cachefile=none`). **`/etc/zfs/zpool.cache` queda vacío en cada arranque**, así que `zfs-import-cache` se salta: `respaldo` se importa con `zfs-import@respaldo.service` (habilitado 2026-10-01), que no depende del cache. `homelab-storage` (recreado 2026-10-03 en el disco de 12 TB) se importa con `zfs-import@homelab\x2dstorage.service`: el `-` del nombre de instancia **debe ir escapado** (`systemd-escape homelab-storage`), porque `%I` convierte `-` en `/` y `zfs-import@homelab-storage` busca el pool `homelab/storage`. Así falló el reinicio del 2026-10-15 (pool sin importar, LXC `nas` sin arrancar y los PVC de `homelab-storage` sin NFS). El `boot-pool` de TrueNAS desapareció con la VM 101 (2026-10-10). `scratch` se importa con `zfs-import@scratch.service` (habilitado 2026-10-10). Si se recrea el cache: `update-initramfs -u -k all`.

## Discos y pools

| Disco | Uso |
|---|---|
| `sda` SSD SATA GIGABYTE 240 GB | Arranque: `sda1-3` (BIOS, EFI, LVM `pve` de 112 GB). `sda4` (32 GiB, etiqueta `zfs-slog-homelab`): SLOG de `homelab-storage`. Quedan ~78 GiB sin particionar. Respaldo de la GPT previa: `/root/sda-gpt-backup-20261010.bin` |
| `nvme0n1` NXM-512 2242 (512 GB, MAXIO MAP1202 sin DRAM) | Pool `nvme` (raíz, **un solo disco desde 2026-10-17**) |
| `nvme1n1` NE-512 2280 (512 GB, INNOGRIT IG5216 sin DRAM) | Pool `replica` (desde 2026-10-18): réplica horaria de `nvme` (syncoid). Sacado del espejo `nvme` el 2026-10-17 por lento; ver abajo y `docs/PENDIENTES.md` § 4f |
| `sdb` Seagate 12 TB | Pool `homelab-storage` (un solo disco) |
| `sde` WD 3 TB | Pool `respaldo` (réplica syncoid) |
| `sdc` WD 1 TB (2,5") + `sdd` WD 2 TB (~10 años de uso) | Pool `scratch` (stripe, 2,6 TB, sin redundancia ni snapshots). `scratch/qbittorrent` (`recordsize=16K`, `sync=disabled`): descargas incompletas de qBittorrent vía NFS. **Se usan hasta que mueran** (decisión 2026-10-25): si muere un disco, recrear el pool y volver a descargar. Para frenar el desgaste no se duermen (`etc/hdparm.conf`). Un sector pendiente se recupera reescribiendo el sector físico entero de 4K con `dd … bs=4096 oflag=direct`, después de comprobar con `zdb -m scratch` que el metaslab no tiene datos. Con `hdparm --write-sector` de a 512 B el disco no lo recupera |

**`nvme` sin espejo (2026-10-17)**: `nvme1n1` escribía con 113–389 ms de latencia en ráfagas de 4–7 min (31 ms en
calma) contra 1–3 ms de `nvme0n1`, con el mismo enlace PCIe Gen3 x4, sin errores AER y SMART sano (13 % de desgaste,
0 errores; controlador a 81–91 °C). Un espejo escribe al ritmo del disco más lento: los tres workers llegaban a
50–85 % de iowait y Grafana daba `SQLITE_BUSY`. Se sacó con `zpool detach nvme nvme-NE-512_2280_9C50506007658`.
**Prueba aislada (2026-10-17, `scripts/ssd/prueba.sh`, 60 min)**: el disco es un **KingSpec NE-512** (ficha: 3D TLC,
hasta 2400/1700 MB/s). Tal como salió del pool (sin TRIM desde el 4-oct, `autotrim=off`), escritura secuencial 128K
QD4 a **29 MB/s con p99 de 169 ms** y fsync con media de 4,6 ms y p99 de 45 ms. Tras `blkdiscard`, lo mismo da 1250
MB/s con p99 de 0,8 ms, pero un llenado de 1M QD8 rinde 1260 MB/s solo durante **~120 GB de caché SLC** y después
**~75 MB/s sostenidos** (316 GB en 45 min). Descartados: temperatura (composite estable en 53 °C; el sensor 1 marcó 91 °C
en la fase rápida y bajó a 75 °C cuando cayó la velocidad), APST (escrituras esporádicas iguales con y sin APST,
p99 ~15 ms) y la ranura (Gen3 x4, sin AER). Conclusión: la NAND, sin DRAM y casi llena sin TRIM, no da abasto con las
escrituras de los txg de ZFS. Los umbrales térmicos que declara el firmware (110/255 °C) no son reales.
**`autotrim=on` en `nvme` desde el 2026-10-17** (antes solo el TRIM mensual del cron `zfsutils-linux`, que sigue
activo): los SSD sin DRAM pierden la caché SLC si no se les avisa del espacio libre. El disco que se agregue al
espejo hereda la propiedad.
Mientras no haya reemplazo, **los discos de las VMs y `nvme/k8s/*` no tienen redundancia**: los protege la réplica
nocturna de syncoid a `respaldo` y restic a R2. Volver a espejo: `zpool attach nvme nvme-NXM-512_2242_0007134003512
/dev/disk/by-id/nvme-<nuevo>` (resilver de ~192 GB) y después `zpool scrub nvme`.

**Pool `replica` en `nvme1n1` (2026-10-18)**: en vez de volver al espejo (cada escritura esperaría al NE-512, que
tras ~120 GB de caché SLC cae a 75 MB/s), recibe cada hora el incremental de `nvme` por syncoid: unos pocos GB que
caben en la caché, sin afectar la latencia de producción. Retiene 24 hourly y 7 daily. Hasta ahora los discos de las
VMs no tenían ninguna copia. Si muere `nvme0n1` (pérdida ≤1 h), se arranca desde la réplica sin copiar nada: crear
el storage `pvesm add zfspool replica --pool replica --content images,rootdir`, copiar
`/replica/pve-config/*.conf` a `/etc/pve/qemu-server/` (y `110.conf` a `/etc/pve/lxc/`) cambiando `nvme:` por
`replica:` en los discos, y arrancar las VMs (los cloudinit no se replican: `qm cloudinit update <vmid>` los
regenera). Creado con `zpool create -o ashift=12 -o autotrim=on -O compression=on
-O atime=off -O xattr=sa -O mountpoint=/replica -O canmount=off replica /dev/disk/by-id/nvme-NE-512_2280_9C50506007658`
más `zfs create replica/k8s` (destino de syncoid con `--skip-parent`) y `zfs create -o canmount=on
replica/pve-config`, y `zfs-import@replica.service`. Cuando llegue el disco con DRAM, el espejo de `nvme` lo usa a él y este disco sigue
como réplica o pasa a copia fría.

**SLOG (2026-10-10)**: el export NFS es `sync` y cada COMMIT esperaba al ZIL en el mismo HDD de 12 TB (COMMIT ~1,2 s, WRITE ~91 ms en el cliente). Con el ZIL en `sda4` bajó a ~200 ms y ~20 ms. Es un SSD de consumo sin PLP y sin espejo: si falla solo, ZFS sigue sin él; se pierden datos únicamente si falla junto con una caída del host. Quitarlo: `zpool remove homelab-storage <id>-part4`.

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
| cada 15 min | sanoid: snapshots de `nvme/k8s/*` y de los discos de las VMs 102–104 y del LXC 110; poda de `respaldo/k8s/*` y `replica/*` |
| :20 cada hora | syncoid `nvme/k8s` (sin `victoria-metrics`), `nvme/vm-10{2,3,4}-disk-0` y `nvme/subvol-110-disk-0` → pool `replica` (nvme1n1); copia las configs de las VMs/LXC a `/replica/pve-config` |
| 02:40–02:48 | (k8s) `config-backup-*`: config y bases de datos de las apps con PVC local-path, hostPath o en `homelab-storage` (qBittorrent, `user/` de ComfyUI) → `nvme/k8s/backups/apps/<app>` |
| 03:15 | (k8s) dump Postgres de Immich → `nvme/k8s/backups/postgres` (5 días) |
| 03:30 | syncoid `nvme/k8s` → `respaldo/k8s` (excepto `victoria-metrics`: métricas, se pueden perder) y rsync de ComfyUI sin modelos (`user`, `input`, `output`, `swarmui/Data`) → `respaldo/comfyui` (snapshots sanoid) |
| 04:30 | restic → Cloudflare R2 (`homelab/restic`): immich, minecraft, backups, webs; sin lo regenerable; retiene 3 diarios + 2 semanales (objetivo < 10 GB, nivel gratuito) |
| 08:00 | verificación de frescura de todos los respaldos (alerta Telegram; resumen los lunes) y ping al monitor externo (`cloudflare/monitor`, avisa si falta > 26 h) |
| 00:30 / 12:30 | (k8s) copia de snapshots de etcd de pibot |

Restaurar desde R2: `set -a; . /root/.secrets/restic-r2.env; set +a; restic snapshots; restic restore latest --target /tmp/restore --include /nvme/k8s/immich`.
