---
name: homelab
description: Use when a task touches the homelab of Daniel (k3s cluster, pibot, Proxmox pve, ZFS/NFS, Ansible, SOPS, Cloudflare tunnels/DNS/Access, backups, static sites on pibot, deploying or publishing any app such as cyano or josekast), from homelab-config or from any other repo, before reading docs, listing pods or running kubectl/ssh to get oriented. Suite arr/qBittorrent/Plex go to media-stack.
---

# Homelab

Objetivo: **mínimo de tokens, documentos y llamadas fallidas**. No leer `README.md`, `AGENTS.md` ni `docs/` completos
ni listar pods para ubicarse: el mapa está aquí, los datos estables en `references/hechos.md`, los procedimientos en
`references/recetas.md`, y `hl.py doc` trae una sola sección cuando hace falta un documento.

```bash
H="python3 -I ~/.claude/skills/homelab/hl.py"   # desde cualquier repo; en un worktree de homelab-config: .claude/skills/homelab/hl.py
$H status [--deep]            # nodos (disco libre, cordon, presión) + pods con problema; --deep: pibot throttled, RAM y zpools de pve
$H app <ns>                   # pods (nodo, imagen, reinicios), svc/NodePort, ingress, pvc, cronjobs, carpeta del repo
$H ports [--serie 30890]      # NodePorts en uso (vivo) o siguiente libre de una serie
$H wait <ns> <deploy> [--kind sts] [--timeout 5m]   # en vez de sleep; si falla imprime pods y logs
$H flux                       # fuente vs SHA de main, ks activas (Ready, revisión), suspendidas, HelmReleases, nodo de los pods
$F reconcile ks <ks> --with-source                  # F=~/.cache/flux-plan/bin/flux; tras un merge, sin esperar los 5 min
$H alertas                    # alertas activas de vmalert (pending/firing), horas en UTC
$H sops keys|encrypt <archivo>                      # con SOPS_AGE_KEY_FILE puesto; keys = solo nombres; aplicar = merge
$H ssh <pibot|pve|node-1..3> <comando>              # LAN y, si no responde, tailnet
$H doc <archivo> [sección]    # índice de encabezados o una sección: doc DISENO-APPS 4.2
$H cf zones|tunnels|routes <túnel>|route <túnel> <host> <servicio> [--apply]|api <M> <ruta> [-d JSON|@f]
$H r2 ls [bucket]|mb <bucket>|put <bucket> <archivo> [clave]|get <bucket> <clave> <destino>   # mb/put: --apply
```

## Mapa (una tarea → dónde mirar)

| Tarea | Primero |
|-------|---------|
| Salud, "algo anda lento", tras corte de luz | `$H status --deep` |
| App nueva o portar | receta *app nueva* + `$H doc DISENO-APPS 2` (contrato) y la plantilla §4.x que toque |
| Sitio estático / publicar web | receta *sitio estático* (túnel `pibot-webs` → `http://192.168.1.15:<nodePort>`) |
| Cloudflare (hostname, DNS, túnel, reglas) | `$H cf …` (autorizado; lo hace el agente, nunca el usuario) |
| Respaldos | receta *respaldo*; `$H doc proxmox/README Tareas` |
| Flux / GitOps (estado, deploy key, fases del plan, ensayo, avisos) | `$H flux`; recetas *Flux en prod*, *probar los avisos de Flux* y *ensayo de Flux en k3d*; `$H doc PLAN-FLUX Estado` (primera fase sin marcar) |
| Cambio temporal en vivo (escalar a 0, probar un parche) | receta *cambio temporal en vivo* (`flux suspend` → … → `flux resume`) |
| VM, RAM, ZFS, NFS del host | `$H doc proxmox/README <tema>` |
| Reiniciar pve (kernel, módulos) | receta *reiniciar el host pve* (verificar los 4 pools al volver) |
| Apagar/encender cluster | `$H doc README Operación` (siempre playbook ordenado) |
| Sonarr/Radarr/qBittorrent/Plex/Seerr | skill **media-stack** |
| ComfyUI | skill **comfyui** |

## Reglas que evitan los errores repetidos

Los errores más caros entre sesiones fueron rechazos de la guarda del worktree y del clasificador. Forma segura:

- **Un comando simple por llamada.** Nada de `cd X &&`, `git -C`, `for`/`until` con variables, `$VAR` como argumento,
  heredocs que mencionen git, ni rutas `/Users/daniel/git/...` dentro de construcciones complejas (la guarda las lee
  como git). Lógica con bucles → script en `$CLAUDE_JOB_DIR/tmp/x.py` y `python3 -I <ruta absoluta>`.
- **Nunca `sleep`**: `$H wait`, `kubectl wait`, o Monitor con condición.
- **Flux aplica todo `cluster/` al mergear a `main`** (desde 2026-10-16). `kubectl apply/edit/patch/scale/label` sobre
  algo gestionado se revierte en ≤10 min; `rollout restart` solo con `--field-manager=reinicio-manual`. Para un cambio
  que deba durar sin PR: receta *cambio temporal en vivo*.
- Si el clasificador bloquea: detenerse, dar el comando exacto y por qué, y esperar (regla global del usuario).
- Más trampas con su arreglo: `references/hechos.md` § Trampas.

## Ciclo de aprendizaje (obligatorio antes de dar la tarea por terminada)

1. **¿Repetiste una secuencia de 3+ llamadas, un script ad hoc o un `jq` que se usaría otra vez?** → subcomando en
   `hl.py` (una línea por ítem, dry-run salvo `--apply`, ayuda en el parser, línea en el bloque de arriba). Específico
   de un dominio grande → skill propia como media-stack. De una sola vez → nada.
2. **¿Un comando falló y encontraste la forma correcta?** → línea en `hechos.md` § Trampas: `error → forma correcta`.
3. **¿Descubriste un dato estable** (IP, ID, puerto, ruta, decisión del usuario)? → `hechos.md` con fecha; borrar lo
   que resultó falso. Datos que cambian (pods, puertos libres) no se anotan: se calculan con `hl.py`.
4. **¿Tipo de tarea nuevo o receta que falló?** → `recetas.md`.
5. Una línea en `references/bitacora.md`: fecha | tarea | llamadas | qué faltó | qué se agregó.
6. Probar lo nuevo (dry-run) y versionarlo en el PR de la tarea, o en `chore(skill-homelab): …`. Mantener este archivo
   bajo ~90 líneas: el detalle va a `references/`.
