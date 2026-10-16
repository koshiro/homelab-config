# Plan: GitOps con Flux

Estado: propuesta (2026-10-15, revisada con el inventario del cluster vivo). Reemplaza la lista corta de
`PENDIENTES.md` §6.

**Objetivo:** que un merge a `main` sea el despliegue, y que eso lo pueda comprobar una máquina, no una persona:
cada Kustomization con `lastAppliedRevision` igual al SHA de `main`, el estado del commit en verde en GitHub y un
cluster desechable que se reconstruye solo desde git.

**Regla de este plan:** los dos intentos anteriores murieron sin terminar. Por eso cada fase dura una sesión
(≤ 2,5 h) y al cerrarla el homelab queda **igual o mejor que antes**, aunque la siguiente fase tarde meses. Ninguna
fase deja `kubectl apply -k` roto ni un estado a medias.

## Estado (marcar al cerrar cada fase; retomar desde la primera sin marcar)

- [x] Fase 0 — k3s 1.35 y kit de recuperación (2026-10-16)
- [x] Fase 1 — Repo = cluster en ambas direcciones (2026-10-16)
- [x] Fase 2 — Ensayo en k3d (2026-10-16)
- [x] Fase 3 — Flux instalado sin gestionar nada (2026-10-16)
- [ ] Fase 4 — Adopción (lote 1: webs y monitoreo · lote 2: media y apps · lote 3: infra y postgres)
- [ ] Fase 5 — Avisos
- [ ] Fase 6 — Prueba de fallas
- [ ] Fase 7 — Prune y automerge
- [ ] Fase 8 — Documentación y skill

## 0. Evidencia (2026-10-15)

Fuentes: los objetos vivos con sus `managedFields` (`scripts/flux/inventario.py`), los archivos SOPS
(`scripts/flux/sops_formato.py`), `/var/lib/rancher/k3s/server/manifests` en pibot, el historial de git y las notas de
versión de Flux.

| Hallazgo | Consecuencia |
|----------|--------------|
| Repo → cluster: `kubectl diff -k` da 0 cambios en todas las carpetas | Flux puede adoptar sin recrear nada |
| Cluster → repo: **22 objetos huérfanos** sin referencias (ConfigMaps con hash viejo: 9 en minecraft, 7 en monitoring y 1 en claude-remote; `plex/plex-proxy-config`, `plex/plex-headers` (el Ingress usa la de kube-system), `comfyui/ghcr-io-koshiro`, `immich/homelab-postgres-superuser`, `default/storage-expansion-script`) | Flux nunca los va a podar porque no están en su inventario: hay que borrarlos a mano antes |
| **Vivos, en uso y sin versionar:** 9 NetworkPolicy (`allow-arr-suite-communication` en 6 ns de media, `allow-all-egress` en 3), el Redis de Immich (StatefulSet y 8 objetos más del chart Bitnami `redis-20.13.2`, imagen `bitnami/redis:7.4.3`), los Namespaces `nvidia-device-plugin`, `postgresql` y `cnpg-system` | Si se reconstruye desde git, desaparecen: Immich queda sin Redis y la suite *arr sin sus políticas |
| El operador CNPG es el release de Helm `cnpg` (chart `cloudnative-pg-0.26.0`, app 1.27.0), no un manifiesto | Para versionarlo hay que adoptar ese release; un manifiesto upstream crea un segundo operador con otro nombre |
| **2 de 17 secretos SOPS están en formato binario** (`06-external/cloudflared/secret.sops.yml` y `04-media-stack/qbittorrent/secret-credentials.sops.yml`); no hay `.sops.yaml` en la raíz | Flux no puede descifrarlos como manifiestos; sin reglas comunes, el formato vuelve a desviarse |
| k3s **v1.33.4** (fuera de soporte upstream desde 2026-06-28). Flux 2.9.x pide ≥ 1.34.1; Flux 2.8.x soporta 1.33–1.35 | Instalar Flux 2.9 hoy no es posible; instalar 2.8 es montarse sobre dos versiones al final de su vida |
| Quién escribe en los objetos del repo: `kubectl-client-side-apply` (266), `kubectl` server-side (63: cert-manager y barman), `kubectl-patch` (CronJob `arr-filtro-archivos`, Deployment `plex`), `kubectl-label` (7 Namespaces), `kubectl-rollout` (19). Ningún otro controlador escribe en el `spec` | No hay operadores que peleen con Flux; los parches y etiquetas a mano son los que Flux va a revertir o heredar |
| En `server/manifests` de pibot solo están los manifiestos que trae k3s | No hay un segundo mecanismo de despliegue que compita con Flux |
| Las dos raíces de confianza solo existen en este Mac: la clave age (`~/.config/sops/age/keys.txt` y `.age-key`, en el mismo disco) y la contraseña del vault de Ansible (`~/.config/homelab/ansible-vault-pass`, que a su vez guarda el token de Cloudflare y `vault_restic_r2_password`). `docs/security/02` todavía ubica la clave en el ns `argocd` | Si se pierde el Mac, no se puede descifrar ningún secreto del repo ni leer el respaldo offsite de restic en R2 |
| **Es el tercer intento:** Flux en «modo observación» (2025-08-10) → ArgoCD (2025-08-18) → retirado el 2025-09-06. Motivo (según el usuario): no se pudo terminar la implementación | Fases cortas, cada una con un punto de parada seguro y su avance marcado en este archivo |
| 107 commits en `cluster/` entre el 1 y el 15 de octubre, todos aplicados a mano | Hay mucho que ganar: cada uno es una oportunidad de que el cluster quede detrás de `main` |
| La ServiceAccount de `claude-remote` es cluster-admin | Va a poder leer `sops-age` y, con eso, descifrar todo el historial de git, no solo los secretos vivos. Es un riesgo aceptado, pero hay que tenerlo presente |

