# Homelab: Ecosistema de Desarrollo Autodesplegable

![Estado](https://img.shields.io/badge/Estado-Completamente%20Funcional-brightgreen)
![Orquestación](https://img.shields.io/badge/Orquestación-Kubernetes%20(k3s)-blue)
![Metodología](https://img.shields.io/badge/Metodología-GitOps%20(ArgoCD)%20%2B%20Ansible-informational)

Este repositorio contiene la configuración completa para un centro de datos personal que no solo ejecuta aplicaciones, sino que también proporciona un ecosistema de desarrollo y despliegue continuo (CI/CD) completamente automatizado.

## 🤖 Filosofía de Diseño

*   **Infraestructura como Código (IaC):** Todo, desde la creación de VMs hasta la configuración de aplicaciones, está definido como código en este repositorio.
*   **GitOps como Fuente de la Verdad:** El estado deseado del clúster de Kubernetes se define en un repositorio de Git (`homelab-config`) que vive en GitHub. ArgoCD se encarga de sincronizar el clúster con este repositorio.
*   **CI/CD Integrado:** GitHub Actions se utiliza para construir, probar y desplegar aplicaciones automáticamente. El pipeline de CI/CD actualiza la versión de la imagen en el repositorio `homelab-config`, y ArgoCD se encarga del resto.

## 🏗️ Arquitectura del Ecosistema

El sistema se compone de dos tipos de repositorios:

1.  **`homelab-config` (Este Repositorio):** Contiene la configuración de la infraestructura (Ansible) y los manifiestos de Kubernetes (`/cluster`) que describen el estado deseado del clúster.
2.  **Repositorios de Aplicaciones (ej. `tattoo-app`):** Contienen el código fuente de las aplicaciones. Su pipeline de CI/CD produce imágenes de Docker que se almacenan en el registro de contenedores de GitHub.

El flujo de trabajo es el siguiente:

1.  Un desarrollador hace `push` a un repositorio de aplicación en GitHub.
2.  GitHub Actions construye una nueva imagen de Docker y la sube al registro de GitHub.
3.  GitHub Actions actualiza el manifiesto de la aplicación en el repositorio `homelab-config` con la nueva versión de la imagen.
4.  ArgoCD detecta el cambio en `homelab-config` y despliega la nueva versión de la aplicación en el clúster.

## 🔐 Gestión de Secretos con SOPS

El homelab utiliza **SOPS (Secrets OPerationS)** con claves `age` para la gestión segura de secretos:

- **Encriptación**: Todos los secretos están encriptados con SOPS antes de ser versionados en Git
- **Integración ArgoCD**: KSOPS plugin permite a ArgoCD desencriptar automáticamente los secretos
- **Clave actual**: `age1ga4dqzwv2wrf5c0dduz0vsjkzlda9xzrp787u2mnhhj6zh5qxaws4mlhhs`
- **Respaldos automáticos**: Scripts para respaldar y restaurar claves

### 📚 Documentación SOPS
- **Configuración completa**: [`docs/SOPS_CONFIGURATION.md`](docs/SOPS_CONFIGURATION.md)
- **Guía de recuperación**: [`docs/SOPS_RECOVERY_GUIDE.md`](docs/SOPS_RECOVERY_GUIDE.md)
- **Scripts de respaldo**: [`scripts/backup-sops-keys.sh`](scripts/backup-sops-keys.sh)
- **Scripts de restauración**: [`scripts/restore-sops-keys.sh`](scripts/restore-sops-keys.sh)

### 🔧 Comandos Rápidos SOPS
```bash
# Respaldar claves
./scripts/backup-sops-keys.sh

# Restaurar claves
./scripts/restore-sops-keys.sh

# Encriptar archivo
sops --encrypt secret.yaml > secret.sops.yml

# Desencriptar archivo
sops --decrypt secret.sops.yml
```

## 📊 Monitoreo

### TrueNAS con Prometheus y Grafana

El sistema incluye monitoreo completo de TrueNAS usando:
- **node_exporter** para métricas del sistema
- **Prometheus** para recopilación de métricas
- **Grafana** con dashboard personalizado "TrueNAS System Metrics"

**Características del Dashboard:**
- Uso de CPU, memoria y disco en tiempo real
- Tráfico de red por interfaz
- Alertas configurables (CPU > 80%, Memoria > 80%, Disco > 80%)
- Métricas del sistema operativo de TrueNAS

**Acceso:**
- Grafana: https://grafana.danielriquelme.cl
- Dashboard: TrueNAS System Metrics
- Métricas: `kubectl port-forward -n monitoring svc/truenas-node-exporter 9100:9100`

**Verificación:**
```bash
./scripts/verify-truenas-monitoring.sh
```

Para más detalles, ver [TRUENAS_MONITORING.md](docs/TRUENAS_MONITORING.md).

## 🔄 Sistema de Respaldo Automático

El homelab incluye un sistema completo de respaldos automáticos ejecutándose en TrueNAS:

### 🛡️ Respaldo de Configuraciones Críticas
- **Configuraciones de pods** (Plex, Sonarr, Radarr, etc.) - Respaldo diario
- **Configuración del cluster** Kubernetes - Respaldo diario
- **Configuraciones de infraestructura** (Ansible, K8s manifests) - Respaldo semanal

### 📅 Cronjobs Configurados
| Descripción | Frecuencia | Hora | Prioridad |
|-------------|------------|------|-----------|
| Respaldo de configuraciones de pods | Diario | 03:00 | CRÍTICO |
| Respaldo de configuración del cluster | Diario | 03:30 | ALTO |
| Verificación de salud del sistema | Diario | 04:00 | ALTO |
| Limpieza de logs del sistema | Semanal | 02:00 (dom) | MEDIO |
| Verificación de salud del ZFS | Diario | 05:00 | ALTO |
| Limpieza de snapshots antiguos | Semanal | 01:00 (dom) | MEDIO |
| Verificación del estado del cluster | Cada 6h | 00:00, 06:00, 12:00, 18:00 | ALTO |
| Verificación de conectividad | Cada 4h | 00:00, 04:00, 08:00, 12:00, 16:00, 20:00 | MEDIO |
| Limpieza de archivos temporales | Diario | 06:00 | MEDIO |
| Respaldo de infraestructura | Semanal | 05:00 (dom) | ALTO |

### 🔧 Gestión de Respaldos

**Verificar cronjobs:**
```bash
ssh root@192.168.1.20 'curl -k -s -X GET "https://192.168.1.20/api/v2.0/cronjob" -H "Authorization: Bearer $(cat /root/.truenas-api-key)" | jq'
```

**Verificar respaldos:**
```bash
ssh root@192.168.1.20 'ls -la /mnt/homelab-storage/backups/'
```

**Ejecutar respaldo manual:**
```bash
ssh root@192.168.1.20 '/root/scripts/backup-pod-configs.sh'
```

**Documentación completa:** [Sistema de Respaldos](docs/guides/05_backup_system.md)

---

## 🚀 Guía de Puesta en Marcha (Bootstrap)

Sigue estos pasos para desplegar el homelab desde cero en un servidor con Proxmox recién instalado.

## 🛑 Apagado Ordenado del Cluster

Para mantenimiento de hardware o actualizaciones del sistema, **SIEMPRE** usa el apagado ordenado:

```bash
# Apagado ordenado completo del cluster
ansible-playbook -i inventory ansible/playbooks/maintenance/playbook_graceful_shutdown_cluster.yml
```

**¿Por qué es importante?**
- ✅ **Integridad de datos**: Evita corrupción de archivos NFS
- ✅ **Recuperación rápida**: El cluster se estabiliza más rápido
- ✅ **Prevención de errores**: Evita locks persistentes y problemas de sincronización

**Secuencia del apagado ordenado:**
1. **Cluster Kubernetes**: Drena nodos y evacua pods ordenadamente
2. **TrueNAS**: Detiene servicios (NFS, SMB, SSH, HTTP) via API
3. **VMs**: Apaga VMs de Kubernetes y TrueNAS
4. **Proxmox**: Apaga el host de manera segura

**Para más detalles, ver [GRACEFUL_SHUTDOWN_GUIDE.md](docs/GRACEFUL_SHUTDOWN_GUIDE.md)**

### Prerrequisitos

### Prerrequisitos

**En tu máquina local:**
*   Ansible instalado (`pip install ansible`).
*   Las colecciones de Ansible necesarias:
    ```bash
    ansible-galaxy collection install community.general community.proxmox kubernetes.core
    ```
*   Claves SSH configuradas (se generarán en el paso 4 si no las tienes).

**En tu servidor Proxmox:**
*   Proxmox VE instalado y funcionando.
*   Acceso de red desde tu máquina local.
*   Un token de API de Proxmox (se explica cómo obtenerlo más abajo).
*   Pool ZFS para VMs configurado (se explica en el paso 3).

**Plantillas de VM (requeridas):**
*   ⚠️ **IMPORTANTE:** Necesitas plantillas de VM para TrueNAS y Ubuntu/Debian en Proxmox antes de ejecutar el playbook.
*   Las plantillas deben tener cloud-init configurado para acceso SSH automático.
*   Ver la sección "Preparar Plantillas de VM" más abajo para instrucciones detalladas.

### Pasos de Configuración

1.  **Clonar el Repositorio (en tu máquina local):**
    Este paso se realiza en tu máquina local, desde donde ejecutarás los playbooks de Ansible. Si tu repositorio es privado, asegúrate de tener configuradas las credenciales de Git (por ejemplo, claves SSH o tokens de acceso personal) en tu máquina local.
    ```bash
    git clone https://github.com/tu_usuario/homelab-config.git
    cd homelab-config
    ```
    *   **Nota:** Si ya te encuentras en el directorio `homelab-config` en tu máquina local, puedes omitir este paso.

2.  **Configurar las Variables:**
    *   Copia el fichero de ejemplo:
        ```bash
        cp ansible/vars/homelab_vars.yml.example ansible/vars/homelab_vars.yml
        ```
    *   **Edita `ansible/vars/homelab_vars.yml`** y rellena los valores iniciales. Este es el único fichero que necesitas modificar manualmente al principio. Ten en cuenta que algunos valores, como la `truenas_api_key`, serán actualizados automáticamente por Ansible durante la ejecución del playbook.

3.  **Configurar Credenciales de Cloudflare (.env):**
    *   Copia el archivo de ejemplo:
        ```bash
        cp .env.example .env
        ```
    *   **Edita `.env`** y configura las credenciales de Cloudflare:
        ```bash
        # Dominio principal
        DOMAIN_NAME=tudominio.com
        
        # Token de Cloudflare (permisos: Account → Cloudflare Tunnel: Edit, Zone → DNS: Edit)
        CF_API_TOKEN=tu_api_token_de_cloudflare
        
        # Credenciales del túnel (token base64 exportado desde Cloudflare)
        CLOUDFLARE_TUNNEL_TOKEN=tu_tunnel_token_base64
        ```
    *   **⚠️ Importante:** El túnel de Cloudflare se configura **automáticamente** durante el despliegue usando estas credenciales.

4.  **Instalación de Proxmox y Configuración de Almacenamiento:**
    *   **Instala Proxmox VE** en tu servidor. Durante la instalación, configura el sistema operativo de Proxmox en un **ZFS RAID1 utilizando tus dos SSD SATA (240GB y 120GB)**. Esto proporcionará redundancia para el hipervisor.
    *   Una vez instalado Proxmox, accede a su interfaz web y crea un **nuevo pool ZFS para las VMs utilizando tu NVMe de 512GB**. Nómbralo, por ejemplo, `nvme-vms`. Este pool será el destino de los discos virtuales de tus VMs de Kubernetes. Cuando recibas el segundo NVMe, podrás añadirlo a este pool para crear un espejo.
        Para crear el pool ZFS en Proxmox:
        1.  Accede a la interfaz web de Proxmox (usualmente `https://<IP_PROXMOX>:8006`).
        2.  En el panel izquierdo, selecciona tu nodo Proxmox.
        3.  Ve a la sección **Disks > ZFS**.
        4.  Haz clic en **Create: ZFS**.
        5.  En el campo **Name**, introduce `nvme-vms` (o el nombre que hayas elegido y que coincida con `storage_pool` en `homelab_vars.yml`).
        6.  Selecciona tu NVMe de 512GB en la lista de **Disks**.
        7.  Elige el **RAID Level** apropiado (por ejemplo, `Single Disk` si solo tienes un NVMe, o `RAID1` si ya tienes dos NVMe y quieres un espejo).
        8.  Haz clic en **Create**.

5.  **Configurar Acceso SSH a Proxmox:**
    El playbook necesita conectarse a Proxmox via SSH como usuario `root`. Configura el acceso SSH desde tu máquina local:
    
    ```bash
    # Generar clave SSH si no tienes una
    ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa
    
    # Copiar la clave pública a Proxmox
    ssh-copy-id root@<IP_PROXMOX>
    
    # Verificar que funciona
    ssh root@<IP_PROXMOX>
    ```
    
    **⚠️ Importante:** Solo necesitas configurar SSH para Proxmox en este paso. Las VMs (TrueNAS, k3s nodes) se crearán y configurarán automáticamente durante el despliegue.

### **Acceso Remoto al Clúster con Tailscale (CRÍTICO)**

**Para gestionar el clúster desde fuera de la red local, es imprescindible usar Tailscale.**

- **Conexión**: Asegúrate de que tu cliente de Tailscale esté activo. La conexión a los nodos se debe hacer usando el **MagicDNS** o la **IP de Tailscale** del nodo.
- **Usuario**: El usuario para acceder a los nodos de k3s es `daniel`.

**Ejemplo de Conexión:**
```bash
# Conectar al nodo maestro usando MagicDNS
ssh daniel@pibot

# O usando la IP de Tailscale
ssh daniel@<IP_TAILSCALE_DEL_NODO>
```

6.  **Configurar el Archivo de Inventario:**
    El archivo `ansible/inventory` define cómo Ansible se conecta a tus servidores. 
    
    *   **Edita `ansible/inventory`** y actualiza las direcciones IP para que coincidan con tu red:
        ```ini
        [proxmox_host]
        proxmox ansible_host=TU_IP_DE_PROXMOX
        
        [truenas_vm]
        truenas ansible_host=TU_IP_PARA_TRUENAS
        
        [k3s_nodes]
        k3s-node-1 ansible_host=TU_IP_PARA_NODE1
        k3s-node-2 ansible_host=TU_IP_PARA_NODE2
        k3s-node-3 ansible_host=TU_IP_PARA_NODE3
        ```
    *   **Importante:** Las IPs de las VMs deben estar en el mismo rango de red que Proxmox y ser direcciones libres que no estén en uso.

7.  **Ejecutar el Playbook Principal:**
    Este es un proceso complejo que orquesta la creación de todo el ecosistema. Tardará varios minutos.
    ```bash
    ansible-playbook -i ansible/inventory ansible/playbook_homelab.yml
    ```

    **🚨 IMPORTANTE - Especificaciones Automáticas de VMs:**
    - **k3s nodes**: 30GB de disco cada uno (automático)
    - **TrueNAS**: 32GB de disco + discos passthrough (automático) 
    - **RAM**: 4GB por nodo k3s, 2GB para TrueNAS
    - Todos los discos se crean automáticamente en el storage NVMe configurado

    **¿Qué hace este playbook?**

    El `playbook_homelab.yml` es el orquestador maestro organizado en una estructura limpia de playbooks especializados:

    ## 📁 **Playbooks Core (ansible/playbooks/core/)**

    *   **0. Bootstrap del Servidor Proxmox (`playbook_bootstrap_server.yml`):**
        *   **Propósito:** Prepara el sistema operativo base de tu servidor Proxmox.
        *   **Qué hace:** Actualiza los paquetes del sistema, configura repositorios, instala herramientas esenciales, configura GPU passthrough y Tailscale.

    *   **1. Crear Máquinas Virtuales (`playbook_create_vms.yml`):**
        *   **Propósito:** Provisiona las máquinas virtuales con dimensionamiento adecuado.
        *   **Qué hace:** Crea VMs con **discos de 10GB mínimo**, configura cloud-init, y establece la red. Los discos se crean en el pool ZFS configurado.

    *   **2. Configuración Inicial de TrueNAS (`playbook_initial_truenas_setup.yml`):**
        *   **Propósito:** Automatiza la configuración inicial de TrueNAS y genera API Keys.
        *   **Qué hace:** Crea usuario `ansible`, genera API Key, actualiza automáticamente `homelab_vars.yml` con la API Key generada, y remueve contraseña inicial por seguridad.

    *   **3. Configurar TrueNAS (`playbook_configure_truenas.yml`):**
        *   **Propósito:** Configura el almacenamiento centralizado usando la API de TrueNAS.
        *   **Qué hace:** Utiliza la API Key generada para crear datasets y recursos compartidos NFS. Habilita el servicio NFS.

    *   **4. Configurar el Clúster de Kubernetes (`playbook_configure_cluster.yml`):**
        *   **Propósito:** Instala k3s v1.31.11+k3s1 (LTS) con configuración robusta.
        *   **Qué hace:** 
            - Verifica espacio en disco y conectividad
            - Instala k3s con reintentos automáticos
            - Configura clúster multi-nodo con validación completa
            - Incluye verificación de estado final del clúster

    *   **5. Configurar Túnel de Cloudflare (integrado en `playbook_homelab.yml`):**
        *   **Propósito:** Configura automáticamente el túnel de Cloudflare desde el archivo `.env`.
        *   **Qué hace:**
            - Lee credenciales del archivo `.env`
            - Decodifica el token del túnel automáticamente
            - Despliega pods de `cloudflared` en k3s
            - Configura ingress para `*.tu-dominio.com`
            - Establece conexión segura sin port forwarding

    
        *   **Propósito:** Despliega infraestructura esencial y establece el ecosistema GitOps completo.
        *   **Qué hace:** 


    ## 🛠️ **Playbooks Utils (ansible/playbooks/utils/)**

    *   **Redimensionar Discos VMs (`playbook_resize_vm_disks.yml`):**
        *   **Propósito:** Utilitario para expandir discos de VMs existentes.
        *   **Uso:** `ansible-playbook -i ansible/inventory ansible/playbooks/utils/playbook_resize_vm_disks.yml`

    ## 🏷️ **Tags de Ansible Disponibles:**
    ```bash
    # Ejecutar solo bootstrap de Proxmox
    ansible-playbook -i ansible/inventory ansible/playbook_homelab.yml --tags bootstrap

    # Solo crear y configurar VMs
    ansible-playbook -i ansible/inventory ansible/playbook_homelab.yml --tags provision

    # Solo configurar k3s
    ansible-playbook -i ansible/inventory ansible/playbook_homelab.yml --tags k3s

    # Solo configurar TrueNAS
    ansible-playbook -i ansible/inventory ansible/playbook_homelab.yml --tags truenas

    # Solo configurar Cloudflare Tunnel
    ansible-playbook -i ansible/inventory ansible/playbook_homelab.yml --tags cloudflare

    # Solo configurar GitOps
    ansible-playbook -i ansible/inventory ansible/playbook_homelab.yml --tags gitops
    ```

8.  **¡Sistema Autónomo!**
    Una vez que el playbook ha terminado, el sistema está completamente operativo y se gestiona a sí mismo:
    
    - ✅ **Cloudflare Tunnel**: Tu dominio es accesible desde internet sin port forwarding
    - ✅ **GitOps**: ArgoCD vigila el repositorio `homelab-config` en GitHub
- ✅ **CI/CD**: GitHub Actions está listo para construir y desplegar tus aplicaciones
    - ✅ **Almacenamiento**: TrueNAS proporciona storage NFS centralizado
      - `nfs-csi` → pool `homelab-storage` (media)
      - `nfs-ssd` → pool `homelab-ssd` (descargas)
    - ✅ **Alta Disponibilidad**: k3s multi-nodo con balanceador de carga integrado

## 🚨 **Troubleshooting y Comandos Útiles**

### **Problema: Apagado del Cluster (CRÍTICO - Siempre usar apagado ordenado)**
```bash
# ❌ NUNCA usar apagado brusco - puede corromper datos
# ansible proxmox -i inventory -m shell -a "poweroff --force"

# ✅ SIEMPRE usar apagado ordenado para mantenimiento
ansible-playbook -i inventory ansible/playbooks/maintenance/playbook_graceful_shutdown_cluster.yml

# Si el apagado ordenado falla, verificar estado:
ansible k3s_nodes -i inventory -m shell -a "sudo systemctl status k3s || sudo systemctl status k3s-agent"
ansible truenas_vm -i inventory -m shell -a "curl -k -s https://localhost/api/v2.0/system/info"
ansible proxmox_host -i inventory -m shell -a "qm list"
```

### **Problema: Espacio Insuficiente en Disco (RARO - VMs tienen 30GB)**
```bash
# Verificar espacio en los nodos
ansible k3s_nodes -i ansible/inventory -m shell -a "df -h /"

# Si realmente necesitas más espacio, editar homelab_vars.yml:
# disk_size: 51200  # 50GB en lugar de 30GB
# Luego recrear VMs con el tamaño nuevo

# Limpiar espacio manualmente en un nodo (temporal)
ssh daniel@pibot
sudo apt clean && sudo apt autoremove -y
sudo journalctl --vacuum-time=3d
```

### **Problema: VMs k3s No Accesibles via SSH**
```bash
# Verificar que las VMs están corriendo
ssh root@<IP_PROXMOX> "qm list"

# Probar ping a las VMs
ping -c 2 192.168.1.131
ping -c 2 192.168.1.132
ping -c 2 192.168.1.133

# Verificar configuración cloud-init de la plantilla
ssh root@<IP_PROXMOX> "qm config 9000 | grep -E '(ciuser|cipassword|sshkeys)'"

# Si falta configuración cloud-init, actualizar plantilla:
ssh root@<IP_PROXMOX> "qm set 9000 --ciuser ubuntu --cipassword ubuntu --sshkeys ~/.ssh/id_rsa.pub"

# Recrear VMs con plantilla corregida
ansible-playbook -i ansible/inventory ansible/playbooks/core/playbook_create_vms.yml
```

### Preparar GPU NVIDIA para Plex (Proxmox + k3s)

1) Proxmox (host): habilitar IOMMU y VFIO
- En `/etc/default/grub` agrega: `intel_iommu=on iommu=pt`
- Carga VFIO: en `/etc/modules`: `vfio`, `vfio_iommu_type1`, `vfio_pci`, `vfio_virqfd`
- En `/etc/modprobe.d/vfio.conf`: `options vfio-pci ids=10de:2484,10de:228b disable_vga=1`
- Blacklist host: en `/etc/modprobe.d/blacklist-nvidia.conf`:
  - `blacklist nvidia`
  - `blacklist nvidia_drm`
  - `blacklist nvidia_modeset`
  - `blacklist nouveau`
- `update-grub` y reboot Proxmox
- Verifica: `lspci -nnk -d 10de:` → `Kernel driver in use: vfio-pci`

2) Proxmox VM k3s-node-1
- `qm set 102 --hostpci0 01:00.0,pcie=1,x-vga=1,rombar=0`
- `qm set 102 --hostpci1 01:00.1,pcie=1,rombar=0`
- `qm set 102 --machine q35 --cpu host`
- Reinicia VM `102`

3) Dentro de k3s-node-1 (Ubuntu 22.04): drivers y runtime
- Instala driver NVIDIA (último estable 570) y toolkit:
  ```bash
  sudo add-apt-repository -y ppa:graphics-drivers/ppa && sudo apt update
  sudo apt install -y nvidia-driver-570
  distribution=$( . /etc/os-release; echo ${ID}${VERSION_ID} )
  curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
  curl -fsSL https://nvidia.github.io/libnvidia-container/stable/${distribution}/nvidia-container-toolkit.list | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#' | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list >/dev/null
  sudo apt update && sudo apt install -y nvidia-container-toolkit
  ```
