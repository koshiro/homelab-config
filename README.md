# Homelab

Configuración de un homelab en Proxmox + k3s: VMs con Ansible, manifiestos de Kubernetes en `cluster/`, secretos con SOPS/age y exposición pública vía Cloudflare Tunnel.

> **Estado (2026-10-10):** TrueNAS retirado (VM 101 y plantilla 9001 destruidas el 2026-10-10). ZFS, NFS y snapshots viven en el host Proxmox (`192.168.1.100`). `homelab-storage` se recreó el 2026-10-03 en el disco de 12 TB (**un solo disco, sin redundancia**) y todas las apps están arriba: Immich, Minecraft y Pingvin desde `nvme/k8s`; Plex, la suite *arr, qBittorrent y ComfyUI desde `homelab-storage`. Todos los workers con `cpu: host` desde 2026-10-10. Ver **[docs/PENDIENTES.md](docs/PENDIENTES.md)**. Arquitectura objetivo (capas de almacenamiento, respaldos, fases): **[docs/ARQUITECTURA.md](docs/ARQUITECTURA.md)**.

## Arquitectura

| Componente | Detalle |
|---|---|
| **Proxmox** | `192.168.1.100` · 64 GB de RAM · pool ZFS `nvme` (mirror 2×512 GB) para discos de VMs. Presupuesto de RAM y cómo reiniciar una VM del cluster: [proxmox/README.md](proxmox/README.md) |
| **k3s** v1.35 | Master `pibot` (Raspberry Pi, `192.168.1.15`, sin taints) + workers `k3s-node-1/2/3` (VMs 102–104, `192.168.1.131–133`, 24/8/12 GB, `cpu: host`) |
| **GPU** | NVIDIA RTX 3070 en `k3s-node-1` (VM 102), `runtimeClassName: nvidia` |
| **Almacenamiento** | ZFS en el host Proxmox: `nvme` (datos de apps en `nvme/k8s/<app>`), `respaldo` (réplica), `homelab-storage` 12 TB (un disco, sin redundancia: `media` RAW, `k8s-media-library`, `comfyui`, `timemachine`). NFS desde `192.168.1.100`; SMB/Time Machine en el LXC 110 `nas`. Detalle: [proxmox/README.md](proxmox/README.md) |
| **Ingress** | Traefik (k3s) · `ingressClassName: traefik`, entrypoint `web`, sin bloque `tls` |
| **Exposición pública** | Cloudflare Tunnel gestionado **remotamente**. Túnel `pve` (conectores en los workers): `plex.danielriquelme.cl` directo, `*.danielriquelme.cl` → Traefik. Túnel `pibot-webs` (conector en pibot): sitios estáticos `josekast.cl`, `noledigasanadie.danielriquelme.cl` y `cyano.danielriquelme.cl` → NodePort, independiente de Proxmox. Todo Ingress con ese dominio es público, salvo los paneles de administración (`grafana`, `comfyui`, `swarmui`, `galeria`, `chat`, `sonarr`, `radarr`, `prowlarr`, `bazarr`, `qbittorrent`), protegidos por **Cloudflare Access** (app «Homelab admin», OTP por correo) |
| **Acceso privado** | Tailscale en cada nodo. Servicios internos por NodePort fijo: `http://k3s-node-0:<nodePort>` |
| **Base de datos** | CloudNative-PG en ns `postgresql` (`homelab-postgres-rw.postgresql.svc`) |
| **Monitoreo** | VictoriaMetrics + Grafana + vmalert → Alertmanager → Telegram (ns `monitoring`); reglas en `cluster/03-monitoring/monitoring/alert-rules.yml` |
| **GitOps** | Objetivo: FluxCD (**aún no instalado**). Hoy se aplica con `kubectl apply -k` |

## Acceso

```bash
ssh daniel@k3s-node-0        # master (pibot) por MagicDNS del tailnet
ssh root@192.168.1.100       # Proxmox
kubectl get nodes -o wide    # kubeconfig local apuntando a k3s-node-0:6443
```

kubeconfig desde el master:

```bash
ssh daniel@k3s-node-0 "sudo cat /etc/rancher/k3s/k3s.yaml" \
  | sed 's#https://127.0.0.1:6443#https://k3s-node-0:6443#' > ~/.kube/config-homelab
export KUBECONFIG=~/.kube/config-homelab
```

## Servicios

