# Documento Maestro de Arquitectura y Metodología: Servidor Homelab v1.0

## 1. Visión General de la Arquitectura

Este documento describe la arquitectura para un servidor doméstico ("homelab") de alto rendimiento y alta disponibilidad, diseñado para soportar cargas de trabajo diversas, incluyendo un entorno de desarrollo de software, un servidor de medios, y experimentación con IA.

Los principios fundamentales de esta arquitectura son:

* **Virtualización como Base:** Se utiliza **Proxmox VE** como hipervisor bare-metal para gestionar el hardware y las máquinas virtuales.
* **Orquestación de Contenedores:** Las aplicaciones se ejecutan como contenedores Docker, orquestados por un clúster de **Kubernetes (k3s)** de alta disponibilidad.
* **Almacenamiento Centralizado:** Se utiliza **TrueNAS CORE** en una VM dedicada para gestionar y compartir todo el almacenamiento de datos, separando el cómputo del almacenamiento.
* **Gestión Declarativa (GitOps):** La configuración y el estado de todas las aplicaciones en el clúster se gestionan a través de un repositorio de **Git**, que actúa como la única fuente de la verdad, utilizando **ArgoCD**.
* **Automatización de la Infraestructura:** La configuración inicial del sistema se automatiza con **Ansible**, asegurando una implementación rápida, consistente y repetible.

## 2. Diseño Físico y de Almacenamiento

### 2.1. Hardware del Servidor
* **GPU:** NVIDIA GeForce RTX 3070
* **Discos:** 1x 512GB NVMe, 2x 240GB NVMe, 1x 240GB SATA SSD, 1x 120GB SATA SSD, 1x 12TB HDD, 1x 1.8TB HDD.

### 2.2. Estrategia de Almacenamiento con ZFS
Se adopta una estrategia que equilibra rendimiento y resiliencia.

| Pool de ZFS | Discos Físicos | Configuración | Capacidad Usable | Propósito | Resiliencia | Gestionado Por |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Pool 1: Sistema/VMs**| 512GB NVMe + 240GB NVMe | **RAID 1 (Espejo)** | ~240GB | Proxmox OS y discos de todas las VMs/LXCs. | **Máxima** | Proxmox (Host) |
| **Pool 2: Descargas** | 240GB SATA SSD | **Standalone** | 240GB | Directorio de descargas rápidas y temporales. | **Bajo** | TrueNAS (VM) |
| **Pool 3: Staging** | 120GB SATA SSD | **Standalone** | 120GB | Área de trabajo para apps de medios. | **Bajo** | TrueNAS (VM) |
| **Pool 4: Medios** | 12TB HDD | **Standalone** | 12TB | Librería de Plex (datos no críticos). | **Bajo** | TrueNAS (VM) |
| **Pool 5: Backups** | 1.8TB HDD | **Standalone** | 1.8TB | Backups del Host Proxmox y de las VMs. | **Crítico** | TrueNAS (VM) |

## 3. Arquitectura de Virtualización (Proxmox VE)

### 3.1. Máquinas Virtuales (VMs) y Contenedores (LXCs)

| Nombre | Tipo | OS | CPU / RAM (Ejemplo) | Notas |
| :--- | :--- | :--- | :--- | :--- |
| **`truenas-core`** | VM | TrueNAS CORE | 2 Cores / 8GB | Control total de los discos de datos (passthrough). Actúa como el NAS. |
| **`k3s-node-1`** | VM | Ubuntu Server | 4 Cores / 16GB | Nodo del clúster Kubernetes. **GPU Passthrough** de la RTX 3070. |
| **`k3s-node-2`** | VM | Ubuntu Server | 4 Cores / 16GB | Nodo del clúster Kubernetes. |
| **`k3s-node-3`** | VM | Ubuntu Server | 4 Cores / 16GB | Nodo del clúster Kubernetes. |
| **`cloudflare-tunnel`**| LXC | Ubuntu | Ligero | Ejecuta el servicio del túnel de Cloudflare. |
| **`traefik-proxy`** | LXC | Ubuntu | Ligero | Ejecuta el proxy inverso Traefik. |

