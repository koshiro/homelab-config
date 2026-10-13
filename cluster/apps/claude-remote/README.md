# claude-remote

Claude Code siempre encendido en modo **Remote Control**: desde claude.ai/code o la app móvil aparecen tres entornos,
`homelab-config`, `SAC` y `cyano`. Cada sesión nueva abre su propio worktree (`--spawn worktree`, modo `auto`).

## Qué se sincroniza con el Mac

| Qué | Cómo |
|---|---|
| `~/.claude/{CLAUDE.md,settings.json,hooks/,skills/}` y `~/.claude/projects/*/memory/` | Syncthing en ambos sentidos (lista blanca en `files/stignore`, copia en el `~/.claude/.stignore` del Mac) |
| Skills de la cuenta (`skills/synced/`) | Llegan solas con el login |
| Repos y sus skills (`.claude/skills/`) | git: clone de `github.com/koshiro/*` en `~/git/<repo>`; pull automático cada hora si están limpios en `main` |

El pod usa `HOME=/Users/daniel` para que los directorios de memoria se llamen igual en los dos lados. Credenciales
(`~/.claude/.credentials.json`), sesiones y caché nunca se sincronizan.

El Mac corre Syncthing con `brew services start syncthing` (dispositivo `claude-remote`, carpeta `claude-home`) y se
conecta al NodePort 30894. Si los dos lados editan el mismo archivo a la vez, queda un `*.sync-conflict-*` y el
log del contenedor `claude` lo avisa cada hora.

## Acceso que tiene el pod (paridad con el Mac)

kubectl como `cluster-admin` (ServiceAccount, `rbac.yml`), clave age de SOPS, contraseña del vault de Ansible, token
de `gh` y una llave SSH propia (`claude-remote@k3s`) autorizada en los cuatro nodos (`daniel`) y en `pve` (`root`).
Revocar: borrar el ClusterRoleBinding, quitar la llave de los `authorized_keys` y revocar el token en GitHub.

## Operación

```bash
# Desplegar
sops -d cluster/apps/claude-remote/secret.sops.yml | kubectl apply -f -
kubectl apply -k cluster/apps/claude-remote

# Primer login (una vez; el token queda en el NFS)
kubectl -n claude-remote exec -it deploy/claude-remote -c claude -- bash -lc 'claude auth login'

# Ver las ventanas de Remote Control (Ctrl-b d para salir). La primera vez cada repo pregunta
# "Trust …? [y/N]" y "Enable Remote Control? (y/n)": responder y en cada ventana (queda guardado en ~/.claude.json)
kubectl -n claude-remote exec -it deploy/claude-remote -c claude -- tmux attach -t rc

# Logs del arranque, conflictos de Syncthing
kubectl -n claude-remote logs deploy/claude-remote -c claude

# GUI de Syncthing del pod
kubectl -n claude-remote port-forward deploy/claude-remote 8384   # http://127.0.0.1:8384
```

Datos: dataset `nvme/k8s/claude-remote` (sanoid + syncoid). Las herramientas viven en `~/.local` del NFS con versión
fijada en `files/bootstrap.sh`; para actualizar una, cambiar la versión allí y reiniciar el pod.
