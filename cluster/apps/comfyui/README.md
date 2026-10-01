# ComfyUI - Stable Diffusion GUI

Despliegue de ComfyUI en el cluster homelab usando la imagen [jemeyer/comfyui](https://github.com/jemeyer/docker-comfyui).

## Pasos previos al despliegue (orden)

Revisión por agent-deploy, agent-truenas, agent-maintenance:

1. **Almacenamiento:** `homelab-storage/comfyui` servido por NFS desde Proxmox (`192.168.1.100`). Estructura de directorios: `kubectl apply -f 05-job-prepare-workspace.yaml`. Si el pod queda en Init por NFS, ajustar `mountOptions` en `02-pv-pvc.yaml` (vers=4 recomendado).
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
3. **Directorios NFS:** Si el pod falla con "Permission denied" en init, ejecuta `kubectl apply -f 05-job-prepare-workspace.yaml` (Job one-shot).

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
| `venv/`        | Python venv persistente (`/app/venv` en el pod): copia inicial desde la imagen + todo `pip install` (incl. custom nodes con `requirements.txt`). No se pierde al reiniciar el pod. |
| `models`       | Modelos (checkpoints, VAE, etc.)   |
| `input`/`output` | Carpetas de trabajo               |
| `user`         | Configuración y datos del Manager  |
| `custom_nodes` | Nodos (Manager, etc.)              |

El init `ensure-venv` crea `/app/venv` en NFS la **primera vez** copiando el venv de la imagen (CUDA/torch incluido). En cada arranque se ejecuta `pip install` de forma idempotente hacia ese mismo venv; `PIP_NO_CACHE_DIR=1` evita persistir **cachés** de pip en disco, pero los **paquetes instalados** sí quedan en `venv/`. Nuevos custom nodes con `requirements.txt` se instalan solos en el siguiente arranque.

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

## Logs de arranque (siempre visibles)

El contenedor escribe mensajes con **timestamp** y prefijo `[comfyui-boot]` por fase (1/4 a 4/4), versión de Python/pip, y **cada** `requirements.txt` de extensiones con índice `[k/N]`. La fase 4 es **síncrona** (termina antes de cargar ComfyUI) para que las dependencias estén instaladas al importar nodos. El primer arranque o tras añadir muchas extensiones puede ser largo; el `startupProbe` permite hasta ~120 minutos (ajustable en el Deployment si hace falta).

- **`COMFYUI_BOOT_VERBOSE`** (por defecto `true`): pip muestra salida normal (paquetes ya satisfechos, descargas, etc.). Con `false`, pip usa `-q` y solo verás las líneas `[comfyui-boot]`.
- **`PYTHONUNBUFFERED=1`**: los logs de Python aparecen al instante.
- El init **`ensure-venv`** imprime `[ensure-venv]` al copiar el venv a NFS.

```bash
kubectl logs -n comfyui -l app=comfyui -f --tail=100
```

## Versionado y dependencias (automático)

### Última release estable

El init `ensure-app` hace `git fetch --tags` y deja el árbol en el tag `v*` **más reciente** (orden semver con `git tag --sort=-version:refname`). Cada nuevo pod puede tomar una release nueva si upstream publicó un tag después del último arranque.

### Pin manual (opcional)

Para fijar un tag o commit concreto, edita `00-deployment.yaml` en el init `ensure-app`:

```yaml
- name: COMFYUI_REF
  value: "v0.19.1"   # o un SHA de git
```

Si `COMFYUI_REF` está **vacío** (por defecto), se usa siempre la última release `v*`.

### Huella de dependencias (`/app/.deps-fingerprint`)

Las fases 1–3 de pip (core ComfyUI, ComfyUI-Manager, paquetes base opencv/gguf/sqlalchemy) solo se ejecutan cuando cambia la **huella**:

- `HEAD` del repo ComfyUI en `/app`
- SHA256 de `requirements.txt`
- SHA256 de `custom_nodes/ComfyUI-Manager/requirements.txt` (si existe)

Si la huella coincide con el fichero guardado en NFS, esas fases se omiten (arranque rápido). Tras un cambio de release o de requirements, la huella difiere y se vuelve a instalar; también se borran los marcadores `.fail` bajo `.pip-req-ready` para permitir reintentos de custom nodes.

**Fase 4 (extensiones):** antes de arrancar `main.py`, el contenedor recorre **todos** los `requirements.txt` bajo `custom_nodes` (excepto `ComfyUI-Manager`, ya cubierto en la fase 2), ejecuta `pip install --upgrade` hacia `/app/venv` (NFS, **persistente**). Cada extensión tiene un marcador en `.pip-req-ready/` con la **huella SHA256 del fichero**; si cambias el `requirements.txt` de una extensión (o el Manager instala una nueva), en el siguiente arranque se vuelve a instalar/actualizar. Si pip falla con un contenido concreto, se guarda `.fail` con la misma huella; para reintentar, borra ese `.fail` o corrige el `requirements.txt`. Se aplica el **constraint** `sqlalchemy>=2.0.36` para no degradar el ORM.

## Persistencia

- Todo en NFS: `/mnt/homelab-storage/comfyui`
- Estructura unificada: todo bajo `/app` (NFS mount único).
- `git clean` en el init `ensure-app` **excluye** datos de trabajo, `venv/`, y estado de bootstrap: `.deps-fingerprint`, `.deps-ready-v*`, `.pip-req-ready`, `.pip-constraints`, además de `models/`, `user/`, `input/`, `output/`, `custom_nodes/`.
