# Diseñar y portar aplicaciones para el cluster

Guía para agentes que **crean una aplicación nueva o portan una existente** (docker-compose, Helm, otro cluster) al k3s
del homelab. Si la app cumple el contrato de la sección 2 y se empaqueta como en la sección 5, se despliega con un
`kubectl apply -k` sin ajustes posteriores.

Estado verificado contra el cluster el 2026-10-08. Ante una contradicción con `.cursor/skills/homelab-deploy-apps`,
**manda este documento** (esa skill está obsoleta: menciona `nfs-csi`/`nfs-immich`, que no existen).

---

## 1. El cluster en una página

### Nodos

| Nodo | Qué es | Arquitectura | CPU / RAM asignable | Notas para diseñar |
|---|---|---|---|---|
| `pibot` (`k3s-node-0` en el tailnet, 192.168.1.15) | Raspberry Pi, control-plane + etcd | **arm64** | 4 / 3,7 GiB | Sobrevive a una caída de Proxmox. Poca RAM: solo cargas livianas y críticas (sitios estáticos, conectores). Exige `nodeName: pibot` + tolerations |
| `k3s-node-1` (192.168.1.131) | VM en Proxmox, label `node-role.kubernetes.io/media-worker` | amd64, CPU `host` | 8 / 23,5 GiB | **Única GPU**: RTX 3070 8 GB, time-slicing (`nvidia.com/gpu: 10` virtuales, misma VRAM). Único worker con x86-64-v2 |
| `k3s-node-2` (192.168.1.132) | VM en Proxmox | amd64, CPU `kvm64` | 4 / 7,7 GiB | **Sin x86-64-v2** (sin SSE4.2): NumPy reciente, PyTorch, Immich ML y similares fallan (`PENDIENTES.md` §4c) |
| `k3s-node-3` (192.168.1.133) | VM en Proxmox | amd64, CPU `kvm64` | 6 / 15,6 GiB | Igual que node-2 |

Ningún nodo tiene taints salvo los de control-plane de pibot. El scheduler reparte libremente entre node-1/2/3.

**Si cae Proxmox, solo queda pibot.** Traefik, CoreDNS, el túnel `pve`, el NFS y los tres workers mueren con él.

### Almacenamiento

| Opción | Cómo se pide | Dónde vive | Respaldo | Úsala para |
|---|---|---|---|---|
| `local-path` (default) | PVC dinámico, `ReadWriteOnce` | Disco de la VM worker donde cae el pod la primera vez (el pod queda **atado a ese nodo**) | Ninguno automático: hay que añadir un CronJob `config-backup-<app>` (§4.6) | Config, SQLite, caches, datos pequeños y reconstruibles |
| `nfs-proxmox` | **PV estático** + PVC con `volumeName` | Dataset ZFS `nvme/k8s/<app>` (mirror NVMe) exportado por NFS desde 192.168.1.100 | Automático: sanoid (24 h · 14 d · 4 sem · 6 meses) + syncoid a `respaldo` + opcional restic a R2 | Datos de usuario valiosos (fotos, archivos subidos, mundos) |
| NFS de `homelab-storage` | PV estático sin StorageClass (ver `cluster/04-media-stack/pv-media-library.yml`) | Disco de 12 TB **sin redundancia**, `/mnt/homelab-storage/<x>` | Ninguno (datos reemplazables) | Media, modelos de IA, descargas, datos voluminosos que se pueden volver a obtener |
| `hostPath` en pibot | `hostPath: /var/lib/homelab-<app>` + `nodeName: pibot` | NVMe de la Pi | CronJob en `webs-estaticas-backup.yaml` | **Solo** sitios estáticos y cosas que deben sobrevivir a Proxmox |
| `emptyDir` | volumen del pod | efímero | — | Temporales, `/tmp` con `readOnlyRootFilesystem` |

Prohibido: `nfs-csi`, `nfs-immich` u otra StorageClass inventada (no hay CSI de NFS instalado); `hostPath` en los
workers; SQLite sobre NFS (bloqueos y corrupción).

### Red y exposición