- Configura containerd de k3s con runtime NVIDIA: crea `/var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl` con sección `runtimes.'nvidia'.options.BinaryName="/usr/bin/nvidia-container-runtime"`.
- `sudo systemctl restart k3s`
- Verifica: `nvidia-smi`

4) Device Plugin NVIDIA
- Aplica el device plugin:
  ```bash
  kubectl apply -f cluster/infra/nvidia-device-plugin.yml
  kubectl -n nvidia-device-plugin get pods -o wide
  ```
- Verifica recurso: `kubectl get node k3s-node-1 -o jsonpath='{.status.allocatable.nvidia\.com/gpu}'`

5) Plex con GPU
- Ya configurado `runtimeClassName: nvidia` y `nvidia.com/gpu: 1` en `cluster/plex/deployment.yml`.
- Rollout: `kubectl -n plex rollout restart deploy/plex`
- Verifica dentro del pod: `ls -l /dev/nvidia*`
- En UI de Plex → Settings → Transcoder → activa Hardware Acceleration.

### **Problema: k3s Falló Durante Instalación**
```bash
# Limpiar instalación fallida
ansible k3s_nodes -i ansible/inventory -m shell -a "sudo /usr/local/bin/k3s-uninstall.sh || sudo /usr/local/bin/k3s-agent-uninstall.sh" || true

# Reinstalar solo k3s
ansible-playbook -i ansible/inventory ansible/playbook_homelab.yml --tags k3s
```