## 1. Decisiones

| Tema | Decisión | Por qué |
|------|----------|---------|
| Kit de recuperación | Clave age + contraseña del vault. Copia A: dos notas seguras en Contraseñas de Apple (llavero de iCloud, siempre cifrado de extremo a extremo). Copia B: un archivo cifrado con `age -p` y una frase que recuerdes (anotada también en papel), en un bucket de R2 separado del repo de restic. **Gmail no** | El llavero no depende de tener activada la Protección Avanzada de Datos. R2 queda fuera del ecosistema de Apple y se accede con el login de Cloudflare. Un correo con la clave queda en texto claro, se puede buscar y es la cuenta más atacada por phishing |
| Versión | Primero subir k3s 1.33 → 1.34 → 1.35, de a un menor; después Flux 2.9.x | 1.33 ya está fuera de soporte, y Flux 2.8 pasa a ser la versión más vieja con el próximo menor |
| Bootstrap | `flux install --export` versionado por PR, más una deploy key de solo lectura | `flux bootstrap github` hace push directo a `main` y pide un PAT con admin |
| Componentes | `source`, `kustomize`, `notification` y `helm` | `helm` solo para adoptar el release `cnpg` sin cortar el operador; Renovate entiende los `HelmRelease`. Nada de image automation |
| Dónde corre | Afinidad a node-2/3 | node-1 está al 75 % de RAM y pibot debe quedar libre |
| Estructura | `cluster/flux/` con `flux-system/`, `capas.yaml` y `apps.yaml` (una Kustomization por app) | Si una app falla, no bloquea a las demás |
| Salud | `wait: true` en todas y `timeout` de 5 min (10 en comfyui) | Que el verde signifique «el rollout terminó», no solo «se aplicó» |
| Borrado | `prune: false` en la adopción; **`deletionPolicy: Orphan`** en las Kustomizations con estado; `kustomize.toolkit.fluxcd.io/prune: disabled` en PV, PVC, Namespaces con datos y el `Cluster` CNPG | Con el valor por defecto (`MirrorPrune`), renombrar o borrar una Kustomization con prune activo borra todo lo que contiene |
| SOPS | `.sops.yaml` en la raíz (`encrypted_regex: ^(data\|stringData)$`, el destinatario age actual); los 17 archivos dentro de sus Kustomizations de Flux, con el Component `solo-flux/` (fase 2) | Un solo formato para todos, y es el que Flux descifra |
| CI | `flate` (`test` + `diff` comentado en el PR, con `scripts/flux/flate.sh`), `kubeconform -strict` con los schemas de los CRD y una revisión de que todo `*.sops.*` esté estructurado y cifrado | `flate` renderiza igual que Flux; sin checks, Renovate no hace automerge. Reemplaza a `flux-local`, que quedó deprecado (decisión del usuario, 2026-10-16) |
| Actualizar Flux | El manager `flux` de Renovate para `gotk-components.yaml`; si la app de Mend no trae el CLI `flux` (la documentación no lo confirma), un workflow mensual que corre `flux install --export` y abre el PR | Que Flux no quede viejo en silencio |

## 2. Fases

Cada fase termina con un **«Listo cuando»** que comprueba una máquina. No se pasa a la siguiente si no se cumple.

### Fase 0 — Prerrequisitos (~2,5 h) · `chore/k3s-1.35`

1. Subir k3s a 1.34 y después a 1.35: primero pibot y luego cada worker con drain. Antes, una copia de etcd con
   `k3s etcd-snapshot save --name pre-k3s-1.34`.
2. Subir a `<1.36` el límite de `registry.k8s.io/kubectl` en `renovate.json`.
3. Kit de recuperación: tú pegas las dos notas en Contraseñas (2 min) y el agente sube a R2 el archivo cifrado con `age -p`.
   Corregir `docs/security/02` y documentar la restauración en `README.md` § Operación.

**Listo cuando:** `kubectl get nodes` muestra los 4 nodos en v1.35.x, `hl.py status` da 0 pods con problema y, en
una carpeta vacía y **con cada copia por separado**, `sops -d` descifra un secreto del repo y `ansible-vault view`
abre el vault.

