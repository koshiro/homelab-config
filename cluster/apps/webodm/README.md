# WebODM en el homelab

Stack alineado con [WebODM docker-compose](https://github.com/OpenDroneMap/WebODM): **Postgres** (`webodm/webodm_db`), **Redis 7**, **webapp**, **worker** (Celery) y **nodo de procesado** (**`opendronemap/nodeodm`**; la imagen `webodm/nodeodx:latest` falló en runtime sin `/usr/bin/node` en el entorno actual). Sin Ingress ni Cloudflare: solo **NodePort `31808`** → HTTP en el contenedor **8000**.

## Acceso vía Tailscale

Con el mismo patrón que Ollama (NodePort + tailnet):

```text
http://k3s-node-0:31808
```

Si usas otra máquina o IP de Tailscale como entrada, edita `configmap.yml` (`WO_HOST`) para que coincida con el host que escribes en el navegador (enlaces y cookies coherentes).

## Persistencia (local-path sobre discos Proxmox)

**TrueNAS no está disponible**, así que el almacenamiento ya no usa NFS. En su lugar se usa **`local-path-provisioner`**, que viene habilitado por defecto en k3s: cada `PersistentVolumeClaim` se aprovisiona dinámicamente como un `hostPath` sobre el disco local del nodo (que en este homelab es, a su vez, un disco virtual gestionado por Proxmox).

Comprueba antes de desplegar que la StorageClass exista:

```bash
kubectl get storageclass local-path
```

Si no aparece, revisa que k3s no se haya instalado con `--disable=local-storage`, o instala manualmente el [local-path-provisioner](https://github.com/rancher/local-path-provisioner).

**Limitación clave:** un volumen `local-path` vive en un único nodo (es ReadWriteOnce "de nodo", no hay RWX real entre nodos distintos). Por eso cada Deployment que usa un PVC trae un `nodeSelector` fijo en vez de la `nodeAffinity` de rango que había antes:

| Deployment | Nodo fijo | PVC |
|---|---|---|
| `db` | `k3s-node-1` | `webodm-db` |
| `webapp` | `k3s-node-2` | `webodm-media` |
| `worker` | `k3s-node-2` | `webodm-media` |
| `node-odx-1` | `k3s-node-3` | `webodm-nodeodm` |
| `broker` (redis, sin PVC) | cualquiera de node-1/2/3 | — |

`db` no necesita estar en el mismo nodo que `webapp`/`worker`: tiene su propio PVC (`webodm-db`), independiente de `webodm-media`. Solo `webapp` y `worker` están obligados a coincidir entre sí, porque comparten `webodm-media`. Se movieron a `k3s-node-2` porque `k3s-node-1` no tenía CPU libre suficiente para sumarlos junto a `db` (ver Troubleshooting).

`webapp` y `worker` **deben** apuntar siempre al mismo nodo porque comparten `webodm-media`. Si cambias uno, cambia el otro (y ojo con el espacio en disco disponible en ese nodo/VM de Proxmox, porque ahí es donde crecerán los proyectos).

Si en el futuro vuelves a tener NFS (TrueNAS u otro) o montas el [Proxmox CSI plugin](https://github.com/sergelogvinov/proxmox-csi-plugin) para discos block reales de Proxmox, puedes volver a un `StorageClass` compartido y quitar los `nodeSelector` fijos.

## Despliegue

```bash
kubectl apply -k cluster/apps/webodm/
kubectl -n webodm rollout status deploy/db --timeout=300s
kubectl -n webodm rollout status deploy/node-odx-1 --timeout=300s
kubectl -n webodm rollout status deploy/webapp --timeout=300s
```

Primera visita: creación del usuario admin en la UI.

## Secretos

`secret.sops.yml` (SOPS) incluye `WO_SECRET_KEY` para evitar que Django escriba `secret_key.py` en una capa de solo lectura.

## Recursos y afinidad

El nodo de procesado pide **4–16 Gi** de RAM y CPU amplia; sube `limits` si procesas muchas imágenes (ver tabla RAM en la doc de OpenDroneMap). Ajusta la memoria/CPU asignada a la VM Proxmox de `k3s-node-3` en consecuencia. `db` está fijado a `k3s-node-1` (asegúrate de que esa VM tenga disco suficiente para Postgres); `webapp` y `worker` están fijados a `k3s-node-2` (asegúrate de que esa VM tenga disco suficiente para los proyectos WebODM en `webodm-media`).

## Troubleshooting breve

- **`Pending` con `0/3 nodes are available: node(s) had volume node affinity conflict`:** el pod intenta agendarse en un nodo distinto al que tiene el volumen `local-path` ya creado. Revisa que el `nodeSelector` del Deployment coincida con el nodo real donde se creó el volumen (mira `kubectl get pv -o wide` y el `hostPath` real bajo `/var/lib/rancher/k3s/storage/` en ese nodo).
- **Webapp `CrashLoop` / migraciones:** revisa logs `kubectl -n webodm logs deploy/db` y `deploy/webapp`.
- **`wait-nodeodm` init falla:** `kubectl -n webodm logs deploy/webapp -c wait-nodeodm` y estado de `deploy/node-odx-1`.
- **Sin cola / nodo offline:** en WebODM → *Processing Nodes*, el host por defecto debería resolverse como `node-odx-1` en el cluster; si cambias el nombre del Service, reconfigura el nodo en la UI.
- **Poco espacio en disco del nodo:** como ahora el almacenamiento es local (no NFS con 200Gi reales garantizados), vigila el disco de las VM Proxmox de `k3s-node-1` (Postgres) y `k3s-node-2` (media); `local-path-provisioner` no aplica cuotas duras por defecto, así que un proyecto grande puede llenar el disco del nodo si no lo dimensionas.
- **`FailedScheduling` / `Insufficient cpu`:** el `nodeSelector` fija cada pod a un único nodo, así que si ese nodo no tiene CPU/memoria libre, el pod se queda en `Pending` aunque otros nodos sí tengan hueco. Revisa `kubectl describe nodes` para ver la CPU `Allocatable` vs ya reservada, y mueve el `nodeSelector` (en `webapp` y `worker` a la vez, porque comparten PVC) a un nodo con margen.