### **Verificar Estado del Sistema**
```bash
# Estado del clúster (desde un terminal con acceso a Tailscale)
ssh daniel@pibot "sudo k3s kubectl get nodes -o wide"

# Estado de aplicaciones
ssh daniel@pibot "sudo k3s kubectl get all --all-namespaces"

# Logs de k3s
ssh daniel@pibot "sudo k3s journalctl -u k3s -f"
```

### **URLs de Acceso Post-Instalación**

**🌐 URLs PÚBLICAS (Acceso desde Internet):**

- **Traefik Dashboard**: https://traefik.tu-dominio.com  
- **Sonarr**: https://sonarr.tu-dominio.com
- **Radarr**: https://radarr.tu-dominio.com
- **Prowlarr**: https://prowlarr.tu-dominio.com
- **Overseerr**: https://overseerr.tu-dominio.com
- **Plex**: https://plex.tu-dominio.com
- **Dominio Principal**: https://tu-dominio.com

**⚠️ NOTA:** Los puertos de Traefik pueden cambiar después de reinstalaciones. Verificar con:
```bash
ssh daniel@pibot "sudo k3s kubectl get service traefik -n kube-system"
```

**🏠 URLs LOCALES (Solo desde la red local):**
- **TrueNAS**: https://192.168.1.20
- **Proxmox**: https://192.168.1.100:8006