- **Túnel `pve`** (conector `cloudflared` en los workers) con comodín `*.danielriquelme.cl → traefik.kube-system:80`.
  Consecuencia: **todo Ingress con host `*.danielriquelme.cl` queda público en internet** sin hacer nada más. TLS lo
  termina Cloudflare: el Ingress no lleva sección `tls`.
- **Túnel `pibot-webs`** (conector en pibot): sitios estáticos, origen `http://192.168.1.15:<nodePort>`, sin Traefik.
- **Tailnet**: los NodePort son accesibles en `http://k3s-node-0:<puerto>` desde los dispositivos del tailnet. Es la vía
  para todo lo administrativo.
- **LoadBalancer** (klipper/svclb de k3s): publica el puerto en las IPs de los 4 nodos. Solo para protocolos no HTTP
  que deban verse en la LAN o reenviarse desde el router (ej. Minecraft 25565/TCP, 19132/UDP).
- Traefik corre en `kube-system` con label `app.kubernetes.io/name: traefik` (dato necesario para las NetworkPolicy).

NodePorts ocupados (revisar `kubectl get svc -A | grep NodePort` antes de elegir uno):
30080, 30188, 30189, 30190, 30444, 30681, 30808, 30890, 30891, 31434, 31551, 31631, 31681, 31682, 31808, 31987,
32400, 32575, 30277.

### Secretos

SOPS + age, receptor `age1ga4dqzwv2wrf5c0dduz0vsjkzlda9xzrp787u2mnhhj6zh5qxaws4mlhhs`, solo se cifran `data`/`stringData`.
En este Mac: `export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt`. Los `*.sops.y*ml` **no van en
`kustomization.yml`** (kubectl no los descifra): se aplican aparte con `sops -d … | kubectl apply -f -` y se anotan en
un comentario del `kustomization.yml`.

### Bases de datos

- **Postgres compartido**: cluster CloudNativePG 1.27 `homelab-postgres` (ns `postgresql`, 3 instancias en
  `local-path`, Postgres 17.5). Servicio de escritura: `homelab-postgres-rw.postgresql.svc.cluster.local:5432`.
  Soporta CRD `Database` y roles administrados (`spec.managed.roles`).
- **SQLite** en un PVC `local-path`: la opción preferida para apps pequeñas de un solo usuario/réplica.
- Redis u otros: como contenedor dentro del namespace de la app, sin persistencia salvo que sea imprescindible.

### Cómo se aplica

No hay Flux todavía (`PENDIENTES.md` §6). `main` = estado del cluster; se aplica con `kubectl apply -k` desde la rama y
el PR se mergea apenas se confirma que funciona (GitHub Flow, ver `AGENTS.md`). `kubectl` local funciona contra
`k3s-node-0:6443`.

---

## 2. Contrato de la aplicación

Requisitos que debe cumplir el **diseño** de la app (al crearla) o que hay que verificar/forzar con configuración (al
portarla). Cada punto evita un problema que ya ocurrió o un límite real del cluster.

### Imagen

1. **Imagen pública con tag fijo** (`nginx:1.27-alpine`, `ghcr.io/…:2.24.2`), nunca `latest` en apps nuevas. No existe
   registry propio ni pipeline de build.
2. **amd64** como mínimo; **multi-arch (amd64 + arm64)** si la app podría tener que correr en pibot.
3. Si la imagen usa NumPy/PyTorch/ONNX modernos o binarios compilados con `-march=x86-64-v2`: fijar a `k3s-node-1`.
4. **Código propio**, en este orden de preferencia:
   - **a)** Script pequeño (un archivo, ≲ 1 MiB) sobre una imagen base oficial, montado con `configMapGenerator`
     (patrón `cluster/apps/minecraft/whitelist-bot/`: `python:3.13-alpine` + `bot.py`). Preferir solo stdlib.
   - **b)** Imagen base + `initContainer` que instala dependencias en un `emptyDir`/PVC (lento en cada arranque; solo si
     las dependencias son pocas y no hay alternativa).
   - **c)** Imagen propia publicada en un registry (p. ej. `ghcr.io/koshiro/<app>`): **no existe aún**; requiere que el
     usuario decida el registry y las credenciales de pull. Preguntar antes de diseñar en esa dirección.

### Proceso y configuración

