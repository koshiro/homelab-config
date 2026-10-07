# Configuración de pibot (master k3s, 192.168.1.15)

Raspberry Pi **Compute Module 4** (4 núcleos, 4 GB, NVMe Toshiba 256 GB como raíz), Debian 12 bookworm,
k3s v1.33 con etcd embebido. Por tailnet es `k3s-node-0` (`ssh daniel@k3s-node-0`).

Copia versionada de lo que vive en el host. Fuente de verdad: este directorio; al cambiar algo en la Pi, actualizar aquí.

| Archivo del repo | Ruta en el host |
|---|---|
| `boot/config.txt` | `/boot/firmware/config.txt` (reiniciar para aplicar) |
| `boot/cmdline.txt` | `/boot/firmware/cmdline.txt` (una sola línea, sin salto final) |
| `etc/k3s-config.yaml` | `/etc/rancher/k3s/config.yaml` |

## Overclock moderado: 1800 MHz (2026-10-06)

`config.txt` tenía `over_voltage=9`, `arm_freq=2147` y `gpu_freq=750`. Con eso la entrada de 5 V caía:
`vcgencmd get_throttled` = `0x50005` (bajo voltaje y throttling activos, incluso en reposo) y el firmware dejaba la
CPU en **600 MHz**. Cambiar la fuente y el cable no lo arregló; lo que no aguanta la corriente es la entrada de la
placa base, no la fuente de 25 W (el CM4 no pasa de ~10–14 W ni con overclock).

Benchmark (`7z b`, `openssl speed -multi 4`) del 2026-10-06:

| Ajuste | 7z 1 hilo | 7z 4 hilos | sha256 | AES-128-GCM | Núcleo | Temp. máx. | `get_throttled` |
|---|---|---|---|---|---|---|---|
| 1500 MHz (de serie) | 1499 | 4674 | 527 MB/s | 220 MB/s | 0,87 V | 51,6 °C | `0x0` |
| **1800 MHz, `over_voltage=2`** | 1722 | 5354 | 646 MB/s | 265 MB/s | 0,92 V | 59,4 °C | `0x0` |
| 2000 MHz, `over_voltage=6` | — | — | — | — | 1,02 V | — | `0x50000` al arrancar |

Queda en **1800 MHz con `over_voltage=2`** (+15 % en 7z, +21 % en cripto, sin bajo voltaje). 2000 MHz ya marcó bajo
voltaje en el arranque. No subir `over_voltage` ni tocar `gpu_freq`: la GPU no se usa (sin pantalla, cámara ni
transcodificación) y solo suma consumo. El CM4 no tiene sensor de corriente (`vcgencmd pmic_read_adc` es solo de la
Pi 5): para medir watts hace falta un medidor USB-C o un enchufe inteligente. Respaldos en la Pi:
`/boot/firmware/config.txt.bak-oc-20261005` (OC original) y `config.txt.bak-pre-bench-20261006` (1500 MHz).

Verificar después de cualquier cambio de hardware o de `config.txt`:

```bash
ssh daniel@k3s-node-0 'vcgencmd get_throttled; vcgencmd measure_clock arm; vcgencmd measure_volts core'
# esperado: throttled=0x0, ~1800 MHz, ~0,92 V
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