**✅ CONFIGURACIÓN DNS AUTOMÁTICA:**
- Todos los registros DNS se crean automáticamente en Cloudflare
- El túnel se configura automáticamente usando tu `.env`
- **NO necesitas port forwarding en el router** - Todo pasa por Cloudflare
- Acceso seguro via HTTPS con certificados de Cloudflare

**📡 CONFIGURACIÓN DEL ROUTER:**
- **Puerto 80**: NO necesitas abrirlo (Cloudflare Tunnel maneja todo)
- **Puerto 443**: NO necesitas abrirlo (Cloudflare Tunnel maneja todo)
- **Puerto 22**: Solo si quieres SSH externo (opcional)
- Tu IP pública puede ser dinámica - no importa con Cloudflare Tunnel

### **Verificar DNS y Túnel de Cloudflare**
```bash
# Verificar que los DNS se propagaron

nslookup traefik.tu-dominio.com

# Verificar estado del túnel en k3s (usando Tailscale)
ssh daniel@pibot "sudo k3s kubectl get pods -n cloudflared -o wide"

# Ver logs del túnel (usando Tailscale)
ssh daniel@pibot "sudo k3s kubectl logs -n cloudflared -l app=cloudflared --tail=20"

# Verificar registros DNS en Cloudflare (desde local)
curl -X GET "https://api.cloudflare.com/client/v4/zones/TU_ZONE_ID/dns_records" \
     -H "Authorization: Bearer $CF_API_TOKEN" \
     -H "Content-Type: application/json"
```

