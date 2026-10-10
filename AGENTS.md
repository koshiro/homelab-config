# Guía para agentes del homelab

Punto de entrada para cualquier agente que trabaje en este repo. El conocimiento vive en documentos versionados; esta
página dice cuál leer según la tarea y reúne las reglas que aplican siempre.

## Dónde está cada cosa

| Tarea | Leer | Contenido |
|-------|------|-----------|
| Nueva aplicación o portar una existente, Ingress, PVC | **`docs/DISENO-APPS.md`** | Contrato de la app, decisiones (nodo, almacenamiento, exposición, BD, respaldo), plantillas y despliegue |
| Apagado, encendido, reconstrucción, verificación rápida | `README.md` § Operación | Playbooks de apagado/encendido ordenado, tags de `playbook_provision_all.yml` |
| Playbooks Ansible, inventario, VMs | `ansible/playbooks/README.md`, `ansible/inventory` | Vault en `ansible/vars/vault.yml`, contraseña en `~/.config/homelab/ansible-vault-pass` |
| ZFS, NFS, sanoid/syncoid/restic, LXC `nas` en Proxmox | `proxmox/README.md` | Fuente de verdad del host: qué archivo del repo va a qué ruta |
| Suite arr, qBittorrent, Plex, Seerr (cola, atascos, calidad, actualizar) | **`.claude/skills/media-stack/SKILL.md`** | CLI `media.py` con salida compacta; leerla antes de explorar el repo o los pods |
| Respaldos y su verificación | `proxmox/README.md` § Tareas programadas, `cluster/00-infrastructure/backups/` | sanoid/syncoid/restic en el host + CronJobs `config-backup-*`, dump de Postgres y copia de etcd |
| Pi master (voltaje, boot, overclock, apagarla) | `pibot/README.md` | |
| Secretos SOPS / age | `README.md` § Operación y las reglas de abajo | |
| Arquitectura objetivo, pendientes | `docs/ARQUITECTURA.md`, `docs/PENDIENTES.md` | |
| Pentest web, evidencias, DTPlus / intranet | Repo hermano **`~/git/security-assessment`** (su `AGENTS.md`) | No recrear `security-assessment/` dentro de este repo |

## Reglas que aplican siempre

- **Apagado siempre ordenado** con `playbook_graceful_shutdown_cluster.yml`; nunca `poweroff --force` (corrompe NFS y
  Postgres).
- **`kubectl` local** funciona contra `k3s-node-0:6443`; no hace falta `ssh … sudo k3s kubectl`.
- **Logs de k3s**: en pibot el servicio es `k3s` (`ssh daniel@k3s-node-0 sudo journalctl -u k3s`); en los workers es
  `k3s-agent`.
- **Disco de los workers** (2026-10-10: node-1 100 GB al 65 %, node-2/3 50 GB al 49 %). `local-path`,
  imágenes y logs comparten ese disco. Revisar con `ansible k3s_nodes -i ansible/inventory -m shell -a 'df -h /'`.
- **SOPS**: `export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt`; editar un secreto cifrado en el lugar con
  `sops <archivo>.sops.yml`. Nunca versionar secretos en claro.
- **Cloudflare** (túneles, DNS, hostnames): lo hace el agente por API con `vault_cloudfare_full_api_token` del vault
  de Ansible. Todo Ingress `*.danielriquelme.cl` es público por el comodín del túnel.
- **Archivos nuevos en `docs/`**: el gitignore global de la máquina ignora `docs`; se agregan con `git add -f`.

## Arquitectura actual (resumen)

- **Cluster**: k3s en pibot (master) + 3 workers
- **Storage**: ZFS en el host Proxmox 192.168.1.100 (`nvme`, `respaldo`, `homelab-storage`), NFS desde el host; TrueNAS retirado
- **Dominio**: danielriquelme.cl
- **GitOps**: manifiestos en `cluster/` aplicados con kubectl; FluxCD planificado (ver docs/PENDIENTES.md)
- **Acceso remoto**: Tailscale (`ssh daniel@k3s-node-0`, MagicDNS del master pibot; kubectl local funciona)

## Flujo de ramas (GitHub Flow)

`main` es el estado del cluster: lo que está en `main` es lo que debe estar aplicado.

1. Cada cambio en una rama corta desde `main`, con el prefijo del tipo de commit: `feat/`, `fix/`, `chore/`, `docs/` (p. ej. `feat/qbittorrent-seed-limits`).
2. Commits con Conventional Commits en español: `tipo(ámbito): descripción` (`feat(comfyui): …`).
3. PR a `main` con `gh pr create`; merge con `gh pr merge --merge`. GitHub borra la rama remota sola (`deleteBranchOnMerge`); la local se borra con `git switch main && git pull && git branch -d <rama>`.
4. No hay `develop`, `release/` ni `hotfix/`: un arreglo urgente es una rama `fix/` más.
5. Si un cambio se aplica al cluster antes del merge (para probarlo), el PR se mergea apenas se confirma que funciona, para que `main` no quede detrás del cluster.

El repo es privado en el plan gratuito: GitHub no permite proteger `main`, así que el flujo se cumple por convención. Nada de push directo a `main` ni `--force`.

## Referencias

- **README.md**: Documentación principal del homelab
- **docs/**: `ARQUITECTURA.md` (arquitectura objetivo y fases), `PENDIENTES.md` y `DISENO-APPS.md` (cómo diseñar y portar apps para el cluster; leer antes de crear cualquier app)
- **proxmox/**: configuración versionada del host
- **pibot/**: configuración versionada de la Pi master (`config.txt` sin overclock, k3s, cómo apagarla)
- **scripts/**: Scripts de verificación y utilidades