| App | Namespace | Acceso | Almacenamiento | Estado |
|---|---|---|---|---|
| Immich | `immich` | `immich.danielriquelme.cl` | NFS Proxmox `nvme/k8s/immich` + CNPG | ✅ |
| Minecraft | `minecraft` | `minecraft.danielriquelme.cl` (Java 25565 / Bedrock 19132, LoadBalancer + DDNS) | NFS Proxmox `nvme/k8s/minecraft` | ✅ proxy Velocity + Geyser, servidores Paper `principal`, `spiral2`, `spiral3`, bot de whitelist ([LOBBY.md](cluster/apps/minecraft/LOBBY.md)) |
| Pingvin | `pingvin` | `pingvin.danielriquelme.cl` | NFS Proxmox `nvme/k8s/pingvin` | ✅ |
| Plex | `plex` | `plex.danielriquelme.cl` · NodePort 32400 | config local-path + media NFS `homelab-storage/k8s-media-library` | ✅ |
| Sonarr, Radarr, Prowlarr, Bazarr | ns propio | `<app>.danielriquelme.cl` | config local-path + media NFS `k8s-media-library` | ✅ |
| qBittorrent | `qbittorrent` | `qbittorrent.danielriquelme.cl` · NodePort 30808 · BT 6881 por `hostPort` en k3s-node-1 · WebUI sin login desde la red de pods (Access protege lo público) | media NFS `k8s-media-library` | ✅ |
| Seerr (ex-Overseerr) | `overseerr` | `seerr.danielriquelme.cl`, `overseerr.danielriquelme.cl` | local-path | ✅ |
| FlareSolverr | `flaresolverr` | interno (Prowlarr) | — | ✅ |
| Ollama / Open WebUI | `ollama-stack` | `k3s-node-0:31434` / `chat.danielriquelme.cl` · NodePort 30080 | local-path (no depende de NFS) | ✅ GPU |
| ComfyUI | `comfyui` | `comfyui.danielriquelme.cl` · NodePort 30188 · `comfyui.lan` | NFS `homelab-storage/comfyui` | ✅ GPU ([README](cluster/apps/comfyui/README.md)) |
| SwarmUI | `comfyui` | `swarmui.danielriquelme.cl` · NodePort 30190 · `swarmui.lan` | NFS `comfyui` (`swarmui/`, salidas en `output/swarmui`) | ✅ interfaz sobre ComfyUI, sin GPU propia |
| SmartGallery | `comfyui` | `galeria.danielriquelme.cl` · NodePort 30189 · `galeria.lan` | NFS `comfyui` (`smartgallery/`) | ✅ galería de `output/` |
| WebODM | `webodm` | NodePort 31808 (tailnet) | local-path | ✅ |
| AirPrint Canon MP250 | `canon-mp250-airprint` | LAN · admin CUPS NodePort 31631 | — | ✅ |
| noledigasanadie | `noledigasanadie` | `noledigasanadie.danielriquelme.cl` · NodePort 30891 | disco de pibot `/var/lib/homelab-noledigasanadie` (respaldo diario al NAS) | ✅ en pibot |
| josekast.cl | `josekast` | `josekast.cl`, `www.josekast.cl` · NodePort 30890 | disco de pibot `/var/lib/homelab-josekast` (respaldo diario al NAS) | ✅ en pibot |
| Cyano Curve | `cyano` | `cyano.danielriquelme.cl` · NodePort 30892 | disco de pibot `/var/lib/homelab-cyano` (respaldo diario al NAS) | ✅ en pibot |
| Grafana + VictoriaMetrics | `monitoring` | `grafana.danielriquelme.cl` | local-path (Grafana) · NFS `nvme/k8s/victoria-metrics` (métricas, 90 días) | ✅ dashboards en `cluster/03-monitoring/monitoring/dashboards/`, alertas a Telegram |

### Sitios estáticos (josekast.cl, noledigasanadie, cyano)

Regla: **los sitios estáticos corren en pibot con almacenamiento propio y deben seguir en línea si cae Proxmox.** El NAS solo guarda un respaldo.

