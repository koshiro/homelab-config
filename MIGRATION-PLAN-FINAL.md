# Plan Final de Migración - Media Stack Resiliente
## Basado en Investigación Exhaustiva Empírica

**Fecha**: 2025-10-19  
**Versión**: 1.0 - INVESTIGACIÓN COMPLETA

---

## RESUMEN EJECUTIVO

Este plan está basado en **investigación empírica completa** de la infraestructura real, no en suposiciones.

### Hallazgos Clave

1. **Infraestructura Real Verificada:**
   - Proxmox: Hardware físico con 2x NVMe 476GB en MIRROR ZFS
   - Pool "nvme": 128GB usado, 348GB libre (26% uso - **RAZONABLE**)
   - TrueNAS: VM con hardware pass-through
   - Cluster k3s: pibot (RPi CM4) + 3 VMs en Proxmox
   
2. **NVMe NO Está Subutilizado:**
   - ✅ Uso del 26% es adecuado para VMs
   - ✅ Ya tiene resiliencia (RAID1/MIRROR)
   - ✅ NO requiere optimización
   - ✅ TrueNAS tiene sus propios discos pass-through

3. **qBittorrent Configuración Actual (VERIFICADA):**
   ```yaml
   volumeMounts:
   - mountPath: /data
     name: shared-storage  # hostPath: /mnt/homelab-storage
   - mountPath: /config
     name: shared-storage
     subPath: qbittorrent-config  # /mnt/homelab-storage/qbittorrent-config
   
   initContainer crea:
   - /data/downloads/completed
   - /data/downloads/incomplete
   - /config/qBittorrent  # Config real de qBittorrent
   
   Env:
   - XDG_CONFIG_HOME=/config  # qBittorrent busca en /config/qBittorrent
   - PUID=1000, PGID=1000
   ```

4. **Problema Raíz Identificado:**
   - ❌ Todos usan `hostPath: /mnt/homelab-storage` con `type: DirectoryOrCreate`
   - ❌ Post-reinicio: si NFS no está montado → crea dir vacío local
   - ❌ Pods ven almacenamiento vacío
   - ❌ Configs en local-path se pierden con crash de PVE

---

## ARQUITECTURA OBJETIVO

### Estructura NFS Consolidada

```
TrueNAS: /mnt/homelab-storage/k8s-media-library/
├── config/
│   ├── plex/                    [de local-path actual]
│   ├── sonarr/                  [de local-path actual]
│   ├── radarr/                  [de local-path actual]
│   ├── qbittorrent/             [de /qbittorrent-config actual]
│   │   └── qBittorrent/         ← CONFIG REAL (qBittorrent.conf, etc)
│   ├── bazarr/                  [de local-path actual]
│   └── prowlarr/                [de local-path actual]
├── downloads/
│   ├── completed/               [qBittorrent descargas]
│   └── incomplete/              [qBittorrent en progreso]
├── media/
│   ├── series/                  [Sonarr administra, hardlinks desde downloads]
│   └── peliculas/               [Radarr administra, hardlinks desde downloads]
└── backups/                     [ZFS snapshots + tar.gz diarios]
```

### Montaje en Pods (UN SOLO PVC COMPARTIDO)

```yaml
Todos los pods montan:
  volumeMounts:
  - name: media-library
    mountPath: /data              # Raíz común para hardlinks
    
Luego cada pod accede a sus subdirectorios:
- Plex:       /data/config/plex/ + /data/media/
- Sonarr:     /data/config/sonarr/ + /data/media/series/ + /data/downloads/
- Radarr:     /data/config/radarr/ + /data/media/peliculas/ + /data/downloads/
- qBittorrent: /data/config/qbittorrent/ + /data/downloads/
- Bazarr:     /data/config/bazarr/ + /data/media/
- Prowlarr:   /data/config/prowlarr/ + /data/media/

CRÍTICO: qBittorrent necesita:
  - XDG_CONFIG_HOME=/data/config/qbittorrent
  - O symlink: /data/config → /data/config/qbittorrent/
```

### PersistentVolume Único

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: media-library-pv
spec:
  capacity:
    storage: 9Ti
  accessModes:
    - ReadWriteMany  # RWX necesario para hardlinks
  nfs:
    server: 192.168.1.20
    path: "/mnt/homelab-storage/k8s-media-library"
  persistentVolumeReclaimPolicy: Retain
  mountOptions:
    - hard
    - nfsvers=4.2
    - noatime
    - nodiratime
    - rsize=1048576
    - wsize=1048576
