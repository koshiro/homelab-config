# Agentes Especializados del Homelab

Este documento describe los **subagentes** y **skills** disponibles para trabajar de forma óptima con el cluster homelab. Los agentes están optimizados con conocimiento de contexto específico del ecosistema.

## Cómo usar

1. **Skills** (en `.cursor/skills/`): Se aplican automáticamente cuando el agente detecta tareas relacionadas. Proveen conocimiento de dominio persistente.

2. **Subagentes** (en `.cursor/agents/`): Definiciones para delegar tareas específicas. Usar el comando o menú de Cursor para lanzar un agente especializado.

3. **mcp_task** (si disponible): Para tareas paralelas o exploración profunda, usar `subagent_type: explore` o `generalPurpose` con prompts que referencien los skills.

## Mapa de delegación por tipo de tarea

| Tarea | Skill / Agente | Descripción |
|-------|----------------|-------------|
| Apagado, mantenimiento, troubleshooting cluster | homelab-maintenance / agent-maintenance | Apagado ordenado, verificación estado, GPU |
| ZFS, NFS, sanoid/syncoid, LXC `nas` en Proxmox | — | Ver `proxmox/README.md` (fuente de verdad del host) |
| Pi master (voltaje, boot, apagarla) | — | Ver `pibot/README.md` |
| Nueva aplicación o portar una existente, Ingress, PVC | **`docs/DISENO-APPS.md`** | Contrato de la app, decisiones (nodo, almacenamiento, exposición, BD, respaldo), plantillas y despliegue. Reemplaza a la skill `homelab-deploy-apps` (obsoleta) |
| Playbooks Ansible, provisionar VMs | homelab-ansible / agent-ansible | Inventario, tags, playbooks |
| Secretos SOPS, age | homelab-sops-secrets | Encriptación, respaldos de claves |
| Respaldos, cronjobs, verificación | homelab-backups / agent-backups | sanoid/syncoid/restic en Proxmox + CronJobs k8s |
| Pentest web sandbox, evidencias, DTPlus / intranet | security-web-pentest (stub) | Repo dedicado **`security-assessment`** junto a este monorepo; ver el `AGENTS.md` de ese repo |

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

## Skills disponibles

| Skill | Ubicación | Cuándo usar |
|-------|-----------|-------------|
| homelab-maintenance | .cursor/skills/homelab-maintenance/ | Mantenimiento, apagado, troubleshooting |
| homelab-deploy-apps | .cursor/skills/homelab-deploy-apps/ | Desplegar/modificar aplicaciones |
| homelab-ansible | .cursor/skills/homelab-ansible/ | Ansible, playbooks, inventario |
| homelab-sops-secrets | .cursor/skills/homelab-sops-secrets/ | Secretos SOPS |
| homelab-backups | .cursor/skills/homelab-backups/ | Respaldos, cronjobs |
| security-web-pentest | .cursor/skills/security-web-pentest/ | **Stub:** redirige al repo `security-assessment` |

## Referencias

- **README.md**: Documentación principal del homelab
- **docs/**: `ARQUITECTURA.md` (arquitectura objetivo y fases), `PENDIENTES.md` y `DISENO-APPS.md` (cómo diseñar y portar apps para el cluster; leer antes de crear cualquier app)
- **proxmox/**: configuración versionada del host
- **pibot/**: configuración versionada de la Pi master (`config.txt` sin overclock, k3s, cómo apagarla)
- **scripts/**: Scripts de verificación y utilidades
