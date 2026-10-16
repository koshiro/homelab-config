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

## Subir k3s (de a un menor)
Destino: `curl -s https://update.k3s.io/v1-release/channels` (canal `v1.NN`); leer `docs.k3s.io/release-notes/v1.NN.X`
(Traefik, etcd, flags) y pedir autorización de drain (trampa). Snapshot en pibot
`sudo k3s etcd-snapshot save --name pre-k3s-1.NN` → `ansible k3s_nodes -i ansible/inventory -b -m script -a
'scripts/k3s-binario.sh <ver> descargar'` (los 4 a la vez, sha256 verificado) → igual con `pibot … instalar` →
`kubectl -n kube-system rollout status deploy/coredns deploy/traefik deploy/metrics-server` → workers de a uno,
dejando al final el del primario de Postgres: `kubectl drain <n> --ignore-daemonsets --delete-emptydir-data` →
`ansible <n> … instalar` → `kubectl wait --for=condition=Ready node/<n>` → `kubectl uncordon <n>` → esperar la réplica
CNPG de ese nodo Ready. Antes del último: `kubectl -n postgresql patch cluster homelab-postgres --type merge
--subresource status -p '{"status":{"targetPrimary":"<instancia en nodo ya subido>"}}'` y esperar
`currentPrimary` y la ex-primaria Ready. En node-1: `nvidia-smi` dentro de comfyui. Al final: `hl.py status`, sondear
los Ingress y actualizar `k3s_version` del playbook, el tope de `registry.k8s.io/kubectl` en renovate.json y
`KUBECTL_VER` de claude-remote (y `IMAGEN` de `scripts/flux/ensayo_k3d.py`). (2026-10-15: 1.33.4 → 1.34.12 → 1.35.9
en ~1 h, sin cortes salvo los pods drenados.)

## Ensayo de Flux en k3d (cluster desechable)
`S="python3 -I scripts/flux/ensayo_k3d.py"`. Si `docker version` no conecta: `orb start` (OrbStack). Push de la rama
primero (Flux la lee de GitHub). `$S crear` (k3s de prod + guarda que rechaza pods de apps, comprobada) →
`ssh-keygen -q -t ed25519 -N "" -f ~/.cache/flux-plan/ensayo/deploy-key` → `gh repo deploy-key add …pub --title
"flux-ensayo-k3d (temporal)"` → `$S instalar --rama <rama> --clave-git ~/.cache/flux-plan/ensayo/deploy-key` →
`kubectl --kubeconfig ~/.cache/flux-plan/ensayo/kubeconfig wait ks --all -n flux-system --for=condition=Ready` (dos
veces: la 1.ª sale con la raíz) → `$S estado` (ks, HelmRelease, 17 SOPS, pods fuera de la guarda) → `$S borrar` →
`gh repo deploy-key delete <id>` y borrar la clave. Probar sin cluster: `bash scripts/flux/flate.sh test` (render de
todo como Flux, sin los suspend; `diff [ref]` para comparar), `$S render --rama <r>` y
`flux build ks <ks> --path <dir> --kustomization-file <ks.yaml> --dry-run`. (2026-10-16: 29/29 Ready en 134 s.)
`instalar --como-prod` deja las hijas suspendidas como en git: ensaya «Flux sin gestionar nada» (fase 3).

## Flux en prod (estado, deploy key, reinstalar)
`F=~/.cache/flux-plan/bin/flux`. **Estado:** `$H flux` (sale 1 si una Kustomization activa no está Ready en el SHA de
`main`) y `$F check`; errores, con `$F logs --all-namespaces --level=error --since=15m`. **Deploy key nueva** (si se pierde o hay
que rotarla): `ssh-keygen -q -t ed25519 -N "" -C flux-system-prod -f ~/.cache/flux-plan/deploy-key-prod` →
`gh repo deploy-key add …pub -R koshiro/homelab-config --title "flux-system (prod, solo lectura)"` → script en
`$CLAUDE_JOB_DIR/tmp` que corre `$F create secret git flux-system --url=ssh://git@github.com/koshiro/homelab-config
--private-key-file=<clave>` (con `subprocess`, porque la guarda rechaza el comando directo) → borrar los dos archivos y
`gh repo deploy-key delete <id viejo>`. **Desde cero:** `kubectl apply --server-side -k cluster/flux/flux-system` (falla
el GitRepository, porque no están los CRD) → `kubectl wait --for=condition=established crd -l
app.kubernetes.io/part-of=flux` → secrets `flux-system` y `sops-age` → otra pasada. (2026-10-16: Ready en 7 s.)

## Reiniciar el host pve (kernel, módulos)
Revisar que no corran respaldos (`systemctl list-units 'syncoid*' 'restic*'`) y que las VMs/LXC tengan `onboot: 1` →
snapshot de etcd en pibot (`sudo k3s etcd-snapshot save --name pre-reboot-pve-<fecha>`) → `nohup systemctl reboot &`
(pve-guests apaga los invitados por ACPI; sin drain si el usuario lo acepta). Esperar SSH con Monitor/`until`; tarda
~20 min en responder. Después: `zpool list` debe mostrar los **4 pools** (`nvme` raíz, `respaldo`, `homelab-storage`
y `scratch`), `pct status 110` running y `exportfs | grep homelab-storage`. Si faltó un pool: `zpool import -d
/dev/disk/by-id <pool>`, `exportfs -ra`, `pct start 110` y borrar los pods `Unknown`/`UnexpectedAdmissionError`
(`kubectl delete pod --force --grace-period=0`); los que esperan NFS se recuperan solos al reintentar el montaje.

## Salud tras corte de luz
`$H status --deep`; si faltan workers: `ansible-playbook -i ansible/inventory ansible/playbooks/maintenance/playbook_startup_cluster.yml`.
Apagar: siempre `playbook_graceful_shutdown_cluster.yml`, nunca `poweroff --force`.
