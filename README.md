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
| **Exposición pública** | Cloudflare Tunnel gestionado **remotamente**: `plex.danielriquelme.cl` directo, `*.danielriquelme.cl` y `josekast.cl` → Traefik. Todo Ingress con ese dominio es público, salvo los paneles de administración (`grafana`, `comfyui`, `chat`, `sonarr`, `radarr`, `prowlarr`, `bazarr`), protegidos por **Cloudflare Access** (app «Homelab admin», OTP por correo) |
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
| noledigasanadie | `noledigasanadie` | `noledigasanadie.danielriquelme.cl` | — | ✅ |
| josekast.cl | `josekast` | `josekast.cl`, `www.josekast.cl` (regla propia en el túnel) | NFS Proxmox `nvme/k8s/webs/josekast` (solo lectura) | ✅ |
| Grafana | `grafana` | `grafana.danielriquelme.cl` | ninguno (efímero) | ⚠️ ver plan de monitoreo |

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