5. **Configuración por variables de entorno**; archivos de config completos vía ConfigMap. Nada que obligue a entrar
   al contenedor a editar a mano.
6. **Secretos solo por variables de entorno o archivos montados desde un Secret.** Nunca en la imagen, el ConfigMap ni
   los argumentos.
7. **Corre como no-root**, UID/GID `1000` (convención del cluster; los respaldos restauran con `chown 1000:1000`).
   Compatible con `readOnlyRootFilesystem: true` + `emptyDir` en `/tmp`, salvo que la imagen upstream lo impida.
8. **Todo el estado bajo uno o dos directorios conocidos** (`/data`, `/config`). Separar estado *valioso* (archivos del
   usuario → NFS) de estado *de configuración/DB* (→ `local-path`) y de *cache* (→ `emptyDir` o excluido del respaldo).
9. **Logs a stdout/stderr.** Nada de archivos de log que crezcan sin rotación dentro del PVC.
10. **Zona horaria**: `TZ=America/Santiago` si la app agenda cosas por hora local.

### HTTP

11. **Un solo puerto HTTP en texto plano** (sin TLS propio; Cloudflare/Traefik lo terminan).
12. **Funciona detrás de proxy**: respeta `X-Forwarded-Proto/For/Host` (opción tipo `TRUST_PROXY=true`) y genera URLs
    absolutas con `https://<app>.danielriquelme.cl` (variable tipo `BASE_URL`/`PUBLIC_URL`).
13. **Sirve en la raíz `/`** de su propio subdominio. Sin rutas base (`/app/`) salvo que la app lo exija.
14. **Endpoint de salud barato** (`/healthz`, `/api/health`) que no dependa de servicios externos, para
    `readinessProbe`/`livenessProbe`.
15. **Autenticación propia** si se publica por Ingress (es público). Si la app no tiene login fuerte, no va por
    Ingress: va por NodePort/tailnet.

### Resiliencia

16. **Arranca sola tras un corte de luz** (el homelab los sufre): migraciones idempotentes, sin lockfiles que bloqueen el arranque, reintentos si la BD o el NFS
    tardan en aparecer.
17. **Termina limpio con SIGTERM** en < 30 s (apagado ordenado del cluster con el playbook de Ansible).
18. **Una réplica es suficiente.** Con PVC `ReadWriteOnce`, usar `strategy: Recreate`. Si la app no tolera dos
    instancias simultáneas (bots con long polling, SQLite), `Recreate` es obligatorio.
19. **Recursos acotados**: declarar `requests` y `limits` de memoria. Referencia: web liviana 32–128 Mi, app típica
    256 Mi–1 Gi, nada > 4 Gi sin fijarla a node-1 o node-3.

### GPU (solo si la necesita)

20. Una sola GPU de 8 GB compartida por time-slicing con Ollama, ComfyUI y Plex: **la VRAM no está aislada**. La app
    debe liberar VRAM cuando está ociosa (descargar modelos) o tolerar `CUDA out of memory` con reintento.

---

## 3. Árbol de decisiones

Responde en orden; cada respuesta fija una parte del manifiesto.

**¿Debe seguir en línea si cae Proxmox?** (solo sitios estáticos o servicios críticos muy livianos)
→ Sí: patrón *sitio en pibot* (§4.2). → No: worker normal.

**¿Necesita GPU o CPU con x86-64-v2?** → Sí: fijar a `k3s-node-1` (§4.3). → No: sin afinidad.

**¿Qué datos guarda?**

| Tipo de dato | Almacenamiento |
|---|---|
| Nada (stateless) | Ninguno |
| Config/SQLite/pequeño (< 5 GiB) | PVC `local-path` + CronJob `config-backup-<app>` |
| Datos de usuario irremplazables | PV estático `nfs-proxmox` en `nvme/k8s/<app>` (requiere crear dataset y export en Proxmox) |
| Voluminoso y reemplazable (media, modelos) | PV estático NFS en `/mnt/homelab-storage/<app>` |
| Relacional con varios usuarios/concurrencia | Base en `homelab-postgres` (§4.5) |

**¿Quién la usa y desde dónde?**