### **Configuración Correcta de Traefik con Cloudflare Tunnel (Gestión Remota)**

**✅ CONFIGURACIÓN ACTUALIZADA:**

#### **1. Configuración del Túnel de Cloudflare (Remota por API)**
Usamos túnel remotamente gestionado: la configuración `ingress` se aplica vía API, no en el ConfigMap local.

Endpoint:
`PUT /accounts/{ACCOUNT_ID}/cfd_tunnel/{TUNNEL_ID}/configurations`

Body:
```json
{
  "config": {
    "ingress": [
      
      { "hostname": "*.tu-dominio.com",  "service": "http://traefik.kube-system.svc.cluster.local:80" },
      { "service": "http_status:404" }
    ]
  }
}
```
Requiere `CF_API_TOKEN` con permiso Cloudflare Tunnel: Edit.

#### **2. Configuración de Ingress con Anotaciones Correctas**
Los ingress deben usar `web` (HTTP). El TLS externo lo termina Cloudflare. No referenciar secretos TLS.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  
  annotations:
    # Configuración para Cloudflare Tunnel
    traefik.ingress.kubernetes.io/router.entrypoints: web
    # Configuración de seguridad
    traefik.ingress.kubernetes.io/headers-frame-deny: "true"
    traefik.ingress.kubernetes.io/headers-browser-xss-filter: "true"