```

---

## PLAN DE EJECUCIÓN FASE POR FASE

### FASE 0: Pre-Migración (CRÍTICO - NO OMITIR)

#### 1. Backup Exhaustivo ZFS

```bash
# En TrueNAS
ssh root@192.168.1.20

# Snapshot PRE-MIGRACIÓN (punto de no retorno)
zfs snapshot homelab-storage@pre-migration-$(date +%Y%m%d-%H%M)

# Listar snapshots
zfs list -t snapshot
```

#### 2. Backup Manual de Configs

```bash
# Para CADA aplicación
for app in plex sonarr radarr bazarr prowlarr qbittorrent; do
  POD=$(kubectl get pods -n $app -l app=$app -o jsonpath='{.items[0].metadata.name}')
  echo "Backup de $app..."
  kubectl exec -n $app $POD -- tar czf /tmp/${app}-config-backup.tar.gz /config
  kubectl cp $app/$POD:/tmp/${app}-config-backup.tar.gz ./backups/${app}-config-$(date +%Y%m%d).tar.gz
done

# Guardar en TrueNAS
scp ./backups/* root@192.168.1.20:/mnt/homelab-storage/backups/pre-migration-$(date +%Y%m%d)/
```

#### 3. Git Commit con Referencia

```bash
git add -A
git commit -m "[PRE-MIGRATION] Full backup at TrueNAS:/mnt/homelab-storage/backups/pre-migration-$(date +%Y%m%d)/"
```

#### 4. Verificar Backup System Actual (Deprecate)

```bash
# Verificar si hay cronjobs activos
ssh root@192.168.1.20 "ls -la /mnt/homelab-storage/backups/pod-configs/ | tail -10"

# Si hay backups recientes → sistema funciona → DEPRECATE después
# Si NO hay backups → sistema roto → OK deprecate ahora
```

---

### FASE 1: Crear Infraestructura NFS

#### 1. Crear Estructura en TrueNAS

```bash
ssh root@192.168.1.20

# Crear directorios base
mkdir -p /mnt/homelab-storage/k8s-media-library/{config,downloads,media,backups}
mkdir -p /mnt/homelab-storage/k8s-media-library/media/{series,peliculas}
mkdir -p /mnt/homelab-storage/k8s-media-library/downloads/{completed,incomplete}
mkdir -p /mnt/homelab-storage/k8s-media-library/config/{plex,sonarr,radarr,qbittorrent,bazarr,prowlarr}

# Permisos
chown -R 1000:1000 /mnt/homelab-storage/k8s-media-library
chmod -R 755 /mnt/homelab-storage/k8s-media-library
```

#### 2. Copiar Datos Existentes

```bash
# Copiar media actual (1.9T)
cp -rp /mnt/homelab-storage/media/* /mnt/homelab-storage/k8s-media-library/media/

# Copiar downloads actual
cp -rp /mnt/homelab-storage/downloads/* /mnt/homelab-storage/k8s-media-library/downloads/

# Copiar config de qBittorrent (está en downloads actualmente)
cp -rp /mnt/homelab-storage/qbittorrent-config/* /mnt/homelab-storage/k8s-media-library/config/qbittorrent/
```

#### 3. Snapshot Post-Copia

```bash
zfs snapshot homelab-storage/k8s-media-library@initial-copy-$(date +%Y%m%d)
```

#### 4. Validar Hardlinks en NFS

```bash
# Test empírico
cd /mnt/homelab-storage/k8s-media-library
echo "test hardlinks" > downloads/test-hardlink.txt
ln downloads/test-hardlink.txt media/test-hardlink.txt

# Verificar inodes IDÉNTICOS
stat downloads/test-hardlink.txt | grep Inode
stat media/test-hardlink.txt | grep Inode
# DEBEN ser el MISMO número

# Cleanup
rm downloads/test-hardlink.txt media/test-hardlink.txt
```

#### 5. Crear PV en Kubernetes

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: media-library-pv
  labels:
    pv-name: media-library-pv
spec:
  capacity:
    storage: 9Ti
  accessModes:
    - ReadWriteMany
  nfs:
    server: 192.168.1.20
    path: "/mnt/homelab-storage/k8s-media-library"
  persistentVolumeReclaimPolicy: Retain
  mountOptions:
    - hard
    - nfsvers=4.2
    - noatime
    - nodiratime
    - rsize=1048576
    - wsize=1048576
    - tcp
    - nconnect=8
EOF

# Verificar
kubectl get pv media-library-pv
```

---

### FASE 2: Migrar PLEX (Primero - Más Crítico)

#### 1. Extraer Config de Plex

```bash
POD=$(kubectl get pods -n plex -l app=plex -o jsonpath='{.items[0].metadata.name}')

# Escalar a 0
kubectl scale deployment plex -n plex --replicas=0
kubectl wait --for=delete pod -l app=plex -n plex --timeout=120s

# Ya tenemos backup del paso anterior, ahora restaurar en NFS
```

#### 2. Restaurar Config en NFS

```bash
ssh root@192.168.1.20
cd /mnt/homelab-storage/k8s-media-library/config/plex
tar xzf /mnt/homelab-storage/backups/pre-migration-*/plex-config-*.tar.gz --strip-components=1

