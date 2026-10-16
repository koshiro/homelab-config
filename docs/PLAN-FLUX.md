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

- [ ] Fase 0 — k3s 1.35 y kit de recuperación
- [ ] Fase 1 — Repo = cluster en ambas direcciones
- [ ] Fase 2 — Ensayo en k3d
- [ ] Fase 3 — Flux instalado sin gestionar nada
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
| SOPS | `.sops.yaml` en la raíz (`encrypted_regex: ^(data\|stringData)$`, el destinatario age actual); los 17 archivos dentro de sus kustomizations | Un solo formato para todos, y es el que Flux descifra |
| CI | `flux-local` (`test` + `diff` comentado en el PR), `kubeconform -strict` con los schemas de los CRD y una revisión de que todo `*.sops.*` esté estructurado y cifrado | `flux-local` renderiza igual que Flux; sin checks, Renovate no hace automerge |
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

### Fase 2 — Ensayo en un cluster desechable (~1 h) · misma rama de la fase 3

1. Crear un cluster local con `k3d` en la misma versión de k3s, usando la imagen de prod.
2. Instalar Flux desde la rama, con `sops-age` (la clave real; el cluster se borra al terminar) y `wait: false`.
3. Comprobar que el orden de `dependsOn` funciona (CRDs → operadores → `Cluster`), que se descifran los 17 secretos y
   que el `HelmRelease` se renderiza. Que los pods queden en Pending es lo esperado: no hay NFS ni GPU.

**Listo cuando:** todas las Kustomizations quedan `Ready=True` en k3d sin tocar nada a mano, salvo los dos secretos del bootstrap.

### Fase 3 — Instalar Flux sin que gestione nada (~45 min) · `feat/flux-instalar`

1. `flux check --pre` y después `flux install --components=…,helm-controller --export` con el patch de afinidad.
2. Crear la deploy key de solo lectura (`gh repo deploy-key add`) y aplicar a mano los secrets `flux-system` y `sops-age`.
3. Mergear y aplicar `cluster/flux/flux-system`. Es el último apply manual.

**Listo cuando:** `flux check` sale limpio y el GitRepository está `Ready` en el SHA de `main`.

### Fase 4 — Adopción con prune apagado (~1,5 h) · 3 PR seguidos

1. Tomar la línea base: un script que guarda, por workload, `pod-template-hash`, `generation` y UID de los pods, más el
   número de objetos por namespace. Además, `k3s etcd-snapshot save --name pre-flux`.
2. Todas las Kustomizations quedan en git con `suspend: true`. Cada PR quita el `suspend` a un lote y, en ese mismo
   PR, mete los `*.sops.y*ml` del lote en sus kustomizations. Orden: primero las webs y el monitoreo, después media y
   apps, y al final infra, `cnpg` (adopción del release) y `postgres`.
3. Antes de cada PR: `flux diff ks <ks> --path <dir>` debe mostrar solo cambios de etiquetas o de manager.

Se puede parar entre lotes: lo que está en un lote ya activo lo despliega Flux, y el resto se sigue aplicando con
`kubectl apply -k`. La lista que manda es `cluster/flux/apps.yaml`: ahí se ve qué Kustomizations tienen el `suspend` quitado.

**Listo cuando:** la comparación con la línea base da 0 `pod-template-hash` distintos (ningún reinicio no buscado) y
0 objetos menos; cada Kustomization tiene `lastAppliedRevision` igual a `git rev-parse origin/main`; ningún objeto de
prueba conserva `kubectl-client-side-apply` en sus `managedFields`; vmalert no disparó alertas en la ventana; los
sitios públicos responden 200 y CNPG tiene 3 instancias sanas.

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
