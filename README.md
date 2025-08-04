# Homelab v2: Centro de Datos Personal Automatizado

![https://img.shields.io/badge/Estado-En%20Desarrollo-blueviolet](https://img.shields.io/badge/Estado-En%20Desarrollo-blueviolet)
![https://img.shields.io/badge/Orquestación-Kubernetes%20(k3s)-blue](https://img.shields.io/badge/Orquestación-Kubernetes%20(k3s)-blue)
![https://img.shields.io/badge/Metodología-GitOps%20(FluxCD)-informational](https://img.shields.io/badge/Metodología-GitOps%20(FluxCD)-informational)

Este repositorio contiene la configuración completa y la "única fuente de la verdad" para mi centro de datos personal. El objetivo es construir una plataforma resiliente, segura y de fácil mantenimiento, siguiendo las mejores prácticas de la industria de DevOps.

> **Nota:** La documentación de arquitectura definitiva y actualizada se encuentra en [`docs/homelab_architecture_v2.md`](./docs/homelab_architecture_v2.md).

## 🤖 Filosofía de Diseño

*   **Gestión Declarativa (GitOps):** No se gestiona el servidor directamente. Se gestiona este repositorio. FluxCD se encarga de que el estado del clúster refleje el contenido de la rama `main`.
*   **Automatización (Manos Libres):** La configuración inicial de la infraestructura se automatiza con Ansible. El despliegue de aplicaciones es 100% automático tras un `git push`.
*   **Seguridad por Diseño:** No hay puertos expuestos a Internet. El acceso se gestiona a través de un túnel seguro y cifrado con Cloudflare.

## 🏗️ Estructura del Repositorio

```
/
├── ansible/              # Playbooks de Ansible para el bootstrap inicial de la infraestructura.
├── cluster/              # El corazón del GitOps: manifiestos de Kubernetes.
│   ├── config/           # Configuración global del clúster (variables, etc.).
│   ├── flux-system/      # Manifiestos para configurar el propio FluxCD.
│   └── (apps)/           # Directorios para cada aplicación (gitea, plex, etc.).
└── docs/                 # Documentación del proyecto.
    ├── archive/          # (No versionado) Documentos históricos.
    └── homelab_architecture_v2.md # La arquitectura oficial del sistema.
```

## 🚀 Flujo de Trabajo: Desplegar una Nueva Aplicación

1.  **Crear un Directorio:** Añadir un nuevo directorio para la aplicación en `cluster/apps/`.
2.  **Crear Manifiestos:** Añadir los archivos YAML de Kubernetes (Deployment, Service, Ingress, etc.) dentro del nuevo directorio.
3.  **Actualizar Kustomization:** Añadir una referencia al nuevo directorio en el archivo `cluster/kustomization.yml` principal.
4.  **Hacer `push`:** `git commit` y `git push`.
5.  **Observar la Magia:** FluxCD detectará los cambios y desplegará la aplicación automáticamente.
