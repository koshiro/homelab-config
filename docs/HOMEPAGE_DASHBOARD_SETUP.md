# 🏠 Dashboard Homepage para Homelab

## Descripción

Este dashboard centralizado proporciona una vista cómoda de todos los servicios corriendo en tu homelab, incluyendo Proxmox, TrueNAS, Kubernetes y todas las aplicaciones desplegadas. Utiliza [Homepage](https://github.com/gethomepage/homepage) con integración de Tailscale para acceso privado y seguro.

## 🎯 Características

### **Servicios Monitoreados**
- **Infraestructura**: Proxmox, TrueNAS, Kubernetes
- **Medios**: Plex, Sonarr, Radarr, Prowlarr, Bazarr, Overseerr
- **Descargas**: qBittorrent, Transmission
- **Desarrollo**: Gitea, ArgoCD
- **Monitoreo**: Grafana, Prometheus
- **Backup**: Time Machine SMB

### **Widgets Disponibles**
- Estado del sistema (CPU, RAM, disco, red)
- Contenedores Docker en tiempo real
- Pods de Kubernetes con estado
- Métricas de servicios específicos
- Estado de TrueNAS y Proxmox
- Estadísticas de Plex y servicios *arr

### **Seguridad**
- Acceso solo a través de Tailscale
- Políticas de red restrictivas
- Credenciales encriptadas con SOPS
- Sin exposición pública a internet

### **Distribución**
- Se despliega en cualquier nodo del clúster
- Configuración de tolerancias para control-plane y worker nodes
- Anti-affinity para evitar múltiples pods en el mismo nodo
- Escalabilidad horizontal automática

## 🚀 Instalación

### 1. Despliegue Automático

```bash
# Desde el directorio raíz del proyecto
./scripts/setup-homepage-dashboard.sh
```

### 2. Despliegue Manual

```bash
# Aplicar la configuración
kubectl apply -k cluster/homepage/

# Verificar el estado
kubectl get pods -n homepage
kubectl get svc -n homepage
kubectl get ingress -n homepage
```

## 🔧 Configuración

### **Archivos de Configuración**

- `cluster/homepage/configmap-settings.yml` - Configuración principal
- `cluster/homepage/configmap-services.yml` - Servicios del homelab
- `cluster/homepage/configmap-widgets.yml` - Widgets de monitoreo
- `cluster/homepage/configmap-bookmarks.yml` - Enlaces rápidos
- `cluster/homepage/secret-credentials.sops.yml` - Credenciales

### **Variables de Entorno**

```yaml
# Configuración principal
HOMEPAGE_ALLOWED_HOSTS: "homepage.tail*.ts.net,192.168.1.*,10.0.0.*,172.16.0.*"
HOMEPAGE_TITLE: "Homelab Dashboard"
HOMEPAGE_THEME: "dark"
HOMEPAGE_LANGUAGE: "es"

# Credenciales de servicios
TRUENAS_API_KEY: "tu_api_key"

# Proxmox (API Token)
PROXMOX_HOST: "pve"
PROXMOX_USER: "root@pam"
PROXMOX_API_TOKEN_ID: "ansible"
PROXMOX_API_TOKEN_SECRET: "tu_token_secret"

# Tailscale
TAILSCALE_AUTH_KEY: "tu_tailscale_auth_key"

PLEX_TOKEN: "tu_token"
# ... más credenciales
```

### **Configuración de Tailscale**

El dashboard está configurado para ser accesible solo a través de:
- Redes Tailscale (100.64.0.0/10)
- Red local (192.168.1.0/24)
- Redes privadas (10.0.0.0/8, 172.16.0.0/12)

#### **Registro de Nodos en Tailscale**

Para que los nodos del clúster se registren automáticamente en Tailscale:

```bash
# Configurar la clave de autenticación
export TAILSCALE_AUTH_KEY="tu_tailscale_auth_key_aqui"

# Registrar nodos manualmente si es necesario
tailscale up --auth-key="$TAILSCALE_AUTH_KEY" --hostname=k3s-node-1
tailscale up --auth-key="$TAILSCALE_AUTH_KEY" --hostname=k3s-node-2
tailscale up --auth-key="$TAILSCALE_AUTH_KEY" --hostname=k3s-node-3
```

#### **Configuración de DNS en Tailscale**

Para acceder al dashboard a través de Tailscale:

```bash
# Configurar hostname personalizado
tailscale up --hostname=homepage-homelab

# El dashboard estará disponible en:
# https://homepage-homelab.tail*.ts.net
```

## 📱 Acceso

### **URLs de Acceso**

- **Local**: `http://192.168.1.131/homepage`
- **Tailscale**: `https://homepage.tail*.ts.net`
- **Interno**: `http://homepage.homepage.svc.cluster.local:3000`

### **Configuración de DNS**

Para acceder a través de Tailscale, configura un hostname:

```bash
# En tu panel de Tailscale
tailscale up --hostname=homepage-homelab
```

## 🔐 Configuración de Credenciales

### 1. Editar el Archivo de Secretos

```bash
# Editar el archivo de credenciales
vim cluster/homepage/secret-credentials.sops.yml
```

### 2. Configurar API Keys

```yaml
stringData:
  # TrueNAS (ya configurado)
  TRUENAS_API_KEY: "1-W3MgqZZFNYGPVYIHWKLtaXEuWFvkRkbeUi3dHAGUlAlj5dwEzI5cRcG9eCHxSjpV"
  
  # Proxmox (API Token)
  PROXMOX_HOST: "pve"
  PROXMOX_USER: "root@pam"
  PROXMOX_API_TOKEN_ID: "ansible"
  PROXMOX_API_TOKEN_SECRET: "tu_token_secret_real"
  
  # Tailscale
  TAILSCALE_AUTH_KEY: "tu_tailscale_auth_key_real"
  
  # Plex
  PLEX_TOKEN: "tu_plex_token_real"
  
  # Servicios *arr
  SONARR_API_KEY: "tu_sonarr_api_key"
  RADARR_API_KEY: "tu_radarr_api_key"
  # ... más servicios
```

### 3. Encriptar con SOPS

```bash
# Encriptar el archivo
sops -e -i cluster/homepage/secret-credentials.sops.yml

# Aplicar al clúster
kubectl apply -f cluster/homepage/secret-credentials.sops.yml
```

## 🎨 Personalización

### **Temas Disponibles**

- `dark` - Tema oscuro (por defecto)
- `light` - Tema claro
- `auto` - Tema automático según preferencias del sistema

### **Layouts**

- `auto` - Automático según pantalla
- `grid` - Cuadrícula fija
- `list` - Lista vertical

### **Widgets Personalizados**

Puedes agregar widgets personalizados editando `configmap-widgets.yml`:

```yaml
- name: "Mi Widget Personalizado"
  type: custom
  options:
    url: "https://mi-servicio.com/api"
    refreshInterval: 30
```

## 📊 Monitoreo y Logs

### **Ver Logs**

```bash
# Logs del pod principal
kubectl logs -f -l app=homepage -n homepage

# Logs de todos los pods
kubectl logs -f -l app=homepage -n homepage --all-containers
```

### **Estado del Servicio**

```bash
# Verificar estado
kubectl get pods -n homepage
kubectl get svc -n homepage
kubectl get ingress -n homepage

# Verificar eventos
kubectl get events -n homepage --sort-by='.lastTimestamp'
```

### **Métricas**

```bash
# Port-forward para acceso directo
kubectl port-forward -n homepage svc/homepage 3000:3000

# Acceder localmente
open http://localhost:3000
```

## 🔒 Seguridad

### **Políticas de Red**

- Solo permite tráfico desde Traefik
- Restringe acceso a redes privadas
- Bloquea acceso externo directo

### **Autenticación**

- No requiere login (acceso por red privada)
- Protegido por Tailscale
- Credenciales encriptadas

### **Auditoría**

```bash
# Ver políticas de red
kubectl get networkpolicies -n homepage

# Ver secretos
kubectl get secrets -n homepage
```

## 🚨 Troubleshooting

### **Problemas Comunes**

#### 1. Pod no arranca
```bash
# Verificar eventos
kubectl describe pod -l app=homepage -n homepage

# Verificar logs
kubectl logs -l app=homepage -n homepage
```

#### 2. No se puede acceder
```bash
# Verificar servicio
kubectl get svc -n homepage

# Verificar ingress
kubectl get ingress -n homepage

# Verificar políticas de red
kubectl get networkpolicies -n homepage
```

#### 3. Widgets no funcionan
```bash
# Verificar credenciales
kubectl get secret homepage-credentials -n homepage -o yaml

# Verificar logs de errores
kubectl logs -l app=homepage -n homepage | grep -i error
```

### **Comandos de Diagnóstico**

```bash
# Estado completo del namespace
kubectl get all -n homepage

# Verificar configuración
kubectl describe configmap -n homepage

# Verificar conectividad
kubectl exec -it -n homepage deployment/homepage -- curl -s http://localhost:3000
```

## 📚 Recursos Adicionales

### **Documentación Oficial**
- [Homepage GitHub](https://github.com/gethomepage/homepage)
- [Documentación de Homepage](https://gethomepage.dev/)
- [Configuración de Widgets](https://gethomepage.dev/services/overview)

### **Integraciones**
- [Docker Integration](https://gethomepage.dev/services/docker)
- [Kubernetes Integration](https://gethomepage.dev/services/kubernetes)
- [Service Widgets](https://gethomepage.dev/services/overview)

### **Comunidad**
- [Discord de Homepage](https://discord.gg/NFeVqJm2)
- [GitHub Discussions](https://github.com/gethomepage/homepage/discussions)

## 🔄 Actualizaciones

### **Actualizar Homepage**

```bash
# Actualizar imagen
kubectl set image deployment/homepage homepage=ghcr.io/gethomepage/homepage:latest -n homepage

# Verificar rollout
kubectl rollout status deployment/homepage -n homepage
```

### **Actualizar Configuración**

```bash
# Aplicar cambios
kubectl apply -k cluster/homepage/

# Reiniciar para aplicar cambios
kubectl rollout restart deployment/homepage -n homepage
```

---

## 📝 Notas de Implementación

- **Fecha**: Enero 2025
- **Versión**: 1.0.0
- **Estado**: Implementado y funcional
- **Integración**: Tailscale + Kubernetes + Traefik
- **Monitoreo**: Todos los servicios del homelab

Para soporte o preguntas, consulta los logs del sistema o crea un issue en el repositorio.
