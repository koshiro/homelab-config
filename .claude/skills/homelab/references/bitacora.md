# Bitácora de uso (una línea por tarea; sirve para ver qué falta promover)

| Fecha | Tarea | Llamadas | Qué faltó | Qué se agregó |
|-------|-------|----------|-----------|---------------|
| 2026-10-14 | Baseline: 74 sesiones previas (homelab-config + cyano), 5731 llamadas | — | 433 errores: guarda del worktree 128, clasificador 46, SOPS sin clave ~20, sleep bloqueado 20, ssh a nombres que no resuelven/LAN ausente 10; orientación leyendo README (34 sesiones), PENDIENTES (19), proxmox/README (13), DISENO-APPS (12) | Skill `homelab`: `hl.py` (status, app, ports, wait, sops, ssh, doc, cf), hechos con trampas, recetas |
| 2026-10-15 | Pendientes, merge PR #62, kernel 7.0.14-24 + reinicio de pve, CronJob arr-filtro | ~45 | Receta de reinicio de pve; `homelab-storage` no se importó (unidad sin escapar); llamadas compuestas bloqueadas por el clasificador y `sleep` | Receta *reiniciar el host pve*, 3 trampas |
| 2026-10-15 | ComfyUI: assets perdidos tras reinicio | ~35 | hl.py app falló por el clasificador; UI tras Access | `--enable-assets`, fechas corregidas en la BD, trampas en hechos |
| 2026-10-15 | ComfyUI: «Insert as node» de Media Assets insertaba otra imagen o nodo vacío | ~40 | No había forma rápida de leer el frontend instalado | Skill `comfyui` con `comfy.py` (src/show/api/assets/logs) y shim `homelab_asset_subfolder` |
| 2026-10-15 | Plan de Flux (docs/PLAN-FLUX.md), versión con inventario inverso | ~60 | Ver qué vive en el cluster sin archivo en el repo; kubectl diff -f falla con *.sops; 2 SOPS binarios no se notaban | scripts/flux/inventario.py y sops_formato.py; pasan a hl.py inventario en la fase 8 |
| 2026-10-15 | Fase 0 de Flux: k3s 1.33.4 → 1.34.12 → 1.35.9 y kit de recuperación | ~130 | El clasificador bloqueó el primer drain; no había subida a R2 sin claves S3 | scripts/k3s-binario.sh y kit-recuperacion.sh, hl.py r2, receta Subir k3s, trampas de drain/etcd/503 |
