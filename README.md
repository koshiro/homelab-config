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

    **¿Qué hace este playbook?**

    El `playbook_homelab.yml` es el orquestador maestro. Ejecuta una secuencia de playbooks más pequeños, cada uno con una responsabilidad específica, para construir tu homelab desde cero:

    *   **0. Bootstrap del Servidor Proxmox (`playbook_bootstrap_server.yml`):**
        *   **Propósito:** Prepara el sistema operativo base de tu servidor Proxmox.
        *   **Qué hace:** Actualiza los paquetes del sistema, instala herramientas esenciales como `git` y `vim`, y asegura que el host esté listo para la virtualización.

    *   **1. Crear Máquinas Virtuales (`playbook_create_vms.yml`):**
        *   **Propósito:** Provisiona las máquinas virtuales que formarán tu clúster de Kubernetes y tu instancia de TrueNAS.
        *   **Qué hace:** Se conecta a la API de Proxmox y crea las VMs (`truenas-core`, `k3s-node-1`, `k3s-node-2`, `k3s-node-3`) con los recursos (CPU, RAM, disco) y configuraciones de red especificados en `homelab_vars.yml`. Los discos virtuales de estas VMs se crearán en el pool ZFS `nvme-vms` que configuraste manualmente.

    *   **2. Esperar a que las VMs estén listas:**
        *   **Propósito:** Asegura que las VMs recién creadas estén arrancadas y accesibles vía SSH antes de intentar configurarlas.
        *   **Qué hace:** Pausa la ejecución del playbook hasta que pueda establecer una conexión SSH con cada una de las VMs.

    *   **3. Configuración Inicial de TrueNAS y Generación de API Key (`playbook_initial_truenas_setup.yml`):**
        *   **Propósito:** Automatiza la configuración inicial de TrueNAS y obtiene la API Key necesaria para futuras operaciones.
        *   **Qué hace:** Se conecta a la VM de TrueNAS (usando las credenciales iniciales de `root`), crea un usuario dedicado para Ansible, genera una API Key para ese usuario, y **actualiza automáticamente el fichero `ansible/vars/homelab_vars.yml` en tu máquina local** con esta API Key. También elimina la contraseña de `root` del fichero de variables por seguridad.

    *   **4. Configurar TrueNAS (Datasets y NFS Shares) (`playbook_configure_truenas.yml`):**
        *   **Propósito:** Configura el almacenamiento centralizado de tu homelab utilizando la API Key generada en el paso anterior.
        *   **Qué hace:** Se conecta a la API de TrueNAS y crea los pools de ZFS, los datasets y los recursos compartidos NFS que serán utilizados por las aplicaciones de Kubernetes. También habilita el servicio NFS.

    *   **5. Configurar el Clúster de Kubernetes (`playbook_configure_cluster.yml`):**
        *   **Propósito:** Instala y configura el clúster de Kubernetes (k3s).
        *   **Qué hace:** Instala k3s en el primer nodo como maestro y luego une los nodos restantes como trabajadores, formando un clúster funcional.

    *   **6. Desplegar aplicaciones base (Gitea, Traefik, etc.):**
        *   **Propósito:** Despliega los componentes esenciales de la infraestructura de Kubernetes que son necesarios para el ecosistema de desarrollo.
        *   **Qué hace:** Aplica los manifiestos de Kubernetes del directorio `cluster/` (incluyendo Gitea, Traefik, Cloudflared, y el NFS CSI Driver) directamente al clúster. Esto asegura que Gitea esté operativo para el siguiente paso.

    *   **7. Configurar el Ecosistema de Gitea y GitOps (`playbook_setup_gitea_ecosystem.yml`):**
        *   **Propósito:** Establece la conexión entre Ansible, Gitea y FluxCD para crear el ecosistema de desarrollo autogestionado.
        *   **Qué hace:**
            *   Espera a que la API de Gitea esté completamente disponible.
            *   Crea un token de administrador temporal en Gitea.
            *   Crea los repositorios `homelab-config` y `tattoo-app` en Gitea.
            *   Clona el repositorio `homelab-config` desde Gitea (asegurando que la VM tenga acceso y credenciales si el repositorio es privado), copia los manifiestos locales del directorio `cluster/` a él, y hace un `commit` y `push` inicial.
            *   Configura FluxCD para que apunte a este nuevo repositorio `homelab-config` en Gitea, estableciendo el ciclo de GitOps.
            *   Obtiene el token de registro del Gitea Actions Runner y lo configura en Kubernetes.
            *   **Revoca el token de administrador de Gitea** para mantener la seguridad.

7.  **¡Sistema Autónomo!**
    Una vez que el playbook ha terminado, el sistema está completamente operativo y se gestiona a sí mismo. FluxCD vigila el repositorio `homelab-config` en tu propia instancia de Gitea, y el Gitea Actions Runner está listo para construir y desplegar tus aplicaciones.

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

### Actualizar Playbook para Usar Plantillas

Edita `ansible/vars/homelab_vars.yml` y añade los IDs de plantilla:

```yaml
# IDs de plantillas de VM en Proxmox
vm_templates:
  ubuntu: 9000      # ID de tu plantilla Ubuntu
  truenas: 9001     # ID de tu plantilla TrueNAS
```

⚠️ **Sin estas plantillas, el playbook fallará.** Este es el paso más importante que faltaba en la documentación original.