## 4. Arquitectura de Red

El tráfico se gestiona de forma centralizada y segura:
1.  **Internet** se conecta a la **Red de Cloudflare**.
2.  El **Túnel de Cloudflare** (en su LXC) establece una conexión segura desde el servidor a Cloudflare, sin exponer puertos.
3.  El túnel reenvía todo el tráfico a **Traefik** (en su LXC).
4.  **Traefik** inspecciona el subdominio (`plex.tudominio.com`, `sonarr.tudominio.com`, etc.) y lo enruta al servicio correspondiente dentro del clúster de k3s.

## 5. Arquitectura del Clúster Kubernetes (k3s)

* **Alta Disponibilidad:** El clúster de 3 nodos asegura que si una VM falla, las aplicaciones se reinician automáticamente en las otras VMs.
* **Ingress:** Se desplegará el **Traefik Kubernetes Ingress Controller** para la gestión automática de rutas.
* **Almacenamiento Persistente:** Se instalará el **NFS CSI Driver**, que permitirá a las aplicaciones solicitar y montar almacenamiento directamente desde el NAS de TrueNAS.

## 6. Metodología de Gestión con GitOps (ArgoCD)

* **Única Fuente de la Verdad:** Se creará un repositorio en GitHub llamado `homelab-config`. Este repositorio contendrá los archivos YAML de Kubernetes para todas las aplicaciones.
* **Agente de Sincronización:** **ArgoCD** se instalará en el clúster k3s para vigilar el repositorio `homelab-config`.
* **Flujo de Trabajo:** Para desplegar o actualizar una aplicación, se debe hacer un `git push` al repositorio. **NUNCA se interactúa directamente con el clúster.**

## 7. Guía para la Automatización con Ansible

Ansible se utilizará **únicamente para la configuración inicial y la recuperación ante desastres**.
* **Playbooks:** Se crearán 4 playbooks principales: `playbook_proxmox_host.yml` (configura Proxmox), `playbook_vms_lxcs.yml` (crea las VMs), `playbook_k3s_cluster.yml` (instala k3s), y `playbook_gitops_bootstrap.yml` (despliega ArgoCD y Traefik Ingress).

## 8. Guía de Puesta en Marcha (Bootstrap Guide)

1.  **[ ] Preparación del Hardware:** Instalar discos.
2.  **[ ] Instalación del Hipervisor:** Instalar Proxmox VE.
3.  **[ ] Configuración de Almacenamiento ZFS:** Crear pools en la shell de Proxmox.
4.  **[ ] Automatización con Ansible:** Ejecutar los 4 playbooks en orden.
5.  **[ ] Configuración de TrueNAS:** Configurar pools de datos y recursos compartidos NFS.
6.  **[ ] Despliegue de Aplicaciones (GitOps):** Clonar el repo `homelab-config`, añadir el YAML de la primera app y hacer `git push`.
7.  **[ ] Configuración Final de Red:** Configurar el túnel de Cloudflare y los DNS.

## 9. Instrucciones para Agentes IA
* **Área de Operación:** Su única área de interacción es el repositorio de Git `homelab-config`.
* **Tarea de Despliegue/Actualización:** Generar o modificar los archivos YAML de Kubernetes y hacer `push` al repositorio.
* **Restricciones:** Los agentes de IA no tienen acceso directo al servidor (SSH) ni a la interfaz de Proxmox. Su único método de interacción con la infraestructura es a través de Git (GitOps).

## 10. Hoja de Ruta a Futuro
* **Fase 1 (Actual):** Implementar la arquitectura de un solo servidor.
* **Fase 2 (Crecimiento):** Adquirir un segundo servidor físico.
* **Fase 3 (Alta Disponibilidad):** Crear un clúster de Proxmox entre los servidores y migrar el almacenamiento de la VM de TrueNAS a un pool distribuido de **Ceph**.