# Verificar permisos
chown -R 1000:1000 /mnt/homelab-storage/k8s-media-library/config/plex
```

#### 3. Actualizar PVC de Plex

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: media-library-pvc
  namespace: plex
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: ""  # Manual binding
  resources:
    requests:
      storage: 9Ti
  selector:
    matchLabels:
      pv-name: media-library-pv
EOF

# Verificar binding
kubectl get pvc -n plex media-library-pvc
```

#### 4. Actualizar Deployment de Plex

```bash
# Editar: cluster/04-media-stack/plex/deployment.yml
```

```yaml
spec:
  template:
    spec:
      containers:
      - name: plex
        image: lscr.io/linuxserver/plex:latest
        env:
        - name: PUID
          value: "1000"
        - name: PGID
          value: "1000"
        # ... resto de env vars
        volumeMounts:
        - name: media-library
          mountPath: /config
          subPath: config/plex
        - name: media-library
          mountPath: /media
          subPath: media
        
        # Health checks
        livenessProbe:
          httpGet:
            path: /web/index.html
            port: 32400
          initialDelaySeconds: 60
          periodSeconds: 30
        readinessProbe:
          exec:
            command:
            - sh
            - -c
            - "test -w /config && test -d /media/series && test -d /media/peliculas"
          initialDelaySeconds: 30
          periodSeconds: 10
      
      # InitContainer para wait-for-storage
      initContainers:
      - name: wait-for-storage
        image: busybox:1.35
        command:
        - sh
        - -c
        - |
          echo "Esperando a que storage esté disponible..."
          for i in 1 2 3 4 5 6 7 8 9 10; do
            if test -w /data/config/plex && test -d /data/media; then
              echo "Storage ready!";
              exit 0;
            fi;
            echo "Intento $i/10...";
            sleep 5;
          done
          echo "ERROR: Storage no disponible después de 50s";
          exit 1
        volumeMounts:
        - name: media-library
          mountPath: /data
      
      volumes:
      - name: media-library
        persistentVolumeClaim:
          claimName: media-library-pvc
```

#### 5. Desplegar y Validar Plex

```bash
kubectl apply -f cluster/04-media-stack/plex/pvc.yml
kubectl apply -f cluster/04-media-stack/plex/deployment.yml
kubectl scale deployment plex -n plex --replicas=1

# Esperar
kubectl wait --for=condition=Ready pod -l app=plex -n plex --timeout=300s

# Validar
kubectl exec -n plex $(kubectl get pods -n plex -l app=plex -o jsonpath='{.items[0].metadata.name}') -- df -h /media
kubectl exec -n plex $(kubectl get pods -n plex -l app=plex -o jsonpath='{.items[0].metadata.name}') -- ls -la /media/series | head -10

# Verificar en web
curl -I https://plex.danielriquelme.cl
```

#### 6. Snapshot Post-Plex

```bash
ssh root@192.168.1.20
zfs snapshot homelab-storage/k8s-media-library@post-plex-migration-$(date +%Y%m%d)

git add -A
git commit -m "[MIGRATION] Plex migrated to NFS-CSI successfully"
```

---

