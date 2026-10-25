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
   Imagen propia (GHCR privado): `$H ghcr secret <ns> cluster/apps/<app>/solo-flux/secret-ghcr-pull.sops.yml` +
   `imagePullSecrets: [{name: ghcr-pull}]`; antes del merge, `$H ghcr check ghcr.io/koshiro/<app>:<tag>`.
4. `kubectl kustomize cluster/apps/<app> >/dev/null`; `kubectl apply -k … --dry-run=server` solo si el namespace ya
   existe (no crearlo a mano: lo crea Flux).
5. Una Kustomization en `cluster/flux/apps.yaml` copiando una parecida (los `*.sops.*` en `solo-flux/` con
   `components` y `decryption`); `bash scripts/flux/flate.sh test`. Desde 2026-10-16 la app la crea Flux al mergear:
   nada de `kubectl apply -k` ni `sops -d | kubectl`. Después: `$F reconcile ks <app> --with-source` → `$H flux` →
   `$H wait <ns> <deploy>` → `$H app <ns>`.
6. Fila en `README.md` § Servicios, respaldo (receta *respaldo*), PR. `cluster/kustomization.yml` es la raíz de la
   época de `kubectl apply -k`: Flux no la usa, no hace falta tocarla.

## Sitio estático en pibot
1. Copiar `cluster/apps/noledigasanadie/` (o `josekast/` si necesita ConfigMap de nginx; SPA → ver `cluster/apps/cyano/`).
2. NodePort: `$H ports --serie 30890`. Carpeta: `$H ssh pibot sudo install -d -o daniel -g daniel /var/lib/homelab-<sitio>`.
3. CronJob en `cluster/00-infrastructure/backups/webs-estaticas-backup.yaml` + nombre en `proxmox/bin/check-backups.sh`
   (copiarlo a `/usr/local/sbin/` de pve después del merge, cuando Flux ya creó el CronJob).
4. Hostname: `$H cf route pibot-webs <host> http://192.168.1.15:<nodePort>` (dry-run) → `--apply`.
5. Publicar: `rsync -a --delete <dir>/ daniel@k3s-node-0:/var/lib/homelab-<sitio>/` (cyano: `~/git/cyano/scripts/publicar.sh`).
6. Verificar: `curl -sI https://<host> | head -1`.

## Hostname público para una app en workers
`*.danielriquelme.cl` con Ingress ya queda público por el comodín del túnel `pve`: no tocar Cloudflare. Otra zona →
`$H cf route pve <host> http://traefik.kube-system:80`. Panel admin → agregar el host a la app de Access «Homelab admin»
(`$H cf api GET 'accounts/{acc}/access/apps'`).

## Respaldo de un PVC local-path
Copiar un bloque de `cluster/00-infrastructure/backups/app-config-backup.yaml`, siguiente minuto libre 02:40–02:48,
`APP`, `EXCLUDES`, `claimName`; agregar a `check-backups.sh`. Al mergear, Flux crea el CronJob (ks `backups`;
`$F reconcile ks backups --with-source` para no esperar) → probar con `kubectl -n <ns> create job
--from=cronjob/config-backup-<app> backup-prueba` → recién entonces copiar `check-backups.sh` a pve (si llega antes,
avisa «nunca» cada mañana).

## Cambio temporal en vivo (escalar a 0, probar un parche antes del PR)
`F=~/.cache/flux-plan/bin/flux`. Sin esto, Flux revierte el cambio en ≤10 min (en comfyui, un `scale --replicas=0`
vuelve a 1 a mitad del Job). `$F suspend ks <ks>` → cambio con kubectl → PR → merge → `$F resume ks <ks>` (reaplica
git: réplicas, imagen, etc.) → `$H flux` (nada en «suspendidas»). Nunca dejar una ks suspendida al cerrar la tarea.
El clasificador puede bloquear `suspend`/`resume` («Shared Cluster Mutation») → dar el comando al usuario.

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
veces: la 1.ª sale con la raíz) → `$S estado` (ks, HelmRelease, 19 SOPS, pods fuera de la guarda y «Alert de Flux
activas: ninguna»: el ensayo suspende las Alert de flux-avisos, que llevan los tokens reales) → `$S borrar` →
`gh repo deploy-key delete <id>` y borrar la clave. Probar sin cluster: `bash scripts/flux/flate.sh test` (render de
todo como Flux, sin los suspend; `diff [ref]` para comparar), `$S render --rama <r>` y
`flux build ks <ks> --path <dir> --kustomization-file <ks.yaml> --dry-run`. (2026-10-16: 30/30 Ready en 142 s.)
`instalar --como-prod` deja las hijas suspendidas como en git: ensaya «Flux sin gestionar nada» (fase 3).

