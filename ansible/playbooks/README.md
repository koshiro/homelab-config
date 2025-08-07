# 📋 **Estructura de Playbooks - Homelab BMad**

Esta estructura está organizada según los principios del **BMad Master - FitnessBrain Framework** para máxima claridad y mantenibilidad.

## 📁 **Estructura de Directorios**

```
ansible/playbooks/
├── core/                    # Playbooks principales del pipeline de despliegue
│   ├── playbook_bootstrap_server.yml      # Bootstrap inicial de Proxmox
│   ├── playbook_create_vms.yml           # Creación de VMs
│   ├── playbook_initial_truenas_setup.yml # Setup inicial TrueNAS + API Key
│   ├── playbook_configure_truenas.yml    # Configuración completa TrueNAS
│   ├── playbook_configure_cluster.yml    # Instalación k3s (LTS robusta)
│   └── playbook_setup_gitea_ecosystem.yml # Setup Gitea + GitOps completo
├── utils/                   # Utilidades de mantenimiento
│   └── playbook_resize_vm_disks.yml      # Redimensionar discos VMs
└── README.md               # Este archivo
```

## 🎯 **Playbooks Core - Pipeline Principal**

Estos playbooks se ejecutan secuencialmente mediante `ansible/playbook_homelab.yml`:

### **1. Bootstrap Proxmox (`playbook_bootstrap_server.yml`)**
- **Propósito**: Preparar el servidor base
- **Acciones**: Actualizar repos, instalar paquetes, configurar GPU passthrough, Tailscale
- **Tags**: `bootstrap`, `proxmox`

### **2. Crear VMs (`playbook_create_vms.yml`)**
- **Propósito**: Provisionamiento de máquinas virtuales
- **Acciones**: Crear VMs con especificaciones correctas (10GB+ disco)
- **Tags**: `provision`, `vms`

### **3. Setup TrueNAS (`playbook_initial_truenas_setup.yml`)**
- **Propósito**: Configuración inicial automatizada de TrueNAS
- **Acciones**: Crear usuarios, generar API Keys, actualizar variables
- **Tags**: `truenas`, `setup`

### **4. Configurar TrueNAS (`playbook_configure_truenas.yml`)**
- **Propósito**: Configurar almacenamiento compartido
- **Acciones**: Crear datasets, shares NFS, habilitar servicios
- **Tags**: `truenas`, `storage`

### **5. Configurar K3s (`playbook_configure_cluster.yml`)**
- **Propósito**: Instalación robusta del clúster Kubernetes
- **Versión**: k3s v1.31.11+k3s1 (LTS)
- **Características**: 
  - Verificación de espacio en disco
  - Instalación con reintentos
  - Validación completa del clúster
  - Configuración de kubectl
- **Tags**: `k3s`, `cluster`

### **6. Configurar Cloudflare Tunnel (integrado en pipeline principal)**
- **Propósito**: Configuración automática del túnel de Cloudflare
- **Acciones**:
  - Lee credenciales del archivo `.env`
  - Decodifica token del túnel
  - Despliega `cloudflared` pods en k3s
  - Configura ingress para dominio principal
  - **Configura IngressRoute correcto para Traefik Dashboard (HTTPS)**
- **Tags**: `cloudflare`, `tunnel`

### **7. Setup Gitea + GitOps (`playbook_setup_gitea_ecosystem.yml`)**
- **Propósito**: Establecer el ecosistema de desarrollo completo
- **Acciones**: 
  - Configura Gitea (crear repos, tokens)
  - Establece FluxCD para GitOps automático
  - Configura Gitea Actions Runner
  - Revoca tokens por seguridad
- **Tags**: `gitops`, `gitea`

## 🛠️ **Playbooks Utils - Utilidades de Mantenimiento**

### **Redimensionar Discos (`playbook_resize_vm_disks.yml`)**
- **Propósito**: Expandir discos de VMs existentes cuando sea necesario
- **Uso**: `ansible-playbook -i ../inventory utils/playbook_resize_vm_disks.yml`
- **⚠️ Advertencia**: Requiere apagar las VMs temporalmente

## 🚀 **Comandos de Ejecución**

### **Despliegue Completo**
```bash
cd /path/to/homelab-config
ansible-playbook -i ansible/inventory ansible/playbook_homelab.yml
```

### **Ejecución Selectiva con Tags**
```bash
# Solo bootstrap de Proxmox
ansible-playbook -i ansible/inventory ansible/playbook_homelab.yml --tags bootstrap

# Solo k3s
ansible-playbook -i ansible/inventory ansible/playbook_homelab.yml --tags k3s

# Solo TrueNAS
ansible-playbook -i ansible/inventory ansible/playbook_homelab.yml --tags truenas

# Solo Cloudflare Tunnel
ansible-playbook -i ansible/inventory ansible/playbook_homelab.yml --tags cloudflare

# Solo GitOps
ansible-playbook -i ansible/inventory ansible/playbook_homelab.yml --tags gitops
```

### **Utilidades Individuales**
```bash
# Redimensionar discos VMs
ansible-playbook -i ansible/inventory ansible/playbooks/utils/playbook_resize_vm_disks.yml
```

## ⚠️ **Requisitos Críticos**

### **Espacio en Disco**
- **Mínimo absoluto**: 10GB por nodo k3s
- **Recomendado**: 20GB+ para producción
- **Fallo garantizado**: < 8GB espacio libre

### **Red y Conectividad**
- Acceso SSH configurado a Proxmox
- Internet disponible para descargas
- IPs estáticas configuradas en inventory

### **Plantillas de VM**
- Ubuntu Cloud template (ID 9000)
- TrueNAS template (ID 9001)
- Cloud-init configurado correctamente

## 🔍 **Troubleshooting Rápido**

```bash
# Verificar espacio en todos los nodos
ansible k3s_nodes -i ansible/inventory -m shell -a "df -h /"

# Estado del clúster
ssh k3s-node-1 "sudo k3s kubectl get nodes -o wide"

# Limpiar k3s fallido
ansible k3s_nodes -i ansible/inventory -m shell -a "sudo /usr/local/bin/k3s-uninstall.sh || sudo /usr/local/bin/k3s-agent-uninstall.sh" --become

# Conectividad básica
ansible all -i ansible/inventory -m ping
```

---

## 📧 **BMad Master Framework - Organización y Calidad**

Esta estructura sigue los principios del **BMad Master** para:
- ✅ **Claridad**: Cada playbook tiene un propósito específico
- ✅ **Mantenibilidad**: Separación entre core y utils
- ✅ **Robustez**: Validaciones y reintentos incorporados
- ✅ **Documentación**: Todo está documentado y tageado
- ✅ **Escalabilidad**: Fácil añadir nuevos playbooks
