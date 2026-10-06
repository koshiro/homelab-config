# Homelab

Configuración de un homelab en Proxmox + k3s: VMs con Ansible, manifiestos de Kubernetes en `cluster/`, secretos con SOPS/age y exposición pública vía Cloudflare Tunnel.

> **Estado (2026-10-01):** TrueNAS se retira (VM 101 detenida). ZFS, NFS y snapshots viven en el host Proxmox (`192.168.1.100`). Immich, Minecraft y Pingvin ya corren desde `nvme/k8s`; Plex, la suite *arr y ComfyUI siguen en `replicas: 0` hasta reconectar el disco de 12 TB (`homelab-storage`, fase 1). Ver **[docs/PENDIENTES.md](docs/PENDIENTES.md)**. Arquitectura objetivo (retiro de TrueNAS, capas de almacenamiento, respaldos, fases): **[docs/ARQUITECTURA.md](docs/ARQUITECTURA.md)**.

## Arquitectura

| Componente | Detalle |
|---|---|
| **Proxmox** | `192.168.1.100` · pool ZFS `nvme` (mirror 2×512 GB) para discos de VMs |
| **k3s** v1.33 | Master `pibot` (Raspberry Pi, `192.168.1.15`) + workers `k3s-node-1/2/3` (VMs 102–104, `192.168.1.131–133`) |
| **GPU** | NVIDIA en `k3s-node-1` (VM 102), `runtimeClassName: nvidia` |
| **Almacenamiento** | ZFS en el host Proxmox: `nvme` (datos de apps en `nvme/k8s/<app>`), `respaldo` (réplica), `homelab-storage` 12 TB (media, pendiente de fase 1). NFS desde `192.168.1.100`; SMB/Time Machine en el LXC 110 `nas`. Detalle: [proxmox/README.md](proxmox/README.md) |
| **Ingress** | Traefik (k3s) · `ingressClassName: traefik`, entrypoint `web`, sin bloque `tls` |
| **Exposición pública** | Cloudflare Tunnel gestionado **remotamente**. Túnel `pve` (conectores en los workers): `plex.danielriquelme.cl` directo, `*.danielriquelme.cl` → Traefik. Túnel `pibot-webs` (conector en pibot): sitios estáticos `josekast.cl` y `noledigasanadie.danielriquelme.cl` → NodePort, independiente de Proxmox. Todo Ingress con ese dominio es público, salvo los paneles de administración (`grafana`, `comfyui`, `chat`, `sonarr`, `radarr`, `prowlarr`, `bazarr`), protegidos por **Cloudflare Access** (app «Homelab admin», OTP por correo) |
| **Acceso privado** | Tailscale en cada nodo. Servicios internos por NodePort fijo: `http://k3s-node-0:<nodePort>` |
| **Base de datos** | CloudNative-PG en ns `postgresql` (`homelab-postgres-rw.postgresql.svc`) |
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
| Minecraft | `minecraft` | LoadBalancer + DDNS | NFS Proxmox `nvme/k8s/minecraft` | ✅ |
| Pingvin | `pingvin` | `pingvin.danielriquelme.cl` | NFS Proxmox `nvme/k8s/pingvin` | ✅ |
| Plex | `plex` | `plex.danielriquelme.cl` | config local-path + media NFS | ⏸ 0 réplicas |
| Sonarr, Radarr, Prowlarr, Bazarr | ns propio | `<app>.danielriquelme.cl` | config local-path + media NFS `k8s-media-library` | ⏸ 0 réplicas |
| qBittorrent | `qbittorrent` | `http://k3s-node-0:30808` (solo tailnet) | media NFS `k8s-media-library` | ⏸ 0 réplicas |
| Overseerr | `overseerr` | `overseerr.danielriquelme.cl` | local-path | ✅ |
| FlareSolverr | `flaresolverr` | interno (Prowlarr) | — | ✅ |
| Ollama / Open WebUI | `ollama-stack` | `k3s-node-0:31434` / `chat.danielriquelme.cl` | local-path (no depende de NFS) | ✅ GPU RTX 3070 |
| ComfyUI | `comfyui` | `comfyui.danielriquelme.cl` | NFS `comfyui` | ⏸ 0 réplicas |
| WebODM | `webodm` | interno | local-path | ✅ |
| AirPrint Canon MP250 | `canon-mp250-airprint` | LAN | — | ✅ |
| noledigasanadie | `noledigasanadie` | `noledigasanadie.danielriquelme.cl` · NodePort 30891 | disco de pibot `/var/lib/homelab-noledigasanadie` (respaldo diario al NAS) | ✅ en pibot |
| josekast.cl | `josekast` | `josekast.cl`, `www.josekast.cl` · NodePort 30890 | disco de pibot `/var/lib/homelab-josekast` (respaldo diario al NAS) | ✅ en pibot |
| Grafana | `grafana` | `grafana.danielriquelme.cl` | ninguno (efímero) | ⚠️ ver plan de monitoreo |

### Sitios estáticos (josekast.cl, noledigasanadie)

Regla: **los sitios estáticos corren en pibot con almacenamiento propio y deben seguir en línea si cae Proxmox.** El NAS solo guarda un respaldo.

