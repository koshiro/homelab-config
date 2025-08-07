# Homelab: Ecosistema de Desarrollo Autodesplegable

![Estado](https://img.shields.io/badge/Estado-Listo%20para%20Despliegue-brightgreen)
![Orquestación](https://img.shields.io/badge/Orquestación-Kubernetes%20(k3s)-blue)
![Metodología](https://img.shields.io/badge/Metodología-GitOps%20(FluxCD)%20%2B%20Ansible-informational)

Este repositorio contiene la configuración completa para un centro de datos personal que no solo ejecuta aplicaciones, sino que también proporciona un ecosistema de desarrollo y despliegue continuo (CI/CD) completamente automatizado.

## 🤖 Filosofía de Diseño

*   **Infraestructura como Código (IaC):** Todo, desde la creación de VMs hasta la configuración de aplicaciones, está definido como código en este repositorio.
*   **GitOps como Fuente de la Verdad:** El estado deseado del clúster de Kubernetes se define en un repositorio de Git (`homelab-config`) que vive dentro de nuestra propia instancia de Gitea. FluxCD se encarga de sincronizar el clúster con este repositorio.
*   **CI/CD Integrado:** Gitea Actions se utiliza para construir, probar y desplegar aplicaciones automáticamente. El pipeline de CI/CD actualiza la versión de la imagen en el repositorio `homelab-config`, y FluxCD se encarga del resto.

## 🏗️ Arquitectura del Ecosistema

El sistema se compone de dos tipos de repositorios:

1.  **`homelab-config` (Este Repositorio):** Contiene la configuración de la infraestructura (Ansible) y los manifiestos de Kubernetes (`/cluster`) que describen el estado deseado del clúster.
2.  **Repositorios de Aplicaciones (ej. `tattoo-app`):** Contienen el código fuente de las aplicaciones. Su pipeline de CI/CD produce imágenes de Docker que se almacenan en el registro de contenedores de Gitea.

El flujo de trabajo es el siguiente:

1.  Un desarrollador hace `push` a un repositorio de aplicación en Gitea.
2.  Gitea Actions construye una nueva imagen de Docker y la sube al registro de Gitea.
3.  Gitea Actions actualiza el manifiesto de la aplicación en el repositorio `homelab-config` con la nueva versión de la imagen.
4.  FluxCD detecta el cambio en `homelab-config` y despliega la nueva versión de la aplicación en el clúster.

## 🚀 Guía de Puesta en Marcha (Bootstrap)

Sigue estos pasos para desplegar el homelab desde cero en un servidor con Proxmox recién instalado.

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

3.  **Instalación de Proxmox y Configuración de Almacenamiento:**
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

4.  **Configurar Acceso SSH a Proxmox:**
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

5.  **Configurar el Archivo de Inventario:**
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

6.  **Ejecutar el Playbook Principal:**
    Este es un proceso complejo que orquesta la creación de todo el ecosistema. Tardará varios minutos.
    ```bash
    ansible-playbook -i ansible/inventory ansible/playbook_homelab.yml
    ```

    **🚨 IMPORTANTE - Requisitos de Espacio en Disco:**
    - **Mínimo absoluto**: 10GB por nodo k3s
    - **Recomendado**: 20GB+ por nodo para producción
    - Las VMs con menos de 8GB de espacio libre **FALLARÁN** durante la instalación de k3s

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

    *   **5. Desplegar aplicaciones base y GitOps (`playbook_setup_gitea_ecosystem.yml`):**
        *   **Propósito:** Despliega infraestructura esencial y establece el ecosistema GitOps completo.
        *   **Qué hace:** 
            - Espera que Gitea esté disponible
            - Crea token temporal y repositorios (`homelab-config`, `tattoo-app`)
            - Configura FluxCD para GitOps automático
            - Configura Gitea Actions Runner
            - Revoca tokens temporales por seguridad

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
    ```

7.  **¡Sistema Autónomo!**
    Una vez que el playbook ha terminado, el sistema está completamente operativo y se gestiona a sí mismo. FluxCD vigila el repositorio `homelab-config` en tu propia instancia de Gitea, y el Gitea Actions Runner está listo para construir y desplegar tus aplicaciones.

## 🚨 **Troubleshooting y Comandos Útiles**

### **Problema: Espacio Insuficiente en Disco**
```bash
# Verificar espacio en los nodos
ansible k3s_nodes -i ansible/inventory -m shell -a "df -h /"

# Redimensionar discos VMs (requiere apagar VMs)
ansible-playbook -i ansible/inventory ansible/playbooks/utils/playbook_resize_vm_disks.yml

# Limpiar espacio manualmente en un nodo
ssh k3s-node-1
sudo apt clean && sudo apt autoremove -y
sudo journalctl --vacuum-time=3d
```

### **Problema: k3s Falló Durante Instalación**
```bash
# Limpiar instalación fallida
ansible k3s_nodes -i ansible/inventory -m shell -a "sudo /usr/local/bin/k3s-uninstall.sh || sudo /usr/local/bin/k3s-agent-uninstall.sh" || true

# Reinstalar solo k3s
ansible-playbook -i ansible/inventory ansible/playbook_homelab.yml --tags k3s
```

### **Verificar Estado del Sistema**
```bash
# Estado del clúster
ssh k3s-node-1 "sudo k3s kubectl get nodes -o wide"

# Estado de aplicaciones
ssh k3s-node-1 "sudo k3s kubectl get all --all-namespaces"

# Logs de k3s
ssh k3s-node-1 "sudo journalctl -u k3s -f"
```

### **URLs de Acceso Post-Instalación**
- **Gitea**: http://gitea.homelab.local
- **TrueNAS**: https://192.168.1.200
- **Traefik Dashboard**: http://traefik.homelab.local
- **Proxmox**: https://192.168.1.100:8006

### **Comandos de Mantenimiento**
```bash
# Actualizar solo TrueNAS
ansible-playbook -i ansible/inventory ansible/playbook_homelab.yml --tags truenas

# Recrear solo las VMs
ansible-playbook -i ansible/inventory ansible/playbook_homelab.yml --tags provision

# Verificar conectividad de todas las VMs
ansible all -i ansible/inventory -m ping
```

## 🔧 Preparar Plantillas de VM (Paso Crítico)

**ANTES** de ejecutar el playbook, debes crear plantillas de VM en Proxmox. Sin estas plantillas, el playbook fallará al intentar crear las VMs.

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
   
   # Importar disco
   qm importdisk 9000 jammy-server-cloudimg-amd64.img local-lvm
   
   # Configurar disco
   qm set 9000 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-9000-disk-0
   qm set 9000 --ide2 local-lvm:cloudinit
   qm set 9000 --boot c --bootdisk scsi0
   qm set 9000 --serial0 socket --vga serial0
   
   # Convertir a plantilla
   qm template 9000
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

1. **Accede a la interfaz web**: `https://192.168.1.19` (IP obtenida por DHCP)
   - **Usuario**: `truenas_admin` 
   - **Contraseña**: `Constantinopl4` (según `homelab_vars.yml`)

2. **Cambiar contraseña por seguridad** (recomendado tras setup inicial)

### **Paso 2: Crear Pool ZFS para Datos**

**🚨 CRÍTICO:** El playbook **fallará** si no existe el pool `Pool 4: Medios`

#### **Verificar Discos Disponibles:**
En TrueNAS → **Storage** → **Disks**, deberías ver:
- ✅ **WDC_WD20EURS** (2TB) - Disco 1
- ✅ **WDC_WD30EZRX** (3TB) - Disco 2  
- ✅ **WDC_WDS120G2G0A** (120GB SSD) - Disco 3

#### **Crear el Pool:**

1. **Ve a**: **Storage** → **Pools** → **Create Pool**

2. **Configuración del Pool:**
   ```
   Nombre: Pool 4: Medios
   Layout: Mirror (RECOMENDADO para protección de datos)
   
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
curl -k -u "truenas_admin:Constantinopl4" https://192.168.1.19/api/v2.0/pool

# Debería mostrar: [{"name": "Pool 4: Medios", ...}]
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
curl -k -u "truenas_admin:Constantinopl4" https://192.168.1.19/api/v2.0/pool

# Si no hay pools, crear manualmente desde la interfaz web
# Luego verificar el nombre exacto y actualizar homelab_vars.yml
```

**Pool con nombre diferente:**
```yaml
# En ansible/vars/homelab_vars.yml, actualizar:
truenas_data_pool: "NOMBRE_REAL_DEL_POOL"
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