**Cerrada (2026-10-16):** k3s v1.35.9+k3s1 en los 4 nodos (etcd 3.6.14, containerd 2.2.7, Traefik 3.7.13), 0 pods con
problema, snapshots `pre-k3s-1.34` y `pre-k3s-1.35` en pibot; kubectl v1.35.9 en el CronJob de minecraft y en
claude-remote. Kit: copia A (Contraseñas) y copia B (`r2://homelab-recuperacion/homelab-kit.age`) pasaron cada una
`sops -d` y `ansible-vault view` en carpeta vacía (`scripts/kit-recuperacion.sh verificar-notas|verificar-archivo`).

### Fase 1 — Repo = cluster en ambas direcciones (~2 h) · `chore/flux-preparar-repo`

1. Agregar `.sops.yaml` y volver a cifrar los 2 secretos binarios (se siguen aplicando aparte, como hoy).
2. Versionar lo que está vivo sin archivo: las 9 NetworkPolicy (exportadas y limpiadas), los 3 Namespaces, la
   kustomization de Immich con su Redis tal como está (cambiar Bitnami por Valkey va en otro PR, después) y el
   `HelmRelease` de `cnpg` con los valores de `helm get values cnpg -n cnpg-system`.
3. Exportar los 22 huérfanos a `~/.cache/flux-plan/huerfanos.yaml`, volver a confirmar que nadie los referencia y borrarlos.
4. Agregar las anotaciones de prune y el workflow de CI.

No cambia cómo se despliega: `kubectl apply -k` sigue funcionando y se puede parar aquí sin perder nada.

**Listo cuando:** `inventario.py` no muestra objetos sin archivo (solo los releases de Traefik y `cnpg`),
`kubectl diff -k` da 0 cambios en cada carpeta, `sops_formato.py` no muestra ningún `BINARIO` y el CI pasa en el PR.

**Revisión antes de empezar (2026-10-16, tras la fase 0).** Se mantiene lo de arriba, con estos ajustes:

- **Drift nuevo en 2 carpetas** (`scripts/flux/diff_todo.py`): `plex/allow-plex-egress` y `minecraft/minecraft-policy`
  solo suben `generation`. La causa es `- to: []` (`plex/networkpolicy-egress.yml:33`) y `- from: []`
  (`minecraft/networkpolicy.yml:15`): desde k3s 1.35 el dry-run cuenta la lista vacía como un cambio. Hay que borrar
  la clave, que significa lo mismo (todos los pares).
- **Huérfanos: 23, no 22.** La fase 0 dejó un segundo ConfigMap viejo en claude-remote (`claude-remote-files-*`:
  hoy son 2, y ninguno es el vigente).
- **Redis de Immich: la imagen ya no existe.** `docker.io/bitnami/redis:7.4.3-debian-12-r0` da 404 en Docker Hub; el
  pod corre de la caché de node-3 (`IfNotPresent`), así que si lo mueven a otro nodo queda en `ImagePullBackOff`. Al
  versionarlo, usar `docker.io/bitnamilegacy/redis:7.4.3-debian-12-r0@sha256:a25b5d07a14ec13730022c7cd9bab6308d55ccd86b74af7315553c17be884889`
  (el mismo digest que corre hoy). El cambio de imagen reinicia el pod una vez. No hay secret de release de Helm: son
  objetos sueltos con etiquetas de Helm.
- **`cnpg`: los valores de usuario están vacíos** (`scripts/flux/helm_valores.py`): el `HelmRelease` lleva solo el chart
  `cloudnative-pg` 0.26.0. El CRD `HelmRelease` no existe hasta la fase 3, así que su archivo no puede entrar en una
  kustomization que se aplique con `kubectl apply -k`: va en `cluster/flux/` sin referenciar.
- **`inventario.py` además lista** `cert-manager/cert-manager-webhook-ca` (lo crea el webhook) y
  `postgresql/cnpg-default-monitoring` (lo crea el operador). Son de controladores: hay que excluirlos en el script, no
  borrarlos. `cloudflared/cloudflared-token` deja de salir cuando su SOPS quede estructurado.
- **No hay `.github/`.** `kubeconform` y la revisión de SOPS se pueden armar ahora; `flux-local` necesita las
  Kustomizations de Flux, así que su job entra en la fase 3.

