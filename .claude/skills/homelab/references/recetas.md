# Recetas (leer solo la que corresponde)

`H="python3 -I ~/.claude/skills/homelab/hl.py"`. Toda tarea en homelab-config: rama `feat|fix|chore|docs/<x>` desde
`main` (worktree con `git worktree add .claude/worktrees/<x> -b feat/<x> main` + EnterWorktree `path`), Conventional
Commits en español, PR con `gh pr create`. Pedir confirmación antes de `kubectl apply`, tocar hosts o borrar.

## Cerrar tras un merge
ExitWorktree `keep` → en `~/git/homelab-config`: `git pull --ff-only` → `git worktree remove .claude/worktrees/<x>` →
`git branch -d <rama>`. Es parte del trabajo, no un pendiente para el usuario.

## App nueva o portada
1. `$H doc DISENO-APPS 3` (árbol de decisiones) y solo la plantilla §4.x que aplique.
2. Carpeta `cluster/apps/<app>/` copiando una app parecida (`$H app <similar>` muestra su carpeta).
3. Puerto: `$H ports --serie 30xxx`. Secreto: escribir en claro en `$CLAUDE_JOB_DIR/tmp`, `$H sops encrypt`, mover.
4. `kubectl kustomize cluster/apps/<app> >/dev/null` → `kubectl apply -k … --dry-run=server` (crear namespace antes).
5. `$H sops apply …` → `kubectl apply -k …` → `$H wait <ns> <deploy>` → `$H app <ns>`.
6. `cluster/kustomization.yml`, fila en `README.md` § Servicios, respaldo (receta *respaldo*), PR.

## Sitio estático en pibot
1. Copiar `cluster/apps/noledigasanadie/` (o `josekast/` si necesita ConfigMap de nginx; SPA → ver `cluster/apps/cyano/`).
2. NodePort: `$H ports --serie 30890`. Carpeta: `$H ssh pibot sudo install -d -o daniel -g daniel /var/lib/homelab-<sitio>`.
3. CronJob en `cluster/00-infrastructure/backups/webs-estaticas-backup.yaml` + nombre en `proxmox/bin/check-backups.sh`
   (y copiarlo a `/usr/local/sbin/` de pve).
4. Hostname: `$H cf route pibot-webs <host> http://192.168.1.15:<nodePort>` (dry-run) → `--apply`.
5. Publicar: `rsync -a --delete <dir>/ daniel@k3s-node-0:/var/lib/homelab-<sitio>/` (cyano: `~/git/cyano/scripts/publicar.sh`).
6. Verificar: `curl -sI https://<host> | head -1`.

## Hostname público para una app en workers
`*.danielriquelme.cl` con Ingress ya queda público por el comodín del túnel `pve`: no tocar Cloudflare. Otra zona →
`$H cf route pve <host> http://traefik.kube-system:80`. Panel admin → agregar el host a la app de Access «Homelab admin»
(`$H cf api GET 'accounts/{acc}/access/apps'`).

## Respaldo de un PVC local-path
Copiar un bloque de `cluster/00-infrastructure/backups/app-config-backup.yaml`, siguiente minuto libre 02:40–02:48,
`APP`, `EXCLUDES`, `claimName`; agregar a `check-backups.sh`; aplicar el CronJob en el mismo momento y probar con
`kubectl -n <ns> create job --from=cronjob/config-backup-<app> backup-prueba`.

## Reiniciar o redimensionar una VM del cluster
`$H status --deep` (RAM libre de pve) → `kubectl drain <nodo> --ignore-daemonsets --delete-emptydir-data` → (si tiene
el primario de Postgres, moverlo antes con patch de `status.targetPrimary`) → `$H ssh pve qm shutdown <vmid>` /
`qm start` (no reboot en el invitado) → `kubectl uncordon`. Pedir confirmación: es disruptivo.

## Salud tras corte de luz
`$H status --deep`; si faltan workers: `ansible-playbook -i ansible/inventory ansible/playbooks/maintenance/playbook_startup_cluster.yml`.
Apagar: siempre `playbook_graceful_shutdown_cluster.yml`, nunca `poweroff --force`.