- **Pod:** nginx con `nodeName: pibot`, contenido en el disco NVMe de la Pi (`hostPath` `/var/lib/homelab-<sitio>`, solo lectura). Nada de NFS ni local-path de los workers.
- **Respaldo:** CronJob `config-backup-<sitio>` (02:47, [webs-estaticas-backup.yaml](cluster/00-infrastructure/backups/webs-estaticas-backup.yaml)) copia el sitio a `nvme/k8s/backups/apps/<sitio>/data` en Proxmox (sanoid + syncoid + R2); `check-backups.sh` avisa si pasan más de 26 h. Si Proxmox está caído el job falla, pero el sitio sigue sirviéndose.
- **Exposición:** túnel propio `pibot-webs`, conector `cloudflared-webs` en pibot ([deployment-webs.yml](cluster/06-external/cloudflared/deployment-webs.yml)) con origen en el NodePort de cada sitio (`http://192.168.1.15:30890` / `30891`). No pasa por Traefik ni CoreDNS (corren en los workers) y resuelve DNS con el router (`dnsPolicy: Default`): con Proxmox caído solo hacen falta pibot e internet. Las rutas viven en Cloudflare (Zero Trust → Tunnels → `pibot-webs` → Public hostnames). El túnel `pve` conserva sus reglas `josekast.cl` y los Ingress siguen: volver atrás = apuntar el CNAME al túnel `pve`.
- **Publicar contenido:** `rsync -a --delete <carpeta>/ daniel@k3s-node-0:/var/lib/homelab-<sitio>/` (nginx sirve lo nuevo al instante). josekast.cl se genera con `~/git/twscrap/web/build.py` y se publica con `~/git/twscrap/web/publicar.sh`.
- **Restaurar desde el NAS:** `rsync -a root@192.168.1.100:/nvme/k8s/backups/apps/<sitio>/data/ /tmp/<sitio>/ && rsync -a --delete /tmp/<sitio>/ daniel@k3s-node-0:/var/lib/homelab-<sitio>/`.
- **Sitio nuevo:** copiar `cluster/apps/josekast` (Deployment en pibot + Service NodePort fijo + Ingress), crear `/var/lib/homelab-<sitio>` en pibot (`sudo install -d -o daniel -g daniel`), agregar su CronJob a `webs-estaticas-backup.yaml` y su nombre a `check-backups.sh`, y su Public hostname en el túnel `pibot-webs` → `http://192.168.1.15:<nodePort>`.

El dataset `nvme/k8s/webs` (antiguo origen NFS de josekast.cl) quedó sin uso; conserva la versión anterior del sitio en `webs/_respaldos/`.

## Estructura del repo

```
ansible/            Inventario, playbooks (provisioning/, maintenance/), rol nvidia_gpu
cluster/
  00-infrastructure/  NVIDIA device plugin, RuntimeClass, CronJob de copia de etcd
  01-networking/      Middleware de Traefik (Traefik lo provee k3s)
  03-monitoring/      kube-prometheus-stack (HelmRelease, requiere Flux) + exporters
  04-media-stack/     Plex, *arr, qBittorrent, FlareSolverr
  05-services/        Overseerr, Pingvin
  06-external/        cloudflared
  apps/               Immich, Minecraft, PostgreSQL, Ollama, ComfyUI, WebODM, …
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

**Desplegar una app:** namespace → Deployment → Service → PVC → Ingress (`host: <app>.danielriquelme.cl`). El túnel ya enruta el comodín; no hace falta tocar Cloudflare. Para servicios privados usar NodePort fijo y acceder por tailnet. Añadir la carpeta a `cluster/kustomization.yml`.

**Secretos (SOPS/age):**

```bash
sops --encrypt --age age1ga4dqzwv2wrf5c0dduz0vsjkzlda9xzrp787u2mnhhj6zh5qxaws4mlhhs \
  --encrypted-regex '^(data|stringData)$' secret.yaml > secret.sops.yaml
sops --decrypt secret.sops.yaml | kubectl apply -f -
```

Nunca versionar secretos sin cifrar. Respaldo de la clave: `scripts/backup-sops-keys.sh` / `restore-sops-keys.sh`.

**Respaldos:** sanoid (snapshots de `nvme/k8s/*`), syncoid a `respaldo`, restic a Cloudflare R2 y verificación diaria con alertas por Telegram, todo en el host Proxmox (ver [proxmox/README.md](proxmox/README.md#tareas-programadas)). En k8s: CronJobs `immich/immich-db-backup` (pg_dump) y `backups/etcd-snapshot-copy`.

**Verificación rápida:**

```bash
kubectl get pods -A | grep -vE 'Running|Completed'
kubectl get node k3s-node-1 -o jsonpath='{.status.allocatable.nvidia\.com/gpu}'
ansible all -i ansible/inventory -m ping
```

## Agentes y skills

Ver **[AGENTS.md](AGENTS.md)**: skills locales en `.cursor/skills/` (mantenimiento, despliegue, Ansible, SOPS, respaldos). Pentest y evaluaciones de seguridad viven en el repo hermano `security-assessment`.
