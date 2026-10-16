# Guía para agentes del homelab

Punto de entrada para cualquier agente que trabaje en este repo. El conocimiento vive en documentos versionados; esta
página dice cuál leer según la tarea y reúne las reglas que aplican siempre.

## Dónde está cada cosa

| Tarea | Leer | Contenido |
|-------|------|-----------|
| **Cualquier tarea del homelab (empezar aquí)** | **`.claude/skills/homelab/SKILL.md`** | CLI `hl.py` (estado, app, NodePorts, ssh, SOPS, Cloudflare, secciones de docs), trampas conocidas y recetas; se amplía al cerrar cada tarea |
| Nueva aplicación o portar una existente, Ingress, PVC | **`docs/DISENO-APPS.md`** | Contrato de la app, decisiones (nodo, almacenamiento, exposición, BD, respaldo), plantillas y despliegue |
| Flux / GitOps (estado, desplegar, probar en caliente, deploy key) | skill homelab: `hl.py flux`, recetas *Flux en prod* y *cambio temporal en vivo*; `docs/PLAN-FLUX.md` | Una Kustomization por carpeta en `cluster/flux/`; fases pendientes del plan |
| Apagado, encendido, reconstrucción, verificación rápida | `README.md` § Operación | Playbooks de apagado/encendido ordenado, tags de `playbook_provision_all.yml`, Flux desde cero |
| Playbooks Ansible, inventario, VMs | `ansible/playbooks/README.md`, `ansible/inventory` | Vault en `ansible/vars/vault.yml`, contraseña en `~/.config/homelab/ansible-vault-pass` |
| ZFS, NFS, sanoid/syncoid/restic, LXC `nas` en Proxmox | `proxmox/README.md` | Fuente de verdad del host: qué archivo del repo va a qué ruta |
| Suite arr, qBittorrent, Plex, Seerr (cola, atascos, calidad, actualizar) | **`.claude/skills/media-stack/SKILL.md`** | CLI `media.py` con salida compacta; leerla antes de explorar el repo o los pods |
| ComfyUI (Media Assets, LoadImage, frontend, custom nodes, actualizar) | **`.claude/skills/comfyui/SKILL.md`** | CLI `comfy.py` (fuentes del frontend, API interna, assets) y cómo funcionan assets e historial |
| Respaldos y su verificación | `proxmox/README.md` § Tareas programadas, `cluster/00-infrastructure/backups/` | sanoid/syncoid/restic en el host + CronJobs `config-backup-*`, dump de Postgres y copia de etcd |
| Pi master (voltaje, boot, overclock, apagarla) | `pibot/README.md` | |
| Claude remoto (Remote Control desde claude.ai/móvil), memoria y skills sincronizadas con el Mac | `cluster/apps/claude-remote/README.md` | Pod con los repos en `/Users/daniel/git` y Syncthing de `~/.claude` (lista blanca) |
| Secretos SOPS / age | `README.md` § Operación y las reglas de abajo | |
| Arquitectura objetivo, pendientes | `docs/ARQUITECTURA.md`, `docs/PENDIENTES.md` | |
| Pentest web, evidencias, DTPlus / intranet | Repo hermano **`~/git/security-assessment`** (su `AGENTS.md`) | No recrear `security-assessment/` dentro de este repo |

## Reglas que aplican siempre

- **Apagado siempre ordenado** con `playbook_graceful_shutdown_cluster.yml`; nunca `poweroff --force` (corrompe NFS y
  Postgres).
- **`kubectl` local** funciona contra `k3s-node-0:6443`; no hace falta `ssh … sudo k3s kubectl`.
- **Logs de k3s**: en pibot el servicio es `k3s` (`ssh daniel@k3s-node-0 sudo journalctl -u k3s`); en los workers es
  `k3s-agent`.
- **Flux aplica todo `cluster/`** (desde 2026-10-16): un merge a `main` es el despliegue. Nada de `kubectl apply -k`
  ni `sops -d | kubectl apply`; un `kubectl edit/patch/scale` sobre algo gestionado se revierte en ≤10 min y
  `rollout restart` va con `--field-manager=reinicio-manual`. Probar en caliente: `flux suspend ks <app>` → cambio →
  PR → merge → `flux resume ks <app>`.
- **Disco de los workers** (2026-10-16, tras borrar imágenes sin uso: node-1 100 GB al 61 %, node-2/3 50 GB al ~50 %;
  el GC de imágenes del kubelet empieza al 85 %). `local-path`, imágenes y logs comparten ese disco. Revisar con
  `hl.py status`; liberar con `sudo k3s crictl --timeout=120s rmi --prune` en el nodo.
- **SOPS**: `export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt`; editar un secreto cifrado en el lugar con
  `sops <archivo>.sops.yml`. Nunca versionar secretos en claro.
- **Cloudflare** (túneles, DNS, hostnames): lo hace el agente por API con `vault_cloudfare_full_api_token` del vault
  de Ansible. Todo Ingress `*.danielriquelme.cl` es público por el comodín del túnel.
- **Archivos nuevos en `docs/`**: el gitignore global de la máquina ignora `docs`; se agregan con `git add -f`.

## Arquitectura actual (resumen)

- **Cluster**: k3s en pibot (master) + 3 workers
- **Storage**: ZFS en el host Proxmox 192.168.1.100 (`nvme`, `respaldo`, `homelab-storage`), NFS desde el host; TrueNAS retirado
- **Dominio**: danielriquelme.cl
- **GitOps**: Flux 2.9 aplica `cluster/` desde `main` (`cluster/flux/`, 28 Kustomizations); prune apagado y avisos
  pendientes (`docs/PLAN-FLUX.md`, fases 5–8)
- **Acceso remoto**: Tailscale (`ssh daniel@k3s-node-0`, MagicDNS del master pibot; kubectl local funciona)

## Flujo de ramas (GitHub Flow)

`main` es el estado del cluster: lo que está en `main` es lo que debe estar aplicado.

1. Cada cambio en una rama corta desde `main`, con el prefijo del tipo de commit: `feat/`, `fix/`, `chore/`, `docs/` (p. ej. `feat/qbittorrent-seed-limits`).
2. Commits con Conventional Commits en español: `tipo(ámbito): descripción` (`feat(comfyui): …`).
3. PR a `main` con `gh pr create`; merge con `gh pr merge --merge`. GitHub borra la rama remota sola (`deleteBranchOnMerge`); la local se borra con `git switch main && git pull && git branch -d <rama>`.
4. No hay `develop`, `release/` ni `hotfix/`: un arreglo urgente es una rama `fix/` más.
5. Flux aplica `main`, así que mergear es desplegar. Para probar un cambio antes del merge: `flux suspend ks <app>` → cambio a mano → PR → merge apenas se confirma que funciona → `flux resume ks <app>`. Nunca dejar una Kustomization suspendida (`hl.py flux` las lista).

El repo es privado en el plan gratuito: GitHub no permite proteger `main`, así que el flujo se cumple por convención. Nada de push directo a `main` ni `--force`.

## Referencias

- **README.md**: Documentación principal del homelab
- **docs/**: `ARQUITECTURA.md` (arquitectura objetivo y fases), `PENDIENTES.md` y `DISENO-APPS.md` (cómo diseñar y portar apps para el cluster; leer antes de crear cualquier app)
- **proxmox/**: configuración versionada del host
- **pibot/**: configuración versionada de la Pi master (`config.txt` sin overclock, k3s, cómo apagarla)
- **scripts/**: Scripts de verificación y utilidades