- **Pod:** nginx con `nodeName: pibot`, contenido en el disco NVMe de la Pi (`hostPath` `/var/lib/homelab-<sitio>`, solo lectura). Nada de NFS ni local-path de los workers.
- **Respaldo:** CronJob `config-backup-<sitio>` (02:47, [webs-estaticas-backup.yaml](cluster/00-infrastructure/backups/webs-estaticas-backup.yaml)) copia el sitio a `nvme/k8s/backups/apps/<sitio>/data` en Proxmox (sanoid + syncoid + R2); `check-backups.sh` avisa si pasan más de 26 h. Si Proxmox está caído el job falla, pero el sitio sigue sirviéndose.
- **Exposición:** túnel propio `pibot-webs`, conector `cloudflared-webs` en pibot ([deployment-webs.yml](cluster/06-external/cloudflared/deployment-webs.yml)) con origen en el NodePort de cada sitio (`http://192.168.1.15:30890` / `30891` / `30892`). No pasa por Traefik ni CoreDNS (corren en los workers) y resuelve DNS con el router (`dnsPolicy: Default`): con Proxmox caído solo hacen falta pibot e internet. Las rutas viven en Cloudflare (Zero Trust → Tunnels → `pibot-webs` → Public hostnames). El túnel `pve` conserva sus reglas `josekast.cl` y los Ingress siguen: volver atrás = apuntar el CNAME al túnel `pve`.
- **Publicar contenido:** `rsync -a --delete <carpeta>/ daniel@k3s-node-0:/var/lib/homelab-<sitio>/` (nginx sirve lo nuevo al instante). josekast.cl se genera con `~/git/twscrap/web/build.py` y se publica con `~/git/twscrap/web/publicar.sh`; Cyano Curve, con `~/git/cyano/scripts/publicar.sh`.
- **Restaurar desde el NAS:** `rsync -a root@192.168.1.100:/nvme/k8s/backups/apps/<sitio>/data/ /tmp/<sitio>/ && rsync -a --delete /tmp/<sitio>/ daniel@k3s-node-0:/var/lib/homelab-<sitio>/`.
- **Sitio nuevo:** copiar `cluster/apps/josekast` (Deployment en pibot + Service NodePort fijo + Ingress), crear `/var/lib/homelab-<sitio>` en pibot (`sudo install -d -o daniel -g daniel`), agregar su CronJob a `webs-estaticas-backup.yaml` y su nombre a `check-backups.sh`, y su Public hostname en el túnel `pibot-webs` → `http://192.168.1.15:<nodePort>`.

El dataset `nvme/k8s/webs` (antiguo origen NFS de josekast.cl) quedó sin uso; conserva la versión anterior del sitio en `webs/_respaldos/`.

## Estructura del repo

```
ansible/            Inventario, playbooks (provisioning/, maintenance/), rol nvidia_gpu
cluster/
  00-infrastructure/  NVIDIA device plugin, RuntimeClass; backups/: CronJobs config-backup-*, copia de etcd
  01-networking/      Middleware de Traefik (Traefik lo provee k3s)
  03-monitoring/      VictoriaMetrics, vmalert, Alertmanager, Grafana, node-exporter, kube-state-metrics, exporters de Proxmox y speedtest
  04-media-stack/     Plex, *arr, qBittorrent, FlareSolverr, PV de la media
  05-services/        Seerr (ns overseerr), Pingvin
  06-external/        cloudflared (túneles pve y pibot-webs)
  apps/               Immich, Minecraft, PostgreSQL, Ollama, ComfyUI, WebODM, AirPrint, sitios estáticos, …
  kustomization.yml   Raíz (compila con `kubectl kustomize cluster`; incompleta, ver PENDIENTES)
docs/               ARQUITECTURA.md, PENDIENTES.md, guides/
proxmox/            Configuración versionada del host (ZFS, NFS, sanoid, restic, LXC nas)
pibot/              Configuración versionada de la Pi master (boot, k3s, apagado ordenado)
scripts/            Respaldos, verificación y utilidades
backups/            Copias locales de configs (ignorado por git)
```

## Operación

**Apagado — siempre ordenado** (nunca `poweroff --force`):

```bash
ansible-playbook -i ansible/inventory ansible/playbooks/maintenance/playbook_graceful_shutdown_cluster.yml
#   -e apagar_proxmox=false   solo vacía/apaga VMs y LXC, deja el host encendido
#   -e apagar_pibot=true      apaga también el control-plane
#   -e confirmar=si           sin pregunta interactiva
```

Snapshot de etcd → cordon y vaciado de workers (Postgres/Immich/Minecraft cierran limpio) → apagado de LXC `nas` y VMs → host. pibot queda encendido por defecto.

**Encendido** (Proxmox arranca VMs y LXC solo; luego):

```bash
ansible-playbook -i ansible/inventory ansible/playbooks/maintenance/playbook_startup_cluster.yml
```

Verifica pools y NFS, espera workers Ready, hace `uncordon` y lista pods con problemas.

