# Homelab v3: Ecosistema de Desarrollo Autodesplegable

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

*   Un servidor con Proxmox VE instalado.
*   Ansible instalado en tu máquina local (`pip install ansible`).
*   Las colecciones de Ansible necesarias (`ansible-galaxy collection install community.general community.proxmox kubernetes.core`).
*   Un token de API de Proxmox.
*   Un token de API de TrueNAS.
*   Credenciales de administrador para Gitea (se usarán para el bootstrap).

### Pasos de Configuración

1.  **Clonar el Repositorio:**
    ```bash
    git clone https://github.com/tu_usuario/homelab-config.git
    cd homelab-config
    ```

2.  **Configurar las Variables:**
    *   Copia el fichero de ejemplo:
        ```bash
        cp ansible/vars/homelab_vars.yml.example ansible/vars/homelab_vars.yml
        ```
    *   **Edita `ansible/vars/homelab_vars.yml`** y rellena todos los valores.

3.  **Ejecutar el Playbook Principal:**
    Este es un proceso complejo que orquesta la creación de todo el ecosistema. Tardará varios minutos.
    ```bash
    ansible-playbook -i ansible/inventory ansible/playbook_homelab.yml
    ```

4.  **¡Sistema Autónomo!**
    Una vez que el playbook ha terminado, el sistema está completamente operativo y se gestiona a sí mismo. FluxCD vigila el repositorio `homelab-config` en tu propia instancia de Gitea, y el Gitea Actions Runner está listo para construir y desplegar tus aplicaciones.