| Público | Exposición |
|---|---|
| Cualquiera en internet, con login propio | Ingress `traefik` con host `<app>.danielriquelme.cl` |
| Solo el dueño / administración | Service NodePort fijo → `http://k3s-node-0:<puerto>` por tailnet. **Sin Ingress** |
| Solo otras apps del cluster | Service ClusterIP |
| Protocolo no HTTP desde LAN/internet | Service LoadBalancer (+ reenvío en el router si es externo) |
| Dominio distinto de `danielriquelme.cl` | Ingress + hostname público en el túnel por API de Cloudflare (§6) |

**¿Corre continuo o por lotes?** → Continuo: Deployment. → Periódico: CronJob con `timeZone: America/Santiago`,
`concurrencyPolicy: Forbid`. → Una vez: Job.

---

## 4. Plantillas

Una carpeta por app en `cluster/apps/<app>/` (o en la capa temática si encaja: `04-media-stack/`, `05-services/`). Un
namespace por app, con el mismo nombre que la carpeta. Nombres de archivo del patrón actual:

```
cluster/apps/<app>/
├── kustomization.yml
├── namespace.yml
├── deployment.yml
├── service.yml
├── ingress.yml            # solo si es pública
├── pvc.yml                # PV/PVC
├── networkpolicy.yml
├── secret.sops.yml        # fuera de kustomization; se aplica con sops -d
└── README.md              # opcional: operación específica (restaurar, actualizar)
```

Los manifiestos llevan un comentario de cabecera que explica las decisiones no obvias (por qué ese nodo, por qué ese
almacenamiento), en español.

### 4.1 App web típica (worker, Ingress público, config en local-path)

`kustomization.yml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: miapp
resources:
  - namespace.yml
  - pvc.yml
  - deployment.yml
  - service.yml
  - ingress.yml
  - networkpolicy.yml
# Secret (aplicar aparte): sops -d cluster/apps/miapp/secret.sops.yml | kubectl apply -f -
```

`namespace.yml`:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: miapp
```

`pvc.yml`:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: miapp-data
  namespace: miapp
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: local-path
  resources:
    requests:
      storage: 2Gi
```

`deployment.yml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: miapp
  namespace: miapp
  labels:
    app: miapp
spec:
  replicas: 1
  strategy:
    type: Recreate            # PVC RWO / SQLite: nunca dos pods a la vez
  selector:
    matchLabels:
      app: miapp
  template:
    metadata:
      labels:
        app: miapp
    spec:
      securityContext:
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
        runAsNonRoot: true
      containers:
        - name: miapp
          image: ghcr.io/upstream/miapp:1.4.2
          ports:
            - name: http
              containerPort: 8080
          env:
            - name: TZ
              value: America/Santiago
            - name: BASE_URL
              value: https://miapp.danielriquelme.cl
            - name: TRUST_PROXY
              value: "true"
            - name: SECRET_KEY
              valueFrom:
                secretKeyRef:
                  name: miapp
                  key: SECRET_KEY
          readinessProbe:
            httpGet: {path: /healthz, port: http}
            initialDelaySeconds: 5
            periodSeconds: 10
          livenessProbe:
            httpGet: {path: /healthz, port: http}
            initialDelaySeconds: 30
            periodSeconds: 30
            failureThreshold: 5
          resources:
            requests: {cpu: 50m, memory: 128Mi}
            limits: {memory: 512Mi}
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
          volumeMounts:
            - name: data
              mountPath: /data
            - name: tmp
              mountPath: /tmp
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: miapp-data
        - name: tmp
          emptyDir: {}
```

`service.yml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: miapp
  namespace: miapp
spec:
  type: ClusterIP
  selector:
    app: miapp
  ports:
    - name: http
      port: 8080
      targetPort: http
```

`ingress.yml` (público por el comodín del túnel; no hay que tocar Cloudflare):

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: miapp
  namespace: miapp
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
spec:
  ingressClassName: traefik
  rules:
    - host: miapp.danielriquelme.cl
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: miapp
                port:
                  number: 8080