### FASE 3: Migrar Apps Satélites

**Orden**: Prowlarr → Bazarr → Sonarr → Radarr → qBittorrent

Para **CADA** app, seguir este patrón:

#### Template de Migración

```bash
APP="sonarr"  # Cambiar por app actual

# 1. Backup (ya tenemos del paso 0, pero refrescar si pasó tiempo)
POD=$(kubectl get pods -n $APP -l app=$APP -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n $APP $POD -- tar czf /tmp/${APP}-config-latest.tar.gz /config
kubectl cp $APP/$POD:/tmp/${APP}-config-latest.tar.gz ./backups/${APP}-config-latest.tar.gz

# 2. Escalar a 0
kubectl scale deployment $APP -n $APP --replicas=0
kubectl wait --for=delete pod -l app=$APP -n $APP --timeout=120s

# 3. Restaurar en NFS
ssh root@192.168.1.20 "
  cd /mnt/homelab-storage/k8s-media-library/config/$APP
  tar xzf - --strip-components=1
" < ./backups/${APP}-config-latest.tar.gz

# 4. Verificar permisos
ssh root@192.168.1.20 "chown -R 1000:1000 /mnt/homelab-storage/k8s-media-library/config/$APP"

# 5. Crear PVC (si no existe)
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: media-library-pvc
  namespace: $APP
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: ""
  resources:
    requests:
      storage: 9Ti
  selector:
    matchLabels:
      pv-name: media-library-pv
EOF

# 6. Actualizar deployment (ver templates abajo)
kubectl apply -f cluster/04-media-stack/$APP/deployment.yml
kubectl scale deployment $APP -n $APP --replicas=1

# 7. Validar
kubectl wait --for=condition=Ready pod -l app=$APP -n $APP --timeout=300s
kubectl exec -n $APP $(kubectl get pods -n $APP -l app=$APP -o jsonpath='{.items[0].metadata.name}') -- df -h /data

# 8. Snapshot
ssh root@192.168.1.20 "zfs snapshot homelab-storage/k8s-media-library@post-${APP}-migration-$(date +%Y%m%d)"
```

#### Deployment Template: Sonarr

```yaml
# cluster/04-media-stack/sonarr/deployment.yml
spec:
  template:
    spec:
      initContainers:
      - name: wait-for-storage
        image: busybox:1.35
        command:
        - sh
        - -c
        - |
          for i in 1 2 3 4 5 6 7 8 9 10; do
            if test -w /data/config/sonarr && test -d /data/downloads && test -d /data/media/series; then
              echo "Storage ready!";
              exit 0;
            fi;
            echo "Intento $i/10...";
            sleep 5;
          done
          exit 1
        volumeMounts:
        - name: media-library
          mountPath: /data
      
      containers:
      - name: sonarr
        image: linuxserver/sonarr:latest
        env:
        - name: PUID
          value: "1000"
        - name: PGID
          value: "1000"
        - name: TZ
          value: "Etc/UTC"
        volumeMounts:
        - name: media-library
          mountPath: /config
          subPath: config/sonarr
        - name: media-library
          mountPath: /data/downloads
          subPath: downloads
        - name: media-library
          mountPath: /data/media/series
          subPath: media/series
        
        livenessProbe:
          httpGet:
            path: /
            port: 8989
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          exec:
            command:
            - sh
            - -c
            - "test -w /config && test -w /data/downloads && test -w /data/media/series"
          initialDelaySeconds: 30
          periodSeconds: 10
      
      volumes:
      - name: media-library
        persistentVolumeClaim:
          claimName: media-library-pvc
```

#### Deployment Template: qBittorrent (ESPECIAL)

