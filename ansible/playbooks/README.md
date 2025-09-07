# 📋 **Estructura de Playbooks - Homelab BMad**

Esta estructura está organizada para separar claramente el **aprovisionamiento inicial** de las **tareas de mantenimiento**, siguiendo principios de Infrastructure as Code (IaC) para máxima claridad y mantenibilidad.

## 📁 **Estructura de Directorios**

```
ansible/
├── inventory                # Define los hosts y grupos (master, workers, etc.)
├── roles/
│   └── nvidia_gpu/          # Rol para configurar nodos con GPU NVIDIA
├── playbooks/
│   ├── provisioning/        # Playbooks para crear la infraestructura desde cero
│   │   ├── playbook_bootstrap_server.yml
│   │   ├── playbook_create_vms.yml
│   │   ├── playbook_initial_truenas_setup.yml
│   │   ├── playbook_configure_truenas.yml
│   │   └── playbook_configure_cluster.yml
│   │
│   ├── maintenance/         # Playbooks para gestionar y mantener el entorno existente
│   │   ├── playbook_add_disk_to_truenas.yml
│   │   ├── playbook_graceful_shutdown_cluster.yml
│   │   ├── playbook_mount_nfs.yml
│   │   ├── playbook_resize_vm_disks.yml
│   │   └── playbook_setup_gpu_node.yml  (Usa el rol nvidia_gpu)
│   │
│   └── playbook_provision_all.yml # Orquestador para el aprovisionamiento completo
│
└── vars/
    └── homelab_vars.yml.example # Variables de configuración
```

## 🚀 **Playbooks de Aprovisionamiento (`provisioning/`)**

Estos playbooks construyen todo el homelab desde cero. Se ejecutan secuencialmente a través de `playbook_provision_all.yml`.

- **`playbook_bootstrap_server.yml`**: Prepara el servidor Proxmox (repos, paquetes, GPU passthrough).
- **`playbook_create_vms.yml`**: Crea las VMs para TrueNAS y k3s.
- **`playbook_initial_truenas_setup.yml`**: Configuración inicial de TrueNAS y generación de API Key.
- **`playbook_configure_truenas.yml`**: Crea datasets y comparte por NFS.
- **`playbook_configure_cluster.yml`**: Instala un clúster de k3s robusto y moderno en los nodos definidos.

### **Ejecución del Aprovisionamiento Completo**
```bash
# Despliega todo el homelab desde cero
ansible-playbook -i ansible/inventory ansible/playbook_provision_all.yml
```

## 🛠️ **Playbooks de Mantenimiento (`maintenance/`)**

Estos playbooks se utilizan para gestionar, actualizar y solucionar problemas del clúster una vez que ya está en funcionamiento.

- **`playbook_add_disk_to_truenas.yml`**: Agrega un disco físico a la VM de TrueNAS.
- **`playbook_graceful_shutdown_cluster.yml`**: Realiza un apagado ordenado de todo el sistema.
- **`playbook_mount_nfs.yml`**: (Re)monta los directorios NFS en los nodos del clúster.
- **`playbook_resize_vm_disks.yml`**: Expande el disco de las VMs y el filesystem interno.
- **`playbook_setup_gpu_node.yml`**: Configura un nodo worker con drivers NVIDIA y el container toolkit.

### **Ejemplos de Comandos de Mantenimiento**
```bash
# Configurar la GPU en el nodo k3s-node-1
ansible-playbook -i ansible/inventory ansible/playbooks/maintenance/playbook_setup_gpu_node.yml --limit k3s-node-1

# Apagar ordenadamente todo el clúster
ansible-playbook -i ansible/inventory ansible/playbooks/maintenance/playbook_graceful_shutdown_cluster.yml
```

## 📦 **Roles (`roles/`)**

- **`nvidia_gpu`**: Lógica encapsulada para la instalación y configuración completa de NVIDIA (drivers, toolkit, runtime de k3s). Es utilizado por `playbook_setup_gpu_node.yml`.

## ⚠️ **Notas Importantes**

- **Idempotencia**: Los playbooks han sido refactorizados para ser lo más idempotentes posible. Puedes ejecutarlos varias veces y solo aplicarán los cambios necesarios.
- **Variables**: Toda la configuración específica de tu entorno (IPs, nombres de pool, etc.) debe estar en `ansible/inventory` y `ansible/vars/homelab_vars.yml`.
- **GitOps**: La configuración de aplicaciones (Deployments, Services, etc.) **NO** se gestiona con Ansible. Se encuentra en el directorio `cluster/` y debe ser aplicada vía GitOps (Flux, ArgoCD) o `kubectl apply`. Ansible se encarga de la infraestructura subyacente.