```

`networkpolicy.yml` (deny por defecto, entra solo Traefik, sale DNS + HTTP/S):

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
  namespace: miapp
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-traefik-ingress
  namespace: miapp
spec:
  podSelector:
    matchLabels:
      app: miapp
  policyTypes: [Ingress]
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
          podSelector:
            matchLabels:
              app.kubernetes.io/name: traefik
      ports:
        - protocol: TCP
          port: 8080
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-basic-egress
  namespace: miapp
spec:
  podSelector: {}
  policyTypes: [Egress]
  egress:
    - ports:
        - {protocol: UDP, port: 53}
        - {protocol: TCP, port: 53}
    - to:
        - ipBlock: {cidr: 0.0.0.0/0}
      ports:
        - {protocol: TCP, port: 80}
        - {protocol: TCP, port: 443}
```

Ajustes según el caso:
- **Usa Postgres**: añadir egress a `namespaceSelector: kubernetes.io/metadata.name: postgresql`, puerto 5432.
- **Usa NFS montado como volumen**: no necesita regla (el montaje lo hace el kubelet del nodo, no el pod).
- **Expuesta por NodePort**: el tráfico llega desde la IP del nodo; añadir un `ingress` con
  `ipBlock: {cidr: 192.168.1.0/24}` y otro con `ipBlock: {cidr: 10.42.0.0/16}` (pods/kube-proxy), o prescindir del
  deny de ingreso. Probar siempre desde el tailnet tras aplicar.

`secret.yml` en claro **solo como archivo temporal** fuera del repo, luego cifrar:

```bash
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt
cat > "$TMPDIR/secret.yml" <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: miapp
  namespace: miapp
type: Opaque
stringData:
  SECRET_KEY: "<generado con openssl rand -hex 32>"
EOF
sops --encrypt --age age1ga4dqzwv2wrf5c0dduz0vsjkzlda9xzrp787u2mnhhj6zh5qxaws4mlhhs \
  --encrypted-regex '^(data|stringData)$' "$TMPDIR/secret.yml" > cluster/apps/miapp/secret.sops.yml
rm "$TMPDIR/secret.yml"
```

`metadata.namespace` dentro del Secret es obligatorio (se aplica fuera de kustomize).

### 4.2 Sitio estático en pibot (sobrevive a Proxmox)

Copiar `cluster/apps/josekast/` tal cual y cambiar nombres. Claves del patrón:
- `nodeName: pibot` + tolerations `node-role.kubernetes.io/control-plane` y `…/master` (`NoSchedule`).
- nginx `nginx:1.27-alpine` (multi-arch), contenido en `hostPath: /var/lib/homelab-<sitio>` `type: Directory`,
  montado `readOnly`. Crear la carpeta antes: `ssh daniel@k3s-node-0 sudo install -d -o daniel -g daniel /var/lib/homelab-<sitio>`.
- Service **NodePort fijo** (siguiente libre de la serie 3089x) como origen del túnel `pibot-webs`
  (`http://192.168.1.15:<nodePort>`); el Ingress queda solo como respaldo por el túnel `pve`.
- Respaldo: nuevo CronJob en `cluster/00-infrastructure/backups/webs-estaticas-backup.yaml` y nombre en el bucle de
  `proxmox/bin/check-backups.sh`.
- Hostname público en el túnel `pibot-webs` por API (§6).
- Publicar contenido: `rsync -a --delete <carpeta>/ daniel@k3s-node-0:/var/lib/homelab-<sitio>/`.

Si el sitio necesita backend, no es un sitio estático: va en un worker (§4.1) y no sobrevive a Proxmox. Decirlo
explícitamente al usuario.

### 4.3 App con GPU

```yaml
    spec:
      runtimeClassName: nvidia
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - key: node-role.kubernetes.io/media-worker
                    operator: In
                    values: ["true"]
      containers:
        - name: miapp
          resources:
            requests: {nvidia.com/gpu: "1"}
            limits: {nvidia.com/gpu: "1", memory: 8Gi}
```

Mismo `nodeAffinity` (sin `runtimeClassName` ni `nvidia.com/gpu`) para apps que solo necesitan x86-64-v2. Ver
`cluster/apps/ollama-stack/deployment-ollama.yml` y `cluster/apps/comfyui/00-deployment.yaml`.

### 4.4 Datos valiosos en NFS de Proxmox (`nvme/k8s/<app>`)

`pvc.yml`:

```yaml
# Datos de usuario en Proxmox: dataset ZFS nvme/k8s/miapp, export NFS (proxmox/etc/k8s.exports).
# Snapshots sanoid + réplica syncoid a respaldo/k8s automáticos (heredan de nvme/k8s).
apiVersion: v1
kind: PersistentVolume
metadata:
  name: miapp-data-pv
spec:
  capacity:
    storage: 50Gi
  accessModes: [ReadWriteMany]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: nfs-proxmox
  nfs:
    server: 192.168.1.100
    path: /nvme/k8s/miapp
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: miapp-data-pvc
  namespace: miapp
spec:
  accessModes: [ReadWriteMany]
  storageClassName: nfs-proxmox
  volumeName: miapp-data-pv
  resources:
    requests:
      storage: 50Gi
```

Pasos en Proxmox (antes de aplicar; requieren confirmación del usuario porque tocan el host):

```bash
ssh root@192.168.1.100 'zfs create nvme/k8s/miapp && chown 1000:1000 /nvme/k8s/miapp'
# Añadir la línea al repo (proxmox/etc/k8s.exports) y copiarla al host:
#   /nvme/k8s/miapp 192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash)
scp proxmox/etc/k8s.exports root@192.168.1.100:/etc/exports.d/k8s.exports
ssh root@192.168.1.100 exportfs -ra
```

Luego: añadir `miapp` al bucle `for d in …` de sanoid/réplica en `proxmox/bin/check-backups.sh` (y copiarlo a
`/usr/local/sbin/` del host); si el dato es irremplazable, añadir `nvme/k8s/miapp` a `DATASETS` de
`proxmox/bin/restic-offsite.sh` (offsite R2). sanoid y syncoid lo toman solos (`recursive = yes`).

Para datos voluminosos y reemplazables, mismo patrón con `path: /mnt/homelab-storage/miapp` y `storageClassName: ""` en PV y PVC
(ver `cluster/apps/comfyui/02-pv-pvc.yaml`) y export en el bloque `homelab-storage` del mismo archivo.

### 4.5 Base de datos en `homelab-postgres`

Preferir SQLite si la app lo soporta y es de un solo usuario. Si necesita Postgres:

1. Secret del rol (cifrado con SOPS) en el namespace `postgresql`, tipo `kubernetes.io/basic-auth` con `username` y
   `password`; y una copia en el namespace de la app para que esta lea las credenciales.
2. Rol administrado: añadir a `spec.managed.roles` de `cluster/apps/postgresql/00-postgres-cluster.yaml`:

   ```yaml
     managed:
       roles:
         - name: miapp
           ensure: present
           login: true
           passwordSecret:
             name: miapp-db-credentials
   ```

3. Base de datos con el CRD:

   ```yaml
   apiVersion: postgresql.cnpg.io/v1
   kind: Database
   metadata:
     name: miapp
     namespace: postgresql
   spec:
     cluster:
       name: homelab-postgres
     name: miapp
     owner: miapp
   ```

4. La app se conecta a `homelab-postgres-rw.postgresql.svc.cluster.local:5432`, credenciales desde el Secret.
5. Respaldo: CronJob de `pg_dump` como `cluster/apps/immich/05-backup-postgres.yaml` (a `nvme/k8s/backups/postgres`) y
   su línea `chk` en `check-backups.sh`.

Modificar el `Cluster` de CNPG afecta a Immich: aplicar con `kubectl apply -f` solo ese archivo, revisar el diff antes
(`kubectl diff -f`) y confirmar con el usuario.

### 4.6 Respaldo de un PVC `local-path`

Todo PVC `local-path` con algo que no se regenere necesita su CronJob. Copiar un bloque de
`cluster/00-infrastructure/backups/app-config-backup.yaml` (p. ej. `config-backup-pingvin`) y cambiar:
- `metadata.name: config-backup-miapp`, `namespace: miapp`
- `schedule`: siguiente minuto libre de la franja `2:40–2:47` (`timeZone: America/Santiago`)
- `APP: miapp` y `EXCLUDES` (caches, logs, miniaturas regenerables)
- `claimName` del PVC

