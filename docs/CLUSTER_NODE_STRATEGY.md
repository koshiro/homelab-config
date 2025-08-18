# 🏗️ Estrategia de Distribución de Nodos - Cluster Homelab

## 📋 **Resumen Ejecutivo**

Este documento define la estrategia probada y documentada para distribuir aplicaciones en nuestro cluster K3s de 3 nodos, optimizando el uso de recursos y manteniendo alta disponibilidad.

## 🎯 **Arquitectura de Nodos**

### **k3s-node-1 (Control-Plane + GPU)**
- **Rol**: Control-plane, etcd, master
- **Recursos Especiales**: GPU NVIDIA
- **Aplicaciones Dedicadas**: Plex (requiere GPU)
- **Almacenamiento**: NFS principal (`/mnt/homelab-storage`)

### **k3s-node-2 (Nodo P2P)**
- **Rol**: Nodo de trabajo especializado
- **Label**: `p2p: "true"`
- **Aplicaciones Dedicadas**: qBittorrent, Transmission
- **Almacenamiento**: NFS SSD (`/mnt/homelab-ssd`)

### **k3s-node-3 (Nodo de Trabajo General)**
- **Rol**: Nodo de trabajo general
- **Aplicaciones**: Radarr, Sonarr, Bazarr, Overseerr
- **Almacenamiento**: NFS principal (`/mnt/homelab-storage`)

## 🔧 **Estrategias de Distribución**

### **1. Node Selectors (Específicos)**
```yaml
# Para aplicaciones que requieren recursos específicos
nodeSelector:
  kubernetes.io/hostname: k3s-node-1  # GPU
  # o
  p2p: "true"  # Nodo P2P
```

### **2. Pod Topology Spread (Distribución Automática)**
```yaml
# Para aplicaciones que deben distribuirse automáticamente
topologySpreadConstraints:
- maxSkew: 1
  topologyKey: kubernetes.io/hostname
  whenUnsatisfiable: DoNotSchedule
  labelSelector:
    matchLabels:
      app: radarr
```

### **3. Taints y Tolerations (Control Fino)**
```yaml
# En el nodo
taints:
- key: p2p
  value: "true"
  effect: NoSchedule

# En el pod
tolerations:
- key: "p2p"
  operator: "Equal"
  value: "true"
  effect: "NoSchedule"
```

### **4. Anti-Affinity (Evitar Concentración)**
```yaml
# Evitar que múltiples instancias se ejecuten en el mismo nodo
podAntiAffinity:
  preferredDuringSchedulingIgnoredDuringExecution:
  - weight: 100
    podAffinityTerm:
      labelSelector:
        matchExpressions:
        - key: app
          operator: In
          values:
          - qbittorrent
      topologyKey: kubernetes.io/hostname
```

## 📊 **Matriz de Aplicaciones por Nodo**

| Aplicación | Nodo | Razón | Storage | Estado |
|------------|------|-------|---------|---------|
| Plex | k3s-node-1 | GPU requerida | nfs-csi | ✅ Funcionando |
| qBittorrent | k3s-node-2 | Nodo P2P dedicado | hostPath | ✅ Funcionando |
| Radarr | Auto-distribuido | Sin restricciones | nfs-csi | ✅ Funcionando |
| Sonarr | Auto-distribuido | Sin restricciones | nfs-csi | ✅ Funcionando |
| Bazarr | Auto-distribuido | Sin restricciones | nfs-csi | ✅ Funcionando |
| Overseerr | Auto-distribuido | Sin restricciones | nfs-csi | ✅ Funcionando |

## 🔧 **Implementación Actual (Funcionando)**

### **qBittorrent en k3s-node-2:**
```yaml
# Solución documentada: hostPath directo
volumes:
- name: qbittorrent-config
  hostPath:
    path: /mnt/qbittorrent-config
    type: DirectoryOrCreate
- name: qbittorrent-downloads
  hostPath:
    path: /mnt/qbittorrent-downloads
    type: DirectoryOrCreate

nodeSelector:
  p2p: "true"  # Se ejecuta en k3s-node-2
```

### **Configuración de red:**
- **IP del nodo P2P**: `192.168.1.132`
- **NodePort TCP**: `31681` → `6881`
- **NodePort UDP**: `31682` → `6881`
- **Portforwarding**: Configurar en router para puerto 6881

### **Monitorización (kube-prometheus-stack + k3s)**
- Persistencia:
  - `Grafana` y `Prometheus` usan `StorageClass: local-path` (NVMe en Proxmox) para alto rendimiento.
- Exposición de Grafana:
  - `Ingress` estándar Traefik (`grafana.danielriquelme.cl`) gestionado por Cloudflared.
- Exporters adicionales:
  - `pve-exporter` (Proxmox) con credenciales via Secret y `ServiceMonitor`.
  - `speedtest-exporter` con `ServiceMonitor` (intervalo 2m, timeout 90s) y dashboard autoprovisto.
- k3s control-plane scraping:
  - En `k3s-node-1` se añadió en `/etc/rancher/k3s/config.yaml`:
    - `kube-controller-manager-arg`: `bind-address=0.0.0.0`, `secure-port=10257`.
    - `kube-scheduler-arg`: `bind-address=0.0.0.0`, `secure-port=10259`.
  - Se deshabilita `kubeProxy` en el chart (no aplica en k3s).
  - En el `HelmRelease` se definen `endpoints` para `kubeControllerManager` y `kubeScheduler` apuntando a `192.168.1.131` (nodo control-plane), con `scheme: https` y `insecureSkipVerify: true`.

## 🚀 **Beneficios de esta Estrategia**

1. **✅ Alta Disponibilidad**: Las aplicaciones se distribuyen automáticamente
2. **✅ Optimización de Recursos**: GPU y P2P en nodos dedicados
3. **✅ Escalabilidad**: Fácil agregar nuevos nodos
4. **✅ Mantenimiento**: Pods se pueden mover sin interrumpir servicios
5. **✅ Performance**: Aplicaciones P2P en nodo dedicado
6. **✅ Simplicidad**: hostPath elimina complejidad de StorageClasses
7. **✅ Control**: Distribución predecible y controlada

## 📝 **Implementación**

Esta estrategia se implementa gradualmente:
1. ✅ Configurar labels y taints en nodos
2. ✅ Aplicar nodeSelectors específicos (Plex, qBittorrent)
3. ✅ Implementar hostPath para storage local en nodos dedicados
4. ✅ Monitorear y ajustar distribución
5. ✅ Documentar configuración de portforwarding
