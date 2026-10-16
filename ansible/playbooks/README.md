# Playbooks de Ansible

Ansible gestiona la infraestructura base (host Proxmox, nodos k3s, GPU). Las aplicaciones viven en `cluster/` y las aplica Flux al mergear a `main`; el almacenamiento (ZFS, NFS, sanoid/syncoid, LXC `nas`) está en el host y se documenta en [`proxmox/README.md`](../../proxmox/README.md).

Inventario: `ansible/inventory` (grupos `proxmox_host`, `k3s_master`, `k3s_workers`, `k3s_nodes`). Secretos: `ansible/vars/vault.yml`, contraseña en `~/.config/homelab/ansible-vault-pass` (configurada en `ansible.cfg`).

## Estructura

```
ansible/
├── inventory
├── playbook_provision_all.yml          # Orquestador: bootstrap Proxmox → k3s → verificación
├── roles/nvidia_gpu/                   # Drivers NVIDIA, container toolkit y runtime de k3s
├── vars/vault.yml                      # ansible-vault
└── playbooks/
    ├── provisioning/
    │   ├── playbook_bootstrap_server.yml    # Repos, paquetes y passthrough de GPU en Proxmox
    │   └── playbook_configure_cluster.yml   # Instala k3s (master + workers)
    └── maintenance/
        ├── playbook_graceful_shutdown_cluster.yml  # Apagado ordenado (etcd, drain, LXC/VMs, host)
        ├── playbook_startup_cluster.yml            # Encendido: pools, NFS, uncordon, verificación
        ├── playbook_setup_gpu_node.yml             # Aplica el rol nvidia_gpu (usar --limit k3s-node-1)
        └── playbook_configure_tailscale_ssh.yml    # Tailscale SSH en los nodos k3s
```

## Uso

```bash
# Apagado ordenado (pibot queda encendido salvo -e apagar_pibot=true)
ansible-playbook ansible/playbooks/maintenance/playbook_graceful_shutdown_cluster.yml

# Encendido / verificación tras arrancar
ansible-playbook ansible/playbooks/maintenance/playbook_startup_cluster.yml

# Nodo GPU
ansible-playbook ansible/playbooks/maintenance/playbook_setup_gpu_node.yml --limit k3s-node-1

# Reconstrucción (tags: bootstrap, wait, k3s, verify)
ansible-playbook ansible/playbook_provision_all.yml --tags k3s
```