El script ya copia las SQLite con `.backup` (consistentes con la app corriendo). Añadir `miapp` al bucle
`for a in …` de `proxmox/bin/check-backups.sh` y copiar el script al host. Restaurar: escalar a 0, copiar
`nvme/k8s/backups/apps/miapp/data/` sobre el PVC, `chown -R 1000:1000`, escalar a 1.

### 4.7 Servicio solo por tailnet (administración)

Igual que §4.1 pero **sin `ingress.yml`** y con Service NodePort fijo:

```yaml
spec:
  type: NodePort
  selector:
    app: miapp
  ports:
    - name: http
      port: 8080
      targetPort: http
      nodePort: 30xxx   # libre; ver lista en §1
```

Acceso: `http://k3s-node-0:30xxx`. Documentarlo en la tabla de servicios del `README.md`.

---

## 5. Portar una app existente

### Desde docker-compose

| compose | Kubernetes en este cluster |
|---|---|
| `image: x:latest` | Fijar tag concreto (mirar releases upstream) |
| `environment:` | `env:` del Deployment; valores sensibles → Secret SOPS |
| `env_file: .env` | ConfigMap (no sensibles) + Secret SOPS (sensibles) |
| `volumes: ./config:/config` | PVC `local-path` + respaldo §4.6 |
| `volumes: /mnt/fotos:/photos` | PV estático NFS (§4.4) |
| `ports: "8080:8080"` | Service ClusterIP + Ingress, o NodePort si es privado |
| `depends_on: db` (postgres) | `homelab-postgres` (§4.5); si exige versión/extensión rara, Postgres propio en el ns con PVC `local-path` + dump diario |
| `depends_on: redis` | Deployment `redis:7-alpine` en el mismo ns, sin persistencia, Service ClusterIP |
| `restart: unless-stopped` | Implícito en Deployment |
| `healthcheck:` | `readinessProbe` / `livenessProbe` |
| `user: "1000:1000"` / `PUID`/`PGID` | `securityContext` (imágenes linuxserver: `PUID=1000`, `PGID=1000` por env) |
| `network_mode: host` | Evitar. Si es imprescindible (mDNS, DLNA, AirPrint), ver `cluster/apps/canon-mp250-airprint/` y fijar nodo |
| `privileged: true`, `devices:` | Evitar; GPU → §4.3; otros dispositivos → consultar al usuario |
| `labels: traefik.*` | Ignorar; se reemplaza por el Ingress estándar |
| Varios servicios en un compose | Un Deployment por servicio, todos en el mismo namespace y carpeta |

### Desde un chart de Helm

No hay Helm ni Flux operativo para apps. Renderizar a manifiestos planos y versionarlos:

```bash
helm template miapp repo/chart --version X.Y.Z -n miapp -f values.yml > "$TMPDIR/render.yml"
```

Luego repartir en archivos, quitar lo que no aplica (Ingress con TLS, cert-manager, ServiceMonitor si no hay
Prometheus, PodSecurityPolicy) y adaptar a este documento. Anotar chart y versión en un comentario del
`kustomization.yml` para poder actualizar.

### Señales de que la app no encaja (avisar al usuario antes de seguir)

- Exige alta disponibilidad real o varias réplicas con estado compartido.
- Necesita > 8 GiB de RAM o > 8 GB de VRAM.
- Solo tiene imagen arm64 o solo amd64 con AVX2/x86-64-v3 (node-1 tiene CPU `host`: verificar flags con
  `ssh` a node-1 `grep -o 'avx2' /proc/cpuinfo | head -1`).
- Requiere un dominio propio, puertos públicos no HTTP o UDP desde internet.
- Requiere build de imagen propia (no hay registry).

---

## 6. Cosas fuera del cluster

- **Hostname en otra zona o en el túnel `pibot-webs`**: se hace por API de Cloudflare con el token
  `vault_cloudfare_full_api_token` del vault de Ansible (`ansible/`, contraseña en
  `~/.config/homelab/ansible-vault-pass`). Lo hace el agente; no es tarea del usuario. Subdominios
  `*.danielriquelme.cl` por Traefik no necesitan nada.
- **Datasets/exports en Proxmox**: §4.4. Todo archivo del host se versiona en `proxmox/` (mapa en
  `proxmox/README.md`).