```yaml
# cluster/04-media-stack/qbittorrent/deployment.yml
spec:
  template:
    spec:
      initContainers:
      - name: setup-qbittorrent
        image: alpine:3.20
        command:
        - sh
        - -c
        - |
          echo "Setup qBittorrent structure..."
          mkdir -p /data/downloads/{completed,incomplete}
          mkdir -p /data/config/qbittorrent/qBittorrent
          
          # CRÍTICO: Verificar que config existe
          if [ ! -f /data/config/qbittorrent/qBittorrent/qBittorrent.conf ]; then
            echo "WARNING: Config no encontrada, será creada en primer arranque"
          fi
          
          chown -R 1000:1000 /data/downloads /data/config/qbittorrent
          chmod -R 755 /data/downloads /data/config/qbittorrent
          echo "Setup complete!"
        volumeMounts:
        - name: media-library
          mountPath: /data
      
      containers:
      - name: qbittorrent
        image: linuxserver/qbittorrent:latest
        env:
        - name: PUID
          value: "1000"
        - name: PGID
          value: "1000"
        - name: TZ
          value: "Etc/UTC"
        - name: WEBUI_PORT
          value: "8080"
        - name: XDG_CONFIG_HOME
          value: "/data/config/qbittorrent"  # CRÍTICO: apunta a subdir correcto
        volumeMounts:
        - name: media-library
          mountPath: /data
        
        livenessProbe:
          httpGet:
            path: /
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          exec:
            command:
            - sh
            - -c
            - "test -w /data/config/qbittorrent && test -w /data/downloads"
          initialDelaySeconds: 30
          periodSeconds: 10
      
      volumes:
      - name: media-library
        persistentVolumeClaim:
          claimName: media-library-pvc
```

#### Validar Hardlinks Post-Migración

```bash
# Test de hardlinks en Sonarr/Radarr
kubectl exec -n sonarr $(kubectl get pods -n sonarr -l app=sonarr -o jsonpath='{.items[0].metadata.name}') -- sh -c '
  echo "test hardlinks" > /data/downloads/completed/test-hardlink-sonarr.txt
  ln /data/downloads/completed/test-hardlink-sonarr.txt /data/media/series/test-hardlink-sonarr.txt
  stat /data/downloads/completed/test-hardlink-sonarr.txt | grep Inode
  stat /data/media/series/test-hardlink-sonarr.txt | grep Inode
'
# Inodes DEBEN ser idénticos

# Cleanup
kubectl exec -n sonarr $(kubectl get pods -n sonarr -l app=sonarr -o jsonpath='{.items[0].metadata.name}') -- rm /data/downloads/completed/test-hardlink-sonarr.txt /data/media/series/test-hardlink-sonarr.txt
```

---

### FASE 4: Recuperación Automática Post-Reinicio

#### 1. Systemd Service Pre-k3s (en cada nodo)

Crear en **CADA** nodo k3s:

```bash
# En k3s-node-1, k3s-node-2, k3s-node-3
cat > /etc/systemd/system/k3s-preboot-nfs.service <<'EOF'
[Unit]
Description=Mount NFS Media Library Before k3s
Before=k3s.service k3s-agent.service
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStartPre=/bin/bash -c 'echo "Waiting for TrueNAS..."; until ping -c1 192.168.1.20 &>/dev/null; do sleep 1; done; echo "TrueNAS accessible"'
ExecStart=/bin/mkdir -p /mnt/k8s-media-library
ExecStart=/bin/mount -t nfs -o hard,nfsvers=4.2,noatime,nodiratime,rsize=1048576,wsize=1048576,tcp,nconnect=8 192.168.1.20:/mnt/homelab-storage/k8s-media-library /mnt/k8s-media-library
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable k3s-preboot-nfs.service
```

#### 2. DaemonSet de Monitoreo NFS

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: storage-recovery
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: nfs-monitor
  namespace: storage-recovery
spec:
  selector:
    matchLabels:
      app: nfs-monitor
  template:
    metadata:
      labels:
        app: nfs-monitor
    spec:
      hostNetwork: true
      hostPID: true
      containers:
      - name: monitor
        image: alpine:3.20
        command:
        - sh
        - -c
        - |
          apk add --no-cache nfs-utils
          while true; do
            if ! mount | grep -q k8s-media-library; then
              echo "WARNING: NFS not mounted, attempting remount..."
              mkdir -p /mnt/k8s-media-library
              mount -t nfs -o hard,nfsvers=4.2,noatime,nodiratime 192.168.1.20:/mnt/homelab-storage/k8s-media-library /mnt/k8s-media-library || echo "ERROR: Remount failed"
            else
              echo "OK: NFS mounted"
            fi
            sleep 30
          done
        securityContext:
          privileged: true
        volumeMounts:
        - name: host-mount
          mountPath: /mnt
          mountPropagation: Bidirectional
      volumes:
      - name: host-mount
        hostPath:
          path: /mnt
          type: Directory