spec:
  ingressClassName: traefik
  # sin sección tls
  rules:
  
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
    
            port:
              number: 3000
```

#### **3. Configuración de Traefik Optimizada**
Traefik está configurado con:
- ✅ Entrypoints `web` (80) y `websecure` (443)
- ✅ Redirección automática HTTP → HTTPS
- ✅ Certificados automáticos con Let's Encrypt
- ✅ Headers de seguridad
- ✅ Rate limiting

#### **4. Cloudflare Zero Trust**
No crear Public Hostnames cuando el túnel es remoto. Mantener los CNAME apuntando a `<TUNNEL_ID>.cfargotunnel.com`.

#### **5. Script de Verificación Automática**
Usa el script actualizado para verificar la configuración:

```bash
./scripts/verify-traefik.sh
```

Este script verifica:
- ✅ Conectividad SSH
- ✅ Estado de k3s
- ✅ Pods de Traefik
- ✅ Puerto HTTPS correcto
- ✅ Estado del túnel de Cloudflare
- ✅ Configuración del túnel
- ✅ Resolución DNS
- ✅ Conectividad HTTPS local
- ✅ Certificados SSL

### **Troubleshooting de Aplicaciones**

**Problema: 404/502 en aplicaciones**

**Solución:**
```bash
# 1. Verificar que Traefik esté funcionando
ssh daniel@pibot "sudo k3s kubectl get pods -n kube-system | grep traefik"

# 2. Verificar los puertos actuales
ssh daniel@pibot "sudo k3s kubectl get service traefik -n kube-system"


```

**✅ CONFIGURACIÓN CORRECTA:**
- **Traefik:** Instalado por defecto en K3s
- **Puertos:** HTTP (32055), HTTPS (32634) - verificar con `kubectl get service traefik -n kube-system`
- **Health Checks:** Verificar endpoints de salud de las aplicaciones

**⚠️ IMPORTANTE:** 
- Los puertos pueden cambiar después de reinstalaciones
- Verificar health checks en deployments

### **Comandos de Mantenimiento**
```bash
# Actualizar solo TrueNAS
ansible-playbook -i ansible/inventory ansible/playbook_homelab.yml --tags truenas