- **Reenvío de puertos en el router** (protocolos no HTTP públicos): lo hace el usuario.

---

## 7. Desplegar

Desde una rama `feat/<app>` (GitHub Flow, `AGENTS.md`):

```bash
# 1. Compila
kubectl kustomize cluster/apps/miapp >/dev/null
# 2. Validación contra el API server (CRDs, campos). Con namespace nuevo, el dry-run de los objetos
#    namespaced falla con «namespaces not found»: crear antes el namespace (paso 4) o usar --dry-run=client
kubectl apply -k cluster/apps/miapp --dry-run=server
# 3. Requisitos externos listos (dataset/export NFS, carpeta en pibot, rol Postgres)
# 4. Secretos primero (el namespace debe existir: aplicar namespace.yml antes si es nuevo)
kubectl apply -f cluster/apps/miapp/namespace.yml
sops -d cluster/apps/miapp/secret.sops.yml | kubectl apply -f -
# 5. App
kubectl apply -k cluster/apps/miapp
kubectl -n miapp rollout status deploy/miapp --timeout=5m
# 6. Verificar
kubectl -n miapp get pods,svc,ingress,pvc
kubectl -n miapp logs deploy/miapp --tail=50
curl -sI https://miapp.danielriquelme.cl | head -1     # pública
curl -sI http://k3s-node-0:30xxx | head -1             # tailnet
# 7. Respaldo: lanzar una vez el CronJob y comprobar el destino
kubectl -n miapp create job --from=cronjob/config-backup-miapp backup-prueba
```

Después:
1. Añadir `apps/miapp/` a `cluster/kustomization.yml` y comprobar que `kubectl kustomize cluster` compila.
2. Añadir la fila a la tabla **Servicios** del `README.md` (namespace, acceso, almacenamiento, estado).
3. Commit (`feat(miapp): …`), PR con `gh pr create`, merge con `gh pr merge --merge` apenas funciona.

---

## 8. Checklist «lista para el cluster»

- [ ] Imagen pública con tag fijo, arquitectura compatible con el nodo destino
- [ ] Nodo decidido: libre / `k3s-node-1` (GPU o x86-64-v2) / `pibot` (estático crítico)
- [ ] Config por env, secretos en `*.sops.yml` cifrado con `metadata.namespace`, nada sensible en claro
- [ ] UID 1000, `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`, `readOnlyRootFilesystem` si se puede
- [ ] `requests`/`limits` de memoria; probes HTTP sobre un endpoint barato
- [ ] `strategy: Recreate` si usa PVC RWO o no tolera dos instancias
- [ ] Cada volumen con la opción correcta de §1; ningún `nfs-csi`, ni SQLite en NFS, ni hostPath en workers
- [ ] Todo dato no regenerable tiene respaldo (CronJob + `check-backups.sh`, o dataset `nvme/k8s`)
- [ ] Exposición correcta: Ingress solo si es pública **y** tiene login; si no, NodePort/tailnet o ClusterIP
- [ ] NetworkPolicy deny + permisos mínimos
- [ ] `kubectl kustomize` y `--dry-run=server` limpios
- [ ] Desplegada y verificada; `cluster/kustomization.yml` y `README.md` actualizados; PR mergeado

## 9. Antipatrones vistos en este cluster

- **Ingress «privado»**: no existe; el comodín lo publica. qBittorrent y TrueNAS tuvieron Ingress públicos que hubo que
  quitar (`PENDIENTES.md` §4).
- **`latest`** (heredado en varias apps antiguas): no copiarlo en apps nuevas.
- **Contraseña en el manifiesto** (Immich la tuvo en `DB_URL`): siempre `secretKeyRef`.
- **App Python/ML en node-2/3**: falla con `NumPy was built with baseline optimizations (X86_V2)`.
- **Sitio que «debería» sobrevivir a Proxmox pero usa NFS, Traefik o CoreDNS**: no sobrevive.
- **Datos sin respaldo en `local-path`**: el disco de la VM no tiene snapshots ni vzdump de esos datos.
- **Componentes aplicados a mano sin manifiesto** (Grafana en ns `grafana`): todo lo desplegado tiene que estar en el
  repo.