**Avance (2026-10-16, PR #91, rama `chore/flux-preparar-repo`).**

- SOPS: `.sops.yaml` y los 2 binarios recifrados; `sops_formato.py` sin `BINARIO`. `qbittorrent-credentials` nunca se
  aplicó (su texto plano era YAML inválido) y nadie lo usa: queda como resguardo de la contraseña.
- Versionado y en sus kustomizations: las 9 NetworkPolicy, los 3 Namespaces, Immich (kustomization nueva, Redis con
  `bitnamilegacy`, aplicado) y el `HelmRelease` de `cnpg` en `cluster/00-infrastructure/cnpg/`, comentado en su
  kustomization hasta la fase 3.
- **No estaba en el inventario:** `inventario.py` contaba como «del repo» los YAML sueltos. 25 archivos vivos no
  entraban en ninguna kustomization (NetworkPolicy de bazarr/radarr/sonarr/overseerr, ConfigMaps de init, el PV de
  Plex): ahora entran. 4 NetworkPolicy que nunca se aplicaron (qbittorrent y radarr) y 1 duplicado se borraron; el
  script ahora solo cuenta kustomizations y SOPS. Quedan fuera a propósito los Jobs manuales de comfyui (05–07) y
  `minecraft/seedfinder`.
- Anotación de prune por el Component `cluster/components/proteger-datos` (PV, PVC, Namespace, `Cluster`), incluido en
  las 30 kustomizations hoja y aplicado.
- CI: `.github/workflows/validar.yml` con `scripts/flux/validar.sh` (kubeconform `-strict`, salta los CRD upstream) y
  `scripts/flux/revisar_sops.py`. En verde en el PR.
- `diff_todo.py`: 0 cambios en las 37 carpetas.
- Los 23 huérfanos, exportados en `~/.cache/flux-plan/huerfanos.yaml`, se borraron con autorización del usuario (el
  clasificador bloquea el borrado en lote sin ella).

**Cerrada (2026-10-16):** `inventario.py` solo muestra los releases de Traefik y `cnpg` (0 errores), `diff_todo.py`
da 0 cambios en las 37 carpetas, `sops_formato.py` no muestra ningún `BINARIO` y el CI (`kubeconform` y `secretos
SOPS`) pasa en el PR #91.

### Fase 2 — Ensayo en un cluster desechable (~1 h) · misma rama de la fase 3

1. Crear un cluster local con `k3d` en la misma versión de k3s, usando la imagen de prod.
2. Instalar Flux desde la rama, con `sops-age` (la clave real; el cluster se borra al terminar) y `wait: false`.
3. Comprobar que el orden de `dependsOn` funciona (CRDs → operadores → `Cluster`), que se descifran los 17 secretos y
   que el `HelmRelease` se renderiza. Que los pods queden en Pending es lo esperado: no hay NFS ni GPU.

**Listo cuando:** todas las Kustomizations quedan `Ready=True` en k3d sin tocar nada a mano, salvo los dos secretos del bootstrap.

**Avance (2026-10-16, rama `feat/flux-instalar`).**

- **`cluster/flux/`:** `flux-system/` (Flux 2.9.6 con `flux install --components=…,helm-controller --export`, sin
  editar; un patch de afinidad: nunca en `pibot` y preferencia por node-2/3, preferencia y no obligación para que Flux
  siga vivo si caen ambos), `gotk-sync.yaml` (sigue `main` por SSH con la deploy key y solo trae `cluster/` al
  artefacto), `capas.yaml` (9: cert-manager, cnpg, plugin, postgresql, nvidia, traefik, monitoring, cloudflared,
  backups) y `apps.yaml` (19). Las 28 llevan `suspend: true`, `wait: true`, `timeout` 5m (10m en comfyui),
  `prune: false`, `retryInterval` 2m y `deletionPolicy: Orphan` en las 19 con PV/PVC, CRD o el `Cluster`. `dependsOn`:
  cert-manager y cnpg → `cnpg-plugin-barman-cloud` → `postgresql` → `immich`. `backups` no tiene `dependsOn` (escribe
  CronJobs en 17 namespaces y una app caída no debe frenarlo): en un cluster nuevo falla hasta que existen y reintenta.
  La raíz va con `wait: false`, porque si no la bloquearían sus hijas suspendidas.
- **Punto abierto resuelto, los `*.sops.*` sin romper `kubectl apply -k`:** cada carpeta con secretos tiene un
  Component `solo-flux/kustomization.yaml` que los lista (`../secret.sops.yaml`), y su Kustomization de Flux lo suma
  con `spec.components: [solo-flux]`, con `decryption` y `sops-age` solo en esas 9. `kubectl apply -k` no lo ve, porque
  no está en `resources`. Las rutas `../` funcionan porque Flux construye sin restricción de carga dentro del
  artefacto, y flate (el CI) hace lo mismo: la prueba negativa con un `../` roto falla. El HelmRelease de `cnpg`
  va igual (`cnpg/solo-flux/`), para que un `kubectl apply -k` no adopte el release fuera del lote 3. `validar.sh`,
  `diff_todo.py` e `inventario.py` saltan los Component y `cluster/flux`. Consecuencia para la fase 4: ya no hay que
  meter los SOPS en ningún kustomization, porque quitar el `suspend` también activa sus secretos. Cuando se retire
  `kubectl apply -k` (fase 8), pueden pasar a `resources` y `solo-flux/` desaparece.
- **Guarda del ensayo:** como el cluster lleva los secretos reales, si los pods arrancaran pasaría esto: cloudflared
  se sumaría a los túneles de prod, el bot y alertmanager hablarían con Telegram, `minecraft-ddns` movería el DNS y
  Postgres o los respaldos podrían escribir en el S3 de garage y en el NFS. Una ValidatingAdmissionPolicy, cargada
  desde los manifiestos de arranque de k3s, rechaza todo pod fuera de `kube-system`, `flux-system`, `cert-manager` y
  `cnpg-system`. Con `wait: false` las Kustomizations quedan Ready igual, y los 3 operadores sí corren (`wait: true`),
  así que el `dependsOn` se prueba de verdad: el `Cluster` pasa por el webhook de CNPG.
- **Cómo se repite** (`scripts/flux/ensayo_k3d.py`, kubeconfig propio en `~/.cache/flux-plan/ensayo/`, nunca el de
  prod; binarios en `~/.cache/flux-plan/bin`): `crear` → deploy key temporal de solo lectura (`gh repo deploy-key add`)
  → `instalar --rama <rama> --clave-git <clave>` → `kubectl wait ks --all` (repetirlo cuando aparezcan las hijas) →
  `estado` → `borrar` y `gh repo deploy-key delete`. La raíz del ensayo es la de git con 3 cambios: la rama, sus
  `spec.patches` (quitan el `suspend`, ponen `wait: false` salvo en los operadores) y la salida del render de la
  fuente y la raíz de git, porque si no Flux se reaplicaría `gotk-sync.yaml` y volvería a `main`.

**Cerrada (2026-10-16):** k3d con `rancher/k3s:v1.35.9-k3s1`, Flux 2.9.6 desde `feat/flux-instalar@7b899e1`, solo
con los secrets `flux-system` (deploy key temporal, ya borrada) y `sops-age`. Resultado: **29/29 Kustomizations
`Ready=True`** sin tocar nada más. Los **17/17 `*.sops.*`** quedaron descifrados como Secrets, sin ningún valor
`ENC[`. El HelmRelease `cnpg` dio «Helm install succeeded … cloudnative-pg@0.26.0» y se aplicaron el `Cluster`
`homelab-postgres`, el `ObjectStore` `garage` y el `ScheduledBackup`. El orden se ve en los tiempos, desde que se creó
la fuente: raíz +12 s, cert-manager +31 s, cnpg +40 s, plugin +66 s, postgresql +78 s, immich +106 s y backups +134 s
(un reintento por el namespace `cyano`). Mientras esperaban, los dependientes mostraban `DependencyNotReady`.
`flux check` pasó entero. La guarda rechazó 417 pods en 22 namespaces y no corrió ningún pod fuera de ella.
`validar.sh` dio 0 fallas (incluye `cluster/flux`) y `diff_todo.py` 0 cambios en las 37 carpetas. El cluster se borró.

**Para la fase 3 (misma rama):**

- `gotk-sync.yaml` ya apunta a `main` y las 28 están suspendidas, así que aplicar `cluster/flux/flux-system` en prod
  instala Flux sin gestionar nada. La deploy key definitiva reemplaza a la temporal del ensayo.
- ~~Sumar `cluster/flux` a `inventario.py` y `diff_todo.py` y agregar al CI el render de Flux~~: hecho (con flate),
  ver la revisión de la fase 3.
- `kubectl wait ks --all` sale apenas la raíz está Ready, cuando las hijas todavía no existen: esperar de nuevo, o
  esperar por nombre.

### Fase 3 — Instalar Flux sin que gestione nada (~45 min) · `feat/flux-instalar`

1. `flux check --pre` y después `flux install --components=…,helm-controller --export` con el patch de afinidad.
2. Crear la deploy key de solo lectura (`gh repo deploy-key add`) y aplicar a mano los secrets `flux-system` y `sops-age`.
3. Mergear y aplicar `cluster/flux/flux-system`. Es el último apply manual.

**Listo cuando:** `flux check` sale limpio y el GitRepository está `Ready` en el SHA de `main`.

**Revisión antes de empezar (2026-10-16, tras la fase 2).** El paso 1 ya está hecho en la rama y el CI listo. Queda
solo lo que toca prod:

- **Prod, solo lectura:** `flux check --pre` pasa (1.35.9+k3s1). No quedan CRD, namespaces (`flux-system`,
  `argocd`) ni objetos con `app.kubernetes.io/part-of=flux` de los intentos de 2025. RAM libre: node-2 ~2,8 GiB y
  node-3 ~3,8 GiB. Renovate no limita `enabledManagers`, así que su manager `flux` ya ve `gotk-components.yaml`.
- **Ensayo de esta fase en k3d** (`ensayo_k3d.py instalar --como-prod`, con la configuración de git): la raíz y la
  fuente quedan Ready en el SHA de la rama, las 28 hijas siguen suspendidas sin `lastAppliedRevision` y no se crea
  ningún namespace de app ni HelmRelease. Instalar Flux no toca nada más.
- **CI con flate 0.6.5** (job `flate` en `validar.yml`; flux-local está deprecado y no se usa). flate salta las
  Kustomizations suspendidas (con el repo tal cual: 1 pasada, 28 saltadas), así que `scripts/flux/flate.sh` trabaja
  sobre una copia temporal sin los `suspend: true` y valida lo que Flux aplicaría al quitarlos, sin tocar el checkout.
  Resultado: `flate.sh test` da 31/31 (las 29 Kustomizations, el HelmRelease de cnpg y su HelmRepository, con
  `kube-version` 1.35.9). Un `../` roto en un `solo-flux/` hace fallar la prueba. `flate.sh diff origin/main` comenta
  en el PR el cambio de render en formato GitHub (probado: `replicas` 1 → 2 sale como un solo cambio); en este PR
  dice «main no tiene cluster/flux» y no falla. konflate (el revisor de PR de los mismos autores) es un servicio con
  GitHub App dentro del cluster: queda fuera.
- **Local:** `bash scripts/flux/flate.sh test|diff [ref]`, con el binario en `~/.cache/flux-plan/bin/flate`.
- `diff_todo.py` e `inventario.py` suman `cluster/flux` solos cuando existe el CRD de Kustomization. Los secrets
  `flux-system` y `sops-age` no cuentan como huérfanos.

**Runbook** (cada paso es un comando; si el clasificador bloquea uno, parar y pedirlo):

1. `gh pr create --base main --head feat/flux-instalar` con el cuerpo en un archivo. Con el CI en verde
   (kubeconform, secretos SOPS y flate), el usuario mergea: `gh pr merge <n> --merge`.
2. `git fetch` y comprobar que `git diff origin/main -- cluster/flux` sale vacío.
3. `kubectl apply --server-side -k cluster/flux/flux-system`: en esta pasada fallan el GitRepository y la
   Kustomization porque todavía no existen sus CRD (esperable).
4. `kubectl wait --for=condition=established crd -l app.kubernetes.io/part-of=flux --timeout=2m`.
5. Deploy key: `ssh-keygen -q -t ed25519 -N "" -C flux-system-prod -f ~/.cache/flux-plan/deploy-key-prod` →
   `gh repo deploy-key add ~/.cache/flux-plan/deploy-key-prod.pub -R koshiro/homelab-config --title "flux-system
   (prod, solo lectura)"` → `flux create secret git flux-system --url=ssh://git@github.com/koshiro/homelab-config
   --private-key-file=<clave>` → borrar los dos archivos de la clave. Vive solo en el secret; si se pierde, se crea otra.
6. `kubectl create secret generic sops-age -n flux-system --from-file=age.agekey=/Users/daniel/.config/sops/age/keys.txt`.
7. `kubectl apply --server-side -k cluster/flux/flux-system` (2.ª pasada).
8. Verificación: `flux check`; `kubectl -n flux-system wait gitrepository/flux-system kustomization/flux-system
   --for=condition=Ready`; que la revisión de `flux get sources git` sea `git rev-parse origin/main`; `flux get ks`
   (las 28 suspendidas); pods de `flux-system` fuera de `pibot`; `hl.py status`; `diff_todo.py`; `inventario.py`.
9. Marcar la fase 3 aquí con la evidencia, en una rama `docs/` con su PR (`main` ya tiene la instalación).

**Cerrada (2026-10-16):** PR #92 con el CI en verde (kubeconform, secretos SOPS, GitGuardian y flate `✓ 31 passed`),
mergeado en `1e0b6fb`. Antes, `flux check --pre` pasó y no había CRD ni namespace de Flux. El runbook se siguió tal
cual: en la 1.ª pasada solo fallaron el GitRepository y la Kustomization (sin CRD), los 11 CRD quedaron `established`,
deploy key `166666091` «flux-system (prod, solo lectura)» (`read-only`, la única del repo; la clave local se borró),
los secrets `flux-system` y `sops-age`, y la 2.ª pasada sin errores (10:35:32 GMT-3). Resultado:

- `flux check`: «all checks passed» (Flux 2.9.6: source 1.9.6, kustomize 1.9.6, helm 1.6.5, notification 1.9.4).
- GitRepository Ready a los 4 s en `main@sha1:1e0b6fbccda692317d625ccb9c3b62611c86a5c6` = `git rev-parse origin/main`;
  la raíz, Ready a los 7 s con «Applied revision» en el mismo SHA.
- Las **28 hijas** tienen `suspend: true` y ninguna tiene `lastAppliedRevision`. No hay ningún HelmRelease,
  HelmRepository ni HelmChart de Flux (solo los de Traefik que trae k3s).
- Los 4 pods de `flux-system` corren en `k3s-node-2`, sin reinicios. No hay logs de error ni eventos Warning.
- `hl.py status`: 0 pods con problema. `diff_todo.py`: 39/39 carpetas OK, con `flux` y `flux/flux-system`.
  `inventario.py`: 0 errores, y solo aparecen los releases de Traefik y `cnpg`, como al cerrar la fase 1. Los secrets
  del bootstrap no salen como huérfanos.
- **Flux ya se gestiona a sí mismo:** la raíz aplica `cluster/flux/flux-system` (62 objetos con el manager
  `kustomize-controller`). Desde ahora, un cambio en Flux va por PR y no con `kubectl apply`.
- Herramienta para la fase 4: `hl.py flux` muestra la fuente comparada con el SHA de `main`, cada Kustomization
  activa con su Ready y su revisión, las suspendidas, los HelmRelease y el nodo de cada pod. Sale con 1 si alguna
  activa no está Ready en `main`. Adelanta el `hl.py flux` de la fase 8.

### Fase 4 — Adopción con prune apagado (~1,5 h) · 3 PR seguidos

1. Tomar la línea base: un script que guarda, por workload, `pod-template-hash`, `generation` y UID de los pods, más el
   número de objetos por namespace. Además, `k3s etcd-snapshot save --name pre-flux`.
2. Todas las Kustomizations quedan en git con `suspend: true`. Cada PR quita el `suspend` a un lote; sus
   `*.sops.y*ml` ya entran por `solo-flux/` (fase 2), así que desde ese PR dejan de aplicarse con `hl.py sops apply`.
   Orden: primero las webs y el monitoreo, después media y apps, y al final infra, `cnpg` (adopción del release) y
   `postgres`.
3. Antes de cada PR: `flux diff ks <ks> --path <dir>` debe mostrar solo cambios de etiquetas o de manager.

Se puede parar entre lotes: lo que está en un lote ya activo lo despliega Flux, y el resto se sigue aplicando con
`kubectl apply -k`. La lista que manda es `cluster/flux/apps.yaml`: ahí se ve qué Kustomizations tienen el `suspend` quitado.

**Listo cuando:** la comparación con la línea base da 0 `pod-template-hash` distintos (ningún reinicio no buscado) y
0 objetos menos; cada Kustomization tiene `lastAppliedRevision` igual a `git rev-parse origin/main`; ningún objeto de
prueba conserva `kubectl-client-side-apply` en sus `managedFields`; vmalert no disparó alertas en la ventana; los
sitios públicos responden 200 y CNPG tiene 3 instancias sanas.

**Punto de partida (2026-10-16, 11:55 GMT-3):** `hl.py flux` con la fuente en `main@38c6c68`, 0 problemas y 28
suspendidas. `hl.py status` sin pods con problema, `diff_todo.py` con 39/39 OK, `inventario.py` con 0 errores y solo
los releases de Traefik y `cnpg`. Línea base `~/.cache/flux-plan/linea-base-pre-flux.json` (`scripts/flux/linea_base.py`):
82 workloads, 76 pods y 909 objetos sin contar los tipos volátiles. etcd: `pre-flux-pibot-1792162588`. vmalert: 1
alerta previa, `SwapOutHostProxmox` (host pve, *pending* desde las 11:47 y *firing* después; no tiene que ver con Flux).

**Lote 1, webs y monitoreo (PR #94, mergeado 12:09 GMT-3 en `main@397ac23`).** Control antes del PR: `flux diff ks`
dio 53 objetos, todos con solo las etiquetas `kustomize.toolkit.fluxcd.io/*`. Los 3 Secrets SOPS de monitoring
(`flux diff` no los muestra porque los enmascara como `**SOPS**`) se compararon descifrados con el vivo: iguales.
Después del merge, la raíz y las 4 llegaron a `lastAppliedRevision` = `git rev-parse origin/main` y `hl.py flux` dio 0
problemas. `josekast` quedó solo con `kustomize-controller/Apply` y `k3s/Update`, sin `kubectl-client-side-apply` ni
la anotación `last-applied-configuration`. Los 4 sitios dan 200 (grafana da 302 por Access) y vmalert no tiene alertas
nuevas. `hl.py status` sin pods con problema y 909 → 909 objetos.

- **Un reinicio no buscado:** `monitoring/pve-exporter` (12:11). Su contenedor tenía `imagePullPolicy: Always`, que
  el apiserver le dio por defecto cuando la imagen era `:latest`. Git fija `3.10.1` sin decir nada, y `kubectl apply`
  (client-side) conservaba el valor. Al adoptar, kustomize-controller pasa a su nombre los campos de **todo manager
  que empiece con `kubectl`** (`kubectl-client-side-apply`, `kubectl-rollout`, `kubectl-label`, `kubectl-patch`…;
  `matchFieldManager` de `fluxcd/pkg/ssa` compara por prefijo). Además borra los que git no trae, y el apiserver
  completa el valor por defecto: `IfNotPresent`. `flux diff` no lo ve, porque su dry-run no hace ese traspaso.
- **Generation +1 sin reinicio** en los 9 Deployments restantes: Flux quita `last-applied-configuration` y en un
  Deployment un cambio de anotaciones sube la generation. `linea_base.py` la trata como aviso.
- **Control nuevo para los lotes 2 y 3:** `scripts/flux/simular_adopcion.py <ks>…` hace con dry-runs lo que hará Flux
  (traspaso de dueños, apply de git y valores por defecto en una copia renombrada) y lista lo que cambia de verdad.
  También compara con el vivo, sin imprimir valores, los Secrets SOPS descifrados. Con lo ya adoptado da 0.

**Lote 2, media y apps (PR #95, mergeado 13:20 GMT-3 en `main@61f0770`).** El control se hizo con `flux diff` más
`simular_adopcion.py`, y se mostraron al usuario 3 cosas que `diff_todo.py` (con `kubectl diff`) no veía. Las aprobó:

- **Reinicio único de 19 Deployments.** 15 tenían un `restartedAt` de algún `kubectl rollout restart` anterior (plex,
  qbittorrent, radarr, sonarr, overseerr, cups-airprint, comfyui, swarmui, minecraft, minecraft-proxy,
  minecraft-spiral3, ollama, node-odx-1, webapp y worker). Otros 4 pasaron de `imagePullPolicy` `Always` a
  `IfNotPresent`, todos con tags fijos (bazarr, flaresolverr, prowlarr y pingvin).
- **qbittorrent:** se agregaron `hostPort: 6881` en `bt-udp` y el puerto 6881/UDP del Service `qbittorrent`. Git los
  declaraba, pero faltaban en vivo por el bug de strategic-merge de `kubectl apply` con TCP y UDP en el mismo puerto.
  Además se creó el Secret `qbittorrent-credentials`, que está en git y no usa nadie.
- **`minecraft-restart`** ahora corre con `--field-manager=minecraft-restart`. Con `kubectl-rollout`, Flux absorbería
  el `restartedAt` y reiniciaría minecraft dos veces por día.

Resultado: las 15 y la raíz llegaron a `main@61f0770`, y `hl.py flux` dio 20 activas Ready y 0 problemas.
`linea_base.py comparar --nombre pre-lote2` dio hash distinto y pods reemplazados exactamente en esos 19, 0 objetos
menos y 910 objetos (+1, el Secret). plex quedó solo con `kustomize-controller/Apply` y `k3s/Update`; comfyui ve la
RTX 3070 (sin NVML Unknown Error) y qbittorrent tiene los dos hostPort. `hl.py status` sin pods con problema. vmalert
dio un `DeploymentIncompleto` *pending* en webodm durante su rollout `Recreate`, que se apagó solo; no hubo alertas
*firing*. Los 9 Secrets SOPS descifrados eran iguales al vivo antes del merge.

### Fase 5 — Avisos (~45 min) · `feat/flux-avisos`

1. `Provider telegram` + `Alert` (`eventSeverity: error`) y `Provider github` (token fine-grained solo con `statuses: write`, en SOPS).
2. Scrape de los controladores y la regla `FluxSinReconciliar` (`Ready=False` por más de 15 min).

**Listo cuando:** los commits de `main` muestran el estado de Flux en GitHub.

### Fase 6 — Prueba de fallas (~45 min)

1. **Deriva:** `kubectl scale deploy/noledigasanadie --replicas=0` → Flux lo repone. Anotar cuánto tarda.
2. **PR roto:** un manifiesto inválido en una rama → el CI falla.
3. **Merge válido pero roto:** un tag de imagen que no existe en una app de bajo riesgo → llega el aviso a Telegram y el estado del commit en rojo; al revertir, vuelve el verde.
4. **Prune:** con prune activo, un ConfigMap de prueba que se saca de git desaparece; un PVC anotado que se saca de git se queda.
5. **Reconstrucción:** un k3d nuevo desde `main` llega a `Ready` solo con los dos secretos.

**Listo cuando:** las 5 pruebas dan el resultado esperado y queda registro de cada una (hora, aviso, captura del estado del commit).

### Fase 7 — Prune y automerge (~30 min + 1 sábado) · `feat/flux-prune-automerge`

1. Activar `prune: true` por capa (monitoreo y red → apps → postgres e infra), revisando antes `flux tree ks <ks>`.
2. `renovate.json`: `automerge` con `platformAutomerge: false` para `monitoreo`, `utilidades` y `cloudflare` (minor,
   patch y digest), y el manager `flux` sin automerge.

**Listo cuando:** el primer sábado, un PR de Renovate se mergea solo y su commit queda verde por Flux sin intervención.

### Fase 8 — Documentación y skill (~1 h) · `docs/flux`

1. `AGENTS.md`, punto 5 del flujo: para probar en caliente, `flux suspend ks <app>` → cambio → merge → `flux resume`.
2. `DISENO-APPS`, `README` (GitOps y reconstrucción desde cero), `ARQUITECTURA` y `PENDIENTES` §6/§6b.
3. Skill homelab: `hl.py flux` (Kustomizations que no están `Ready`, con el motivo) e `hl.py inventario` (este
   script); la trampa «un cambio manual se revierte»; la receta *app nueva* con su entrada en `apps.yaml`.

## 3. Quién confirma que está bien (ni tú ni yo)

| Afirmación | Verificador |
|------------|-------------|
| `main` es el estado del cluster | Flux (`lastAppliedRevision` igual al SHA de `main`) y GitHub (estado del commit) |
| La adopción no reinició ni borró nada | La comparación con la línea base (hash de plantilla, UIDs, conteo de objetos) |
| Todo lo que corre está en git | `inventario.py` en 0 |
| Se puede reconstruir | Un cluster k3d nuevo que llega a `Ready` desde `main` |
| Si algo falla, me entero | El mensaje real de Telegram en la prueba de fallas |
| Nadie lo notó desde afuera | vmalert sin alertas y Cloudflare con 200 durante la ventana |

## 4. Total

~10,5 h en 9 sesiones de 45 min a 2,5 h. Cualquier fase se puede dejar para otro día; solo la fase 7 tiene que
esperar a un sábado de Renovate.
