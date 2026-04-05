# ComfyUI - Stable Diffusion GUI

Despliegue de ComfyUI en el cluster homelab usando la imagen [jemeyer/comfyui](https://github.com/jemeyer/docker-comfyui).

## Pasos previos al despliegue (orden)

Revisión por agent-deploy, agent-truenas, agent-maintenance:

1. **API key TrueNAS:** Crear `.truenas-api-key` en la raíz del repo con una API key válida.
2. **Dataset y share NFS:** Ejecutar `./setup-truenas-dataset.sh` (crea `homelab-storage/comfyui` y la estructura de directorios vía API TrueNAS). Si el pod queda en Init por NFS, ajustar `mountOptions` en `02-pv-pvc.yaml` (vers=4 recomendado).
3. **Credenciales BasicAuth:** Guardar la contraseña generada por agent-deploy en tu gestor de contraseñas.
4. **Label media-worker:** Verificar que k3s-node-1 tenga el label:
   ```bash
   ssh daniel@pibot "sudo k3s kubectl get node k3s-node-1 --show-labels | grep media-worker"
   # Si falta: kubectl label node k3s-node-1 node-role.kubernetes.io/media-worker=true
   ```
5. **Device plugin (time-slicing):** Tras aplicar cambios, reiniciar:
   ```bash
   kubectl rollout restart daemonset/nvidia-device-plugin-daemonset -n nvidia-device-plugin
   # Verificar: kubectl get node k3s-node-1 -o jsonpath='{.status.allocatable.nvidia\.com/gpu}'  # debe ser 2
   ```
6. **Aplicar:** `kubectl apply -k cluster/apps/comfyui/` o push para FluxCD.

## Acceso

- **Por dominio (con autenticación):** https://comfyui.danielriquelme.cl
  - Usuario: `comfyui` / Contraseña: ver `COMFYUI-CREDENTIALS.txt` (generada por agent-deploy, guardar de forma segura)
- **Por Tailscale (sin auth):** Exponer con Tailscale Serve en pibot:
  1. Añadir NodePort al service: `kubectl patch svc comfyui -n comfyui -p '{"spec":{"type":"NodePort"}}'`
  2. Obtener puerto: `kubectl get svc comfyui -n comfyui -o jsonpath='{.spec.ports[0].nodePort}'`
  3. En pibot (o k3s-node-1 donde corre el pod): `tailscale serve --bg 80 http://127.0.0.1:$(kubectl get svc comfyui -n comfyui -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "31234")`
  4. Acceso: https://pibot (o hostname Tailscale del nodo) - solo desde dispositivos en la tailnet.

## Credenciales BasicAuth

La contraseña fue generada por **agent-deploy** en la revisión del plan. **Guardar en tu gestor de contraseñas** (el hash ya está aplicado en `03-ingress-domain.yaml`).

Si necesitas regenerar: `htpasswd -nb comfyui 'NUEVA_PASS' | base64 | tr -d '\n'` y reemplazar `users` en el Secret.

## GPU compartida con Plex (time-slicing)

- Se usa `--lowvram` para reducir uso de VRAM.
- Ambas apps comparten la GPU vía time-slicing (2 réplicas en el device plugin).

### Advertencia: uso simultáneo

**Riesgo de OOM (Out of Memory) de VRAM** si Plex y ComfyUI usan la GPU a la vez de forma intensiva:
- Transcodear 4K HDR en Plex + generar con SDXL/FLUX en ComfyUI puede agotar la VRAM.
- Recomendación: evitar transcodear en Plex mientras se generan imágenes con modelos pesados en ComfyUI, o usar modelos ligeros (e.g. SD 1.5) si se requiere uso simultáneo.

## Troubleshooting: "no available server"

Si tras hacer login ves "no available server":

1. **Pod no listo:** Verifica que el pod esté `Running` y `Ready`:
   ```bash
   kubectl get pods -n comfyui
   kubectl logs -n comfyui -l app=comfyui --tail=50
   ```
2. **WebSocket:** El frontend conecta a `/ws`. Si falla por proxy/Cloudflare, prueba acceso directo por Tailscale (sin túnel).
3. **Directorios NFS:** Si el pod falla con "Permission denied" en init, ejecuta el setup: `./setup-truenas-dataset.sh`. Alternativa: `kubectl apply -f 05-job-prepare-workspace.yaml` (Job one-shot).

## Copiar modelos desde tu Mac

Para modelos grandes (~19GB), usa el script que monta el NFS y copia (ejecutar con sudo):

```bash
cd cluster/apps/comfyui
sudo ./copy-z-imageturbo-models.sh
```

El NFS se monta como root; la copia requiere sudo para tener permisos de escritura. Incluye: Z Image Turbo (diffusion, VAE, text encoder).

## Persistencia completa (NFS)

Todo bajo una única raíz `/app` (un solo mount, sin subPaths):

| Directorio     | Contenido                          |
|----------------|------------------------------------|
| `main.py`, etc.| Código ComfyUI (raíz)              |
| `venv`         | Python venv + paquetes pip         |
| `models`       | Modelos (checkpoints, VAE, etc.)   |
| `input`/`output` | Carpetas de trabajo               |
| `user`         | Configuración y datos del Manager  |
| `custom_nodes` | Nodos (Manager, etc.)              |

El venv se crea solo la **primera vez**; los reinicios posteriores arrancan en segundos.

### Imagen personalizada (recomendada)

La imagen `ghcr.io/koshiro/comfyui-homelab:latest` incluye git + sqlalchemy + deps del Manager. Evita apt-get en cada arranque y resuelve `ModuleNotFoundError: No module named 'sqlalchemy'`.

Construir y publicar:

```bash
cd cluster/apps/comfyui
docker build -t ghcr.io/koshiro/comfyui-homelab:latest -f Dockerfile .
docker push ghcr.io/koshiro/comfyui-homelab:latest
```

## ComfyUI Manager

Incluido por defecto. Permite instalar nodos faltantes y actualizar ComfyUI desde la interfaz (pestaña Manager). Se instala automáticamente en el primer arranque si no existe en `custom_nodes`.

## Persistencia

- Todo en NFS: `/mnt/homelab-storage/comfyui`
- Estructura unificada: todo bajo `/app` (NFS mount único).