# Reconfigurar solo Cloudflare
ansible-playbook -i ansible/inventory ansible/playbook_homelab.yml --tags cloudflare

# Recrear solo las VMs
ansible-playbook -i ansible/inventory ansible/playbook_homelab.yml --tags provision

# Verificar conectividad de todas las VMs
ansible all -i ansible/inventory -m ping

# Verificar configuración de Traefik
./scripts/verify-traefik.sh

# Reinstalar Traefik (si hay problemas)
ssh daniel@pibot "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml && helm uninstall traefik -n kube-system"
ssh daniel@pibot "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml && helm install traefik traefik/traefik --namespace kube-system --set api.dashboard=true --set api.insecure=false"
```

## 🔧 Preparar Plantillas de VM (Paso Crítico)

**ANTES** de ejecutar el playbook, debes crear plantillas de VM en Proxmox. Sin estas plantillas, el playbook fallará al intentar crear las VMs.

**🚨 AVISO IMPORTANTE:** Si previamente creaste plantillas siguiendo versiones anteriores de este README que **NO incluían configuración de cloud-init**, las plantillas **NO FUNCIONARÁN** y necesitas recrearlas o actualizarlas según las instrucciones corregidas a continuación.

### Crear Plantilla de Ubuntu para Kubernetes

1. **Descargar imagen cloud Ubuntu:**
   ```bash
   # En Proxmox, descargar imagen cloud
   wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
   ```

2. **Crear VM plantilla:**
   ```bash
   # Crear VM (usa ID 9000 para plantillas)
   qm create 9000 --memory 2048 --core 2 --name ubuntu-cloud --net0 virtio,bridge=vmbr0
   
   # Importar disco al storage NVMe (recomendado para rendimiento)
   qm importdisk 9000 jammy-server-cloudimg-amd64.img nvme
   
   # Configurar disco
   qm set 9000 --scsihw virtio-scsi-pci --scsi0 nvme:vm-9000-disk-0
   qm set 9000 --ide2 nvme:cloudinit
   qm set 9000 --boot c --bootdisk scsi0
   qm set 9000 --serial0 socket --vga serial0
   
   # 🚨 CRÍTICO: Configurar cloud-init (SIN ESTO SSH NO FUNCIONARÁ)
   qm set 9000 --ciuser ubuntu
   qm set 9000 --cipassword ubuntu  # Contraseña temporal para acceso inicial
   qm set 9000 --sshkeys ~/.ssh/id_rsa.pub  # Tu clave SSH pública
   
   # Convertir a plantilla
   qm template 9000
   ```

   **⚠️ IMPORTANTE - Pasos Adicionales para Cloud-Init:**
   
   Si no tienes una clave SSH, genérala primero:
   ```bash
   # Generar clave SSH si no existe
   ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa
   
   # Verificar que existe la clave pública
   cat ~/.ssh/id_rsa.pub
   ```

   **🚨 CRÍTICO - Copiar tu clave SSH a Proxmox:**
   ```bash
   # Copiar tu clave SSH pública local a Proxmox
   scp ~/.ssh/id_rsa.pub root@<IP_PROXMOX>:/tmp/my_public_key.pub
   
   # En Proxmox, configurar la plantilla con TU clave (no la de Proxmox)
   ssh root@<IP_PROXMOX> "qm set 9000 --sshkeys /tmp/my_public_key.pub"
   ```
   
   **⚠️ ERROR COMÚN:** Si usas `--sshkeys ~/.ssh/id_rsa.pub` directamente en Proxmox, estarás usando la clave SSH del servidor Proxmox, no la tuya local. Esto hará que SSH falle desde tu máquina.

3. **Verificar que la plantilla funciona correctamente:**
   ```bash
   # Crear VM de prueba desde la plantilla
   qm clone 9000 999 --name test-ubuntu --full
   
   # Configurar IP temporal para prueba
   qm set 999 --ipconfig0 ip=192.168.1.199/24,gw=192.168.1.1
   
   # Iniciar VM de prueba
   qm start 999
   
   # Esperar 60 segundos y probar SSH
   sleep 60
   ssh ubuntu@192.168.1.199 "hostname && uptime"
   
   # Si funciona, eliminar VM de prueba
   qm stop 999 && qm destroy 999 --purge
   ```

   **🚨 Si la prueba falla:**
   ```bash
   # Verificar configuración de la plantilla
   qm config 9000 | grep -E "(ciuser|cipassword|sshkeys)"
   
   # Debería mostrar:
   # ciuser: ubuntu
   # cipassword: **********
   # sshkeys: ssh-rsa AAAA... (tu clave pública)
   ```

### Configurar Plantilla de TrueNAS

1. **Descargar TrueNAS SCALE ISO** desde el sitio oficial
2. **Crear VM manualmente** en Proxmox con la ISO
3. **Instalar TrueNAS** con configuración básica
4. **Configurar usuario root** con contraseña conocida
5. **Convertir a plantilla** una vez configurado

## 🗄️ **Configuración Inicial de TrueNAS (PASO CRÍTICO)**

**⚠️ IMPORTANTE:** Después de que las VMs se creen automáticamente, **DEBES configurar manualmente** el pool de almacenamiento en TrueNAS antes de continuar con el playbook.

### **Paso 1: Acceso Inicial a TrueNAS**

1. **Accede a la interfaz web**: `https://192.168.1.20` (IP obtenida por DHCP)
   - **Usuario**: `truenas_admin` 
   - **Contraseña**: `Constantinopl4` (según `homelab_vars.yml`)