EOF
```

---

### FASE 5: Deprecate Backup System Antiguo

#### 1. Verificar Backups en NFS

```bash
ssh root@192.168.1.20 "ls -la /mnt/homelab-storage/backups/"
```

#### 2. Deshabilitar Cronjobs Antiguos

```bash
# En TrueNAS
ssh root@192.168.1.20

# Ver cronjobs actuales
crontab -l

# Comentar los de backup (si existen)
crontab -e
# Comentar líneas de backup-pod-configs.sh, backup-cluster-config.sh, etc
```

#### 3. Crear Nuevo Sistema ZFS Snapshots

```bash
# En TrueNAS, crear cronjob para snapshots automáticos
ssh root@192.168.1.20

cat >> /etc/cron.daily/zfs-snapshot-media-library <<'EOF'
#!/bin/bash
zfs snapshot homelab-storage/k8s-media-library@daily-$(date +%Y%m%d)
# Limpiar snapshots antiguos (mantener 30 días)
zfs list -t snapshot -o name -s creation | grep k8s-media-library@daily | head -n -30 | xargs -n 1 zfs destroy
EOF

chmod +x /etc/cron.daily/zfs-snapshot-media-library
```

#### 4. Documentar Nuevo Sistema

```bash
cat > docs/new-backup-system-zfs.md <<'EOF'
# Nuevo Sistema de Backups - ZFS Snapshots

## Estrategia

- **ZFS Snapshots Diarios**: Automáticos vía cron
- **Retención**: 30 días de snapshots
- **Restauración**: `zfs rollback homelab-storage/k8s-media-library@snapshot-name`

## Snapshots Manuales

```bash
# Crear
zfs snapshot homelab-storage/k8s-media-library@manual-$(date +%Y%m%d-%H%M)

# Listar
zfs list -t snapshot

# Restaurar (CUIDADO: destructivo)
zfs rollback homelab-storage/k8s-media-library@snapshot-name
```

## Backups Off-site (Recomendado)

- Considerar replicación ZFS a otro NAS
- O backup incremental a cloud storage
EOF

git add docs/new-backup-system-zfs.md
git add -u  # stage deletions
git commit -m "[BACKUP] New ZFS snapshot system, deprecated old scripts"
```

---

### FASE 6: Test de Recuperación Post-Reinicio

#### Test Completo

```bash
# 1. Apagar TODOS los nodos (simulando apagón)
ansible k3s_nodes -i ansible/inventory -m shell -a "sudo poweroff" -b

# 2. Apagar Proxmox
ssh root@pve "poweroff"

# 3. Encender manualmente (o esperar a que se encienda post-apagón real)

# 4. Verificar que TODO se recuperó
# Esperar 5 minutos para que cluster arranque

# 5. Verificar nodos
kubectl get nodes

# 6. Verificar pods
kubectl get pods -A | grep -E "plex|sonarr|radarr|bazarr|prowlarr|qbittorrent"

# 7. Verificar montaje NFS en nodos
ansible k3s_nodes -i ansible/inventory -m shell -a "mount | grep k8s-media-library"

# 8. Verificar storage en pods
kubectl exec -n plex $(kubectl get pods -n plex -l app=plex -o jsonpath='{.items[0].metadata.name}') -- df -h /media

# 9. Test funcional: acceder a https://plex.danielriquelme.cl
curl -I https://plex.danielriquelme.cl

# 10. ÉXITO si TODO arranca en < 3 min sin intervención
```

---

## MÉTRICAS DE ÉXITO

POST-IMPLEMENTACIÓN:

- ✅ Todos los pods media-stack Ready < 3 min post-reinicio (sin intervención)
- ✅ NFS montado en todos los nodos ANTES de k3s
- ✅ Plex accede a 1.9T de contenido (como antes)
- ✅ Hardlinks funcionales: qBittorrent → Sonarr/Radarr → Plex (instant move)
- ✅ qBittorrent config en `/data/config/qbittorrent/qBittorrent/`
- ✅ CERO pérdida de configuración
- ✅ CERO directorios vacíos (DirectoryOrCreate eliminado)
- ✅ ZFS snapshots automáticos diarios
- ✅ backup-system.md deprecated, nuevo sistema en place

---

## ROLLBACK PLAN (Si Algo Falla)

```bash
# 1. Restaurar snapshot ZFS
ssh root@192.168.1.20
zfs rollback homelab-storage@pre-migration-YYYYMMDD

