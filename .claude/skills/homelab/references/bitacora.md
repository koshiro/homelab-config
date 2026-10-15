# Bitácora de uso (una línea por tarea; sirve para ver qué falta promover)

| Fecha | Tarea | Llamadas | Qué faltó | Qué se agregó |
|-------|-------|----------|-----------|---------------|
| 2026-10-14 | Baseline: 74 sesiones previas (homelab-config + cyano), 5731 llamadas | — | 433 errores: guarda del worktree 128, clasificador 46, SOPS sin clave ~20, sleep bloqueado 20, ssh a nombres que no resuelven/LAN ausente 10; orientación leyendo README (34 sesiones), PENDIENTES (19), proxmox/README (13), DISENO-APPS (12) | Skill `homelab`: `hl.py` (status, app, ports, wait, sops, ssh, doc, cf), hechos con trampas, recetas |
| 2026-10-15 | Pendientes, merge PR #62, kernel 7.0.14-24 + reinicio de pve, CronJob arr-filtro | ~45 | Receta de reinicio de pve; `homelab-storage` no se importó (unidad sin escapar); llamadas compuestas bloqueadas por el clasificador y `sleep` | Receta *reiniciar el host pve*, 3 trampas |