**Reconstruir** (bootstrap de Proxmox + k3s; las VMs se restauran desde vzdump):

```bash
ansible-galaxy collection install community.general kubernetes.core
ansible-playbook ansible/playbook_provision_all.yml   # vault: ~/.config/homelab/ansible-vault-pass
# Tags: bootstrap, wait, k3s, verify
```

Playbooks disponibles: [ansible/playbooks/README.md](ansible/playbooks/README.md).

**Desplegar una app:** ver [docs/DISENO-APPS.md](docs/DISENO-APPS.md) (contrato de la app, almacenamiento, exposición, plantillas y checklist). En corto: namespace → Deployment → Service → PVC → Ingress (`host: <app>.danielriquelme.cl`); el túnel ya enruta el comodín y todo Ingress queda público. Para servicios privados usar NodePort fijo y acceder por tailnet. Añadir la carpeta a `cluster/kustomization.yml`.

**Secretos (SOPS/age):**

```bash
sops --encrypt --age age1ga4dqzwv2wrf5c0dduz0vsjkzlda9xzrp787u2mnhhj6zh5qxaws4mlhhs \
  --encrypted-regex '^(data|stringData)$' secret.yaml > secret.sops.yaml
sops --decrypt secret.sops.yaml | kubectl apply -f -
```

Nunca versionar secretos sin cifrar. Dónde vive la clave y cómo se usa: [docs/security/02_sops_configuration.md](docs/security/02_sops_configuration.md).

**Kit de recuperación.** La clave age y la contraseña del vault de Ansible solo existen en el Mac; si se pierde, no
se descifra ningún `*.sops.*` ni se abre `ansible/vars/vault.yml` (token de Cloudflare, contraseña de restic). Hay dos
copias independientes:

- **A:** Contraseñas de Apple, entradas «homelab · clave age (SOPS)» y «homelab · contraseña vault Ansible» (campo Notas).
- **B:** `homelab-kit.age` en el bucket R2 `homelab-recuperacion` (dashboard de Cloudflare → R2 → descargar), cifrado
  con `age -p` y una frase anotada en papel. Va aparte del bucket `homelab` de restic.

```bash
# Mac nuevo: clonar el repo, brew install age sops ansible, y una de las dos:
scripts/kit-recuperacion.sh restaurar ~/Downloads/homelab-kit.age
scripts/kit-recuperacion.sh restaurar notas          # pega desde Contraseñas
# Comprobar cada copia por separado (carpeta vacía, solo esa copia): sops -d y ansible-vault view
scripts/kit-recuperacion.sh verificar-notas
scripts/kit-recuperacion.sh verificar-archivo        # lo baja de R2
# Rehacer tras rotar la clave o la contraseña
scripts/kit-recuperacion.sh notas && scripts/kit-recuperacion.sh cifrar
```

**Subir k3s** (de a un menor: 1.35 → 1.36 → …): snapshot de etcd en pibot
(`sudo k3s etcd-snapshot save --name pre-k3s-<menor>`) → `scripts/k3s-binario.sh` reemplaza solo el binario
(verificado por sha256, sin reescribir las unidades systemd, que tienen flags propios) → pibot primero y luego cada
worker con drain y uncordon, moviendo antes el primario de Postgres si está en ese nodo. Después actualizar
`k3s_version` del playbook y el límite de `registry.k8s.io/kubectl` en `renovate.json`. Pasos exactos: skill homelab,
`references/recetas.md` § Subir k3s.

**Respaldos:** sanoid (snapshots de `nvme/k8s/*`), syncoid a `respaldo`, restic a Cloudflare R2 y verificación diaria con alertas por Telegram, todo en el host Proxmox (ver [proxmox/README.md](proxmox/README.md#tareas-programadas)). En k8s: CronJobs `config-backup-<app>` (config de cada app a `nvme/k8s/backups/apps/`, 02:40–02:48), `immich/immich-db-backup` (pg_dump) y `backups/etcd-snapshot-copy`; `check-backups.sh` en el host avisa si alguno se atrasa.

**Verificación rápida:**

```bash
kubectl get pods -A | grep -vE 'Running|Completed'
kubectl get node k3s-node-1 -o jsonpath='{.status.allocatable.nvidia\.com/gpu}'
ansible all -i ansible/inventory -m ping
```

## Agentes

Ver **[AGENTS.md](AGENTS.md)**: qué documento leer según la tarea y reglas que aplican siempre. Pentest y evaluaciones de seguridad viven en el repo hermano `security-assessment`.