2. **Cambiar contraseña por seguridad** (recomendado tras setup inicial)

### **Paso 2: Crear Pool ZFS para Datos**

**🚨 CRÍTICO:** El playbook **fallará** si no existe el pool `homelab-storage`

#### **Verificar Discos Disponibles:**
En TrueNAS → **Storage** → **Disks**, deberías ver:
- ✅ **WDC_WD20EURS** (2TB) - Disco 1
- ✅ **WDC_WD30EZRX** (3TB) - Disco 2  
- ✅ **WDC_WDS120G2G0A** (120GB SSD) - Disco 3

#### **Crear el Pool:**

1. **Ve a**: **Storage** → **Pools** → **Create Pool**

2. **Configuración del Pool:**
   ```
   Nombre: homelab-storage
   Layout: Mirror (RECOMENDADO para protección de datos)
   
   ⚠️ IMPORTANTE: Los nombres ZFS NO pueden contener:
   - Espacios en blanco
   - Dos puntos (:)
   - Caracteres especiales
   Usa guiones (-) o guiones bajos (_)
   
   Configuración sugerida:
   - Mirror: WDC_WD20EURS + WDC_WD30EZRX (datos principales)  
   - Hot Spare: WDC_WDS120G2G0A (SSD como caché/spare)
   ```

3. **Layouts Alternativos según tus necesidades:**

   **🔒 MÁXIMA SEGURIDAD (Mirror):**
   ```yaml
   Layout: Mirror
   Discos: WDC_WD20EURS + WDC_WD30EZRX
   Capacidad: ~2TB (limitado por el disco menor)
   Protección: 1 disco puede fallar
   ```

   **📈 MÁXIMO ESPACIO (RAIDZ1):**  
   ```yaml
   Layout: RAIDZ1 (si tienes 3+ discos similares)
   Discos: Los 3 discos
   Capacidad: ~4TB (espacio combinado menos paridad)
   Protección: 1 disco puede fallar
   ```

   **⚡ RENDIMIENTO + SEGURIDAD (Striped Mirror):**
   ```yaml
   Layout: Striped Mirror (para discos similares)
   Configuración: 2 espejos en paralelo
   ```

4. **Confirmar Creación**: Click **Create Pool**

### **Paso 3: Verificar Pool Creado**

Ejecutar **antes** de continuar con el playbook:

```bash
 # Verificar que el pool existe
 curl -k -u "truenas_admin:Constantinopl4" https://192.168.1.20/api/v2.0/pool
 
 # Debería mostrar: [{"name": "homelab-storage", ...}]
```

### **Paso 4: Continuar con Ansible**

Una vez creado el pool, **continúa** con el playbook:

```bash
# Configurar TrueNAS (datasets y NFS)
ansible-playbook -i ansible/inventory ansible/playbooks/core/playbook_configure_truenas.yml

# O continuar con el pipeline completo
ansible-playbook -i ansible/inventory ansible/playbook_homelab.yml --tags truenas
```

### **Troubleshooting TrueNAS Pool**

**Error: "Parent dataset does not exist"**
```bash
# Verificar pools disponibles
curl -k -u "truenas_admin:Constantinopl4" https://192.168.1.20s/api/v2.0/pool

# Si no hay pools, crear manualmente desde la interfaz web
# Luego verificar el nombre exacto y actualizar homelab_vars.yml
```

**Pool con nombre diferente:**
```yaml
# En ansible/vars/homelab_vars.yml, actualizar:
truenas_data_pool: "NOMBRE_REAL_DEL_POOL"

# Ejemplos de nombres válidos:
truenas_data_pool: "homelab-storage"  # RECOMENDADO
truenas_data_pool: "media-pool" 
truenas_data_pool: "data_storage"
truenas_data_pool: "tank"            # Nombre ZFS clásico

# ❌ INVÁLIDOS (causarán errores):
# truenas_data_pool: "Pool 4: Medios"  # Contiene espacios y dos puntos
# truenas_data_pool: "media pool"      # Contiene espacios
```

### Actualizar Playbook para Usar Plantillas

Edita `ansible/vars/homelab_vars.yml` y añade los IDs de plantilla:

```yaml
# IDs de plantillas de VM en Proxmox
vm_templates:
  ubuntu: 9000      # ID de tu plantilla Ubuntu
  truenas: 9001     # ID de tu plantilla TrueNAS

# IMPORTANTE: Especificaciones mínimas de VMs
vms:
  - name: k3s-node-1
    vmid: 102
    cores: 4
    memory: 4096  # 4GB RAM
    disk: 20480   # 20GB disco (MÍNIMO para k3s)
  # ... resto de nodos con especificaciones similares
```

⚠️ **Requisitos Críticos:**
- **Sin estas plantillas, el playbook fallará**
- **Discos menores a 10GB causarán fallos en k3s**
- **Recomendado: 20GB+ por nodo para producción estable**