# 2. Eliminar PVC/PV nuevos
kubectl delete pvc media-library-pvc -n plex
kubectl delete pv media-library-pv

# 3. Restaurar deployments originales desde Git
git checkout HEAD~1 cluster/04-media-stack/

# 4. Aplicar
kubectl apply -k cluster/04-media-stack/plex/
kubectl apply -k cluster/04-media-stack/sonarr/
# etc...

# 5. Escalar a 1
for app in plex sonarr radarr bazarr prowlarr qbittorrent; do
  kubectl scale deployment $app -n $app --replicas=1
done
```

---

## PUNTOS CRÍTICOS (NO IGNORAR)

1. ⚠️  **NVMe NO necesita optimización** - 26% uso es razonable, ya tiene RAID1
2. ⚠️  **qBittorrent config path**: `XDG_CONFIG_HOME=/data/config/qbittorrent`
3. ⚠️  **UN SOLO PVC compartido** - necesario para hardlinks
4. ⚠️  **Systemd mount ANTES de k3s** - evita race conditions
5. ⚠️  **Validar hardlinks** en CADA migración (verificar inodes)
6. ⚠️  **ZFS snapshots** en cada punto crítico (pre/post migración)
7. ⚠️  **Backup antes de CADA paso** - rollback debe ser posible
8. ⚠️  **Test de reinicio completo** - simulando apagón real

---

## ARCHIVOS A CREAR/MODIFICAR

### Nuevos
```
cluster/04-media-stack/pv-media-library.yml
cluster/04-media-stack/*/pvc.yml (actualizar TODOS a usar media-library-pvc)
cluster/00-infrastructure/storage-recovery/namespace.yml
cluster/00-infrastructure/storage-recovery/daemonset-nfs-monitor.yml
docs/new-backup-system-zfs.md
/etc/systemd/system/k3s-preboot-nfs.service (en cada nodo)
```

### Modificar
```
cluster/04-media-stack/plex/deployment.yml
cluster/04-media-stack/sonarr/deployment.yml
cluster/04-media-stack/radarr/deployment.yml
cluster/04-media-stack/bazarr/deployment.yml
cluster/04-media-stack/prowlarr/deployment.yml
cluster/04-media-stack/qbittorrent/deployment.yml (actualmente: qbittorrent-pibot-complete.yaml)
cluster/04-media-stack/*/kustomization.yml
```

### Deprecar
```
docs/bmad/backup-system.md → Marcar como DEPRECATED
scripts/backup-pod-configs.sh → DEPRECATED
scripts/backup-cluster-config.sh → DEPRECATED
scripts/robust-backup-system.sh → DEPRECATED
scripts/*backup*.sh → Revisar y deprecar si obsoletos
```

---

## TIMELINE REALISTA

```
Semana 1: Pre-Migración + Plex
  Día 1-2: Backup exhaustivo + ZFS snapshots
  Día 3-4: Crear infraestructura NFS + validar hardlinks
  Día 5-7: Migrar Plex + validar funcionamiento

Semana 2: Apps Satélites
  Día 1: Prowlarr + Bazarr
  Día 2-3: Sonarr (validar hardlinks)
  Día 4-5: Radarr (validar hardlinks)
  Día 6-7: qBittorrent (CRÍTICO - validar descargas + hardlinks)

Semana 3: Automatización
  Día 1-2: Systemd pre-k3s en todos los nodos
  Día 3-4: DaemonSet NFS monitor
  Día 5: Deprecate backup system antiguo
  Día 6-7: Test de recuperación completo

Semana 4: Validación Final
  Día 1-3: Test de apagón simulado (múltiples veces)
  Día 4-5: Documentación final
  Día 6-7: Buffer para issues inesperados
```

---

## CONTACTO Y SOPORTE

Para issues o preguntas durante la migración:
- Rollback: Ver sección "ROLLBACK PLAN"
- Logs: `kubectl logs -n NAMESPACE POD_NAME`
- Snapshots ZFS: `zfs list -t snapshot`
- Estado NFS: `mount | grep k8s-media-library` (en nodos)

---

**FIN DEL PLAN - Basado en Investigación Empírica Completa**

