# Configuración de pibot (master k3s, 192.168.1.15)

Raspberry Pi **Compute Module 4** (4 núcleos, 4 GB, NVMe Toshiba 256 GB como raíz), Debian 12 bookworm,
k3s v1.33 con etcd embebido. Por tailnet es `k3s-node-0` (`ssh daniel@k3s-node-0`).

Copia versionada de lo que vive en el host. Fuente de verdad: este directorio; al cambiar algo en la Pi, actualizar aquí.

| Archivo del repo | Ruta en el host |
|---|---|
| `boot/config.txt` | `/boot/firmware/config.txt` (reiniciar para aplicar) |
| `boot/cmdline.txt` | `/boot/firmware/cmdline.txt` (una sola línea, sin salto final) |
| `etc/k3s-config.yaml` | `/etc/rancher/k3s/config.yaml` |

## Sin overclock (2026-10-05)

`config.txt` tenía `over_voltage=9`, `arm_freq=2147` y `gpu_freq=750`. Con eso la fuente no daba abasto:
`vcgencmd get_throttled` = `0x50005` (bajo voltaje y throttling activos) y el firmware dejaba la CPU en **600 MHz**,
más lento que sin overclock. Cambiar la fuente y el cable no lo arregló; comentar esas tres líneas sí, con la fuente
original de 25 W: `0x0`, 1500 MHz, 0,87 V en el núcleo. **No reactivar el overclock.** Respaldo del original en la Pi:
`/boot/firmware/config.txt.bak-oc-20261005`.

Verificar después de cualquier cambio de hardware o de `config.txt`:

```bash
ssh daniel@k3s-node-0 'vcgencmd get_throttled; vcgencmd measure_clock arm; vcgencmd measure_volts core'
# esperado: throttled=0x0, ~1500 MHz
```

## Qué corre aquí

Además del plano de control y etcd, solo lo que depende de la Pi: `cups-airprint` (impresora por USB) y
`noledigasanadie` (hostPath `/var/lib/homelab-noledigasanadie`). `cloudflared` está fijado a los workers x86
(`cluster/06-external/cloudflared/deployment.yml`); Traefik, CoreDNS, Immich y Grafana no están fijados y quedaron en
los workers tras el mantenimiento del 2026-10-05.

## Apagarla sin cortar los servicios

1. Snapshot de etcd y copia al NAS (el CronJob `backups/etcd-snapshot-copy` solo copia `etcd-snapshot-*`):
   `sudo k3s etcd-snapshot save --name <motivo>`.
2. `kubectl cordon pibot` y borrar los pods que pueden vivir en otro nodo (todos salvo `cups-airprint`,
   `noledigasanadie` y los `svclb-*`). No usar `drain`: movería esos dos y noledigasanadie arrancaría sin datos.
3. Comprobar los sitios y apagar: `sudo shutdown -h now`. Sin el master, los pods siguen corriendo pero no hay API.
4. Al volver: `kubectl uncordon pibot`. Durante 1–2 min flannel no llega a los pods de la Pi (502 en
   noledigasanadie); el operador CNPG puede reiniciarse varias veces hasta que vuelve la API.