## Flux en prod (estado, deploy key, reinstalar)
`F=~/.cache/flux-plan/bin/flux`. **Estado:** `$H flux` (sale 1 si una Kustomization activa no está Ready en el SHA de
`main`; una pasada en curso sale como «reconciliando» y no cuenta) y `$F check`; errores, con `$F logs
--all-namespaces --level=error --since=15m`. **Tras un merge:** `$F reconcile ks <ks> --with-source` trae el commit y
aplica sin esperar el intervalo de 5 min (probado 2026-10-16). **Antes de un PR que adopte
objetos vivos** (app que ya corre, `suspend` quitado): `$F diff ks <ks> --path <dir> --kustomization-file
cluster/flux/<apps|capas>.yaml` + `python3 -I scripts/flux/simular_adopcion.py <ks>` (lo que `flux diff` no ve:
campos de `kubectl*` que Flux borra y Secrets SOPS); después del merge, `kubectl wait ks/<ks>
--for=jsonpath='{.status.lastAppliedRevision}'=main@sha1:<git rev-parse origin/main>` y `scripts/flux/linea_base.py
comparar --nombre <base>` (fase 4 de `docs/PLAN-FLUX.md`). **Deploy key nueva** (si se pierde o hay
que rotarla): `ssh-keygen -q -t ed25519 -N "" -C flux-system-prod -f ~/.cache/flux-plan/deploy-key-prod` →
`gh repo deploy-key add …pub -R koshiro/homelab-config --title "flux-system (prod, solo lectura)"` → script en
`$CLAUDE_JOB_DIR/tmp` que corre `$F create secret git flux-system --url=ssh://git@github.com/koshiro/homelab-config
--private-key-file=<clave>` (con `subprocess`, porque la guarda rechaza el comando directo) → borrar los dos archivos y
`gh repo deploy-key delete <id viejo>`. **Desde cero:** `kubectl apply --server-side -k cluster/flux/flux-system` (falla
el GitRepository, porque no están los CRD) → `kubectl wait --for=condition=established crd -l
app.kubernetes.io/part-of=flux` → secrets `flux-system` y `sops-age` → otra pasada. (2026-10-16: Ready en 7 s.)

## Probar los avisos de Flux (sin tocar main)
`kubectl apply` de un GitRepository suelto en `flux-system` con URL inexistente (`spec.interval: 10m`, `timeout: 20s`)
→ en segundos `kubectl -n flux-system logs deploy/notification-controller --since=3m | grep <nombre>` muestra
«dispatching event» y ningún `"level":"error"` (= Telegram lo aceptó) → a los ~15 min `$H alertas` da
`FluxSinReconciliar` en firing (vmalert → Alertmanager → Telegram) → `kubectl delete gitrepository <nombre> -n
flux-system`. No usar una Kustomization rota: el Alert `github` dejaría un check en rojo en el commit de main.
(2026-10-16)

## Falla real de Flux en prod (prueba con merge, fase 6)
App sin estado y `RollingUpdate` con 1 réplica (flaresolverr): tag inexistente → PR → **confirmación del usuario** →
merge → `$F reconcile ks <ks> --with-source` en background (espera el timeout y sale con «context deadline
exceeded») → vigilar con un script en `$CLAUDE_JOB_DIR/tmp` (Ready de la ks, pods, «dispatching event» del
notification-controller, `$H alertas`). Qué esperar: aviso a los 5 min y check `flux/<ks>` en rojo; tras
`progressDeadlineSeconds` (10 min) los «failed early due to stalled resources» quedan fuera por el `exclusionList`
(#110; antes, uno cada `retryInterval` de 2 min) y a los 15 min llega `FluxSinReconciliar`. Revert con `git revert -m 1 <merge>` en rama `fix/` → PR → merge → reconcile → `gh api
repos/koshiro/homelab-config/commits/<sha>/statuses`. El pod viejo sigue sirviendo. (2026-10-16)

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

## App lenta o con errores intermitentes (SQLITE_BUSY, readiness con timeout, iowait)
1. Agrupar los errores de la app por minuto (`kubectl logs --since=24h` → contar por `t=…[:16]`): si llegan en
   ráfagas de minutos, sospechar del disco antes que de la app.
2. `$H io --en <fin de la ráfaga en UTC> --ventana 6m` y comparar con un momento de calma. Disco con `esc_ms` alto y
   pocos MB/s = disco lento; iowait y `psi_io_full` altos en los tres workers a la vez = el problema está en pve.
3. Zvol → VM: `$H ssh pve "ls -l /dev/zvol/nvme/"` (`zdNN`); por VM: `pve_disk_read_bytes`/`pve_disk_written_bytes`.
4. Descartar la ranura: `lspci -vv` (`LnkSta` igual a `LnkCap`) y `journalctl -k | grep -i aer`; SMART con `smartctl -a`.
5. Así se encontró `nvme1n1` (2026-10-17, `proxmox/README.md` § Discos y pools).
6. Para saber por qué un SSD es lento (caché, TRIM, temperatura, APST): sacarlo de uso y correr
   `scripts/ssd/prueba.sh <by-id> --destruir` en el host con nohup (~60 min; uso en su cabecera) y `scripts/ssd/analiza.py`.
