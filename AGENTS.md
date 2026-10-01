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
| Snapshots, NFS, cronjobs en TrueNAS | homelab-truenas-api / agent-truenas | API REST TrueNAS v2.0 |
| Nueva aplicación, Ingress, PVC | homelab-deploy-apps / agent-deploy | Patrones de despliegue (kubectl apply -k; Flux pendiente) |
| Playbooks Ansible, provisionar VMs | homelab-ansible / agent-ansible | Inventario, tags, playbooks |
| Secretos SOPS, age | homelab-sops-secrets | Encriptación, respaldos de claves |
| Respaldos, cronjobs, verificación | homelab-backups / agent-backups | Sistema de respaldos en TrueNAS |
| Pentest web sandbox, evidencias, DTPlus / intranet | security-web-pentest (stub) | Repo dedicado **`security-assessment`** junto a este monorepo; ver `docs/security-assessment-repo.md` y el `AGENTS.md` de ese repo |

## Arquitectura actual (resumen)

- **Cluster**: k3s en pibot (master) + 3 workers
- **Storage**: TrueNAS 192.168.1.20, pool homelab-storage
- **Dominio**: danielriquelme.cl
- **GitOps**: manifiestos en `cluster/` aplicados con kubectl; FluxCD planificado (ver docs/PENDIENTES.md)
- **Acceso remoto**: Tailscale (`ssh daniel@k3s-node-0`, MagicDNS del master pibot; kubectl local funciona)

## Skills disponibles

| Skill | Ubicación | Cuándo usar |
|-------|-----------|-------------|
| homelab-maintenance | .cursor/skills/homelab-maintenance/ | Mantenimiento, apagado, troubleshooting |
| homelab-truenas-api | .cursor/skills/homelab-truenas-api/ | Operaciones TrueNAS vía API |
| homelab-deploy-apps | .cursor/skills/homelab-deploy-apps/ | Desplegar/modificar aplicaciones |
| homelab-ansible | .cursor/skills/homelab-ansible/ | Ansible, playbooks, inventario |
| homelab-sops-secrets | .cursor/skills/homelab-sops-secrets/ | Secretos SOPS |
| homelab-backups | .cursor/skills/homelab-backups/ | Respaldos, cronjobs |
| security-web-pentest | .cursor/skills/security-web-pentest/ | **Stub:** redirige al repo `security-assessment` (ver `docs/security-assessment-repo.md`) |

## Referencias

- **README.md**: Documentación principal del homelab
- **docs/**: Guías adicionales (backup, SOPS, etc.)
- **scripts/**: Scripts de verificación y utilidades
