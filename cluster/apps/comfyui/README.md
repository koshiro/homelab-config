# ComfyUI

ComfyUI en la **RTX 3070 (8 GB, Ampere)** de `k3s-node-1`, con la GPU compartida por time-slicing (Plex y
Ollama también la usan). Todo el estado vive en el volumen NFS `homelab-storage/comfyui` (Proxmox,
`02-pv-pvc.yaml`): código, entorno de Python, extensiones, modelos, workflows y salidas. Rehecho el
2026-10-03 tras recrear el pool (ver `docs/PENDIENTES.md`).

| Archivo | Qué hace |
|---|---|
| `00-deployment.yaml` | Solo arranca `main.py` con `--use-sage-attention --fast fp16_accumulation` (imagen pública `nvidia/cuda:12.8.1-devel`, que trae gcc/nvcc para Triton). No instala nada. |
| `06-job-build-env.yaml` | Construye/actualiza el entorno: ComfyUI a la última release `v*`, Python 3.12 (uv, en `/app/.python`), PyTorch 2.11 + CUDA 12.8, SageAttention 2.2 compilado para sm_86, extensiones usadas por los workflows (las demás a `custom_nodes/.disabled`). Lock en `venv/requirements.lock`. |
| `07-job-download-models.yaml` | Descarga los modelos con verificación SHA256 (Civitai con el token de `secret-civitai.sops.yaml`). Idempotente. |
| `05-job-prepare-workspace.yaml` | Estructura de carpetas (solo si hay `Permission denied`). |
| `08-smartgallery.yaml` | Galería de las salidas (SmartGallery) en `galeria.danielriquelme.cl`. Ver [Galería](#galería). |
| `secret-smartgallery.sops.yaml` | `ADMIN_PASSWORD` (login de la galería) y `SECRET_KEY` (sesiones). Se aplica a mano con `sops -d … \| kubectl apply -f -`. |

## Actualizar

```bash
kubectl -n comfyui scale deploy/comfyui --replicas=0
kubectl delete job -n comfyui comfyui-build-env --ignore-not-found
kubectl apply -f cluster/apps/comfyui/06-job-build-env.yaml && kubectl -n comfyui logs -f job/comfyui-build-env
kubectl -n comfyui scale deploy/comfyui --replicas=1
```

Versiones fijadas en el Job: `TORCH_VERSION` (CUDA 12.8 porque el driver 570 del nodo no soporta CUDA 13),
`SAGEATTENTION_REF`. Las extensiones se instalan desde git en su última versión (`CUSTOM_NODES`); para
agregar una que use un workflow nuevo, sumarla a esa lista (o instalarla con el Manager y luego a la lista).

## Modelos

Inventario y decisiones en `models/MODELOS-COMFYUI.md` (en el volumen). Base única: **CyberRealistic
Z-Image Turbo v9.0 en INT8 ConvRot** con su codificador de texto INT8. En la serie 30 (sin fp8 por
hardware) INT8 ConvRot, nativo desde ComfyUI 0.27, rinde 1,5–2× más que fp8. Evitar nvfp4/mxfp8 (solo
Blackwell/Ada) y modelos que no caben en 8 GB (Krea 2, FLUX.2 dev).

Crear LoRAs de personaje a partir de imágenes del propio Z-Image Turbo: [`LORAS-PERSONAJES.md`](LORAS-PERSONAJES.md).

### LoRAs y trigger words

ComfyUI no lee las trigger words: si el LoRA tiene una, hay que escribirla en el prompt positivo; si
no, el LoRA se aplica más débil o no se nota. Al agregar un LoRA al Job, sacar la palabra de
`trainedWords` en `https://civitai.com/api/v1/model-versions/<modelVersionId>` y anotarla aquí. Dentro
de ComfyUI, el clic derecho → «Show info» del Power Lora Loader (rgthree) también la muestra.

| Archivo (`loras/`) | Trigger | Fuerza | Notas |
|---|---|---|---|
| `woman037-zimage.safetensors` | `woman037` | 1.0 | personaje |
| `woman992-ZIT.safetensors` | `woman992` | 1.0 | personaje |
| `Purple_grainy_zit.safetensors` | — | 1.0 | grano, desenfoque de bordes, color apagado; el autor usa euler/simple |
| `grainscape_zimage.safetensors` | — | 0.85–0.9 | película B/N tipo Tri-X, grano fuerte |
| `AnalogRedmond_zit.safetensors` | `AnalogRedmAF` | 1.0 | foto analógica; `detailed`, `minimalist`, `colorful` o `black and white` orientan el resultado |

El workflow `z-image-turbo---upscaling` nunca funcionó (requiere SeedVR2, Florence2, UltimateSDUpscale y
controlnet_aux, no instalados). Los originales de los workflows previos al cambio de modelos están en
`user/default/workflows-originales-20261003/`.

## Acceso

`comfyui.danielriquelme.cl` está detrás de **Cloudflare Access** (app «Homelab admin», política
`BlockAllbyMe`): login con código enviado al correo, sesión de 24 h.

Desde la casa o el tailnet conviene entrar directo, sin pasar por Cloudflare: cada imagen (PNG de ~4 MB)
sale a internet y vuelve por el túnel. `04-service-nodeport.yaml` expone el puerto 30188 (sin login):

- **LAN:** `http://192.168.1.131:30188` (k3s-node-1, donde corre el pod)
- **LAN por nombre:** `http://comfyui.lan` (Ingress; requiere la línea de `/etc/hosts` de la sección Galería)
- **Tailscale:** `http://k3s-node-1-k3s:30188`

El navegador trata cada URL como un sitio distinto: los ajustes del frontend guardados en `localStorage`
no se comparten (los workflows sí, viven en el servidor).

## Galería

[SmartGallery](https://github.com/biagiomaf/smart-comfyui-gallery) (`08-smartgallery.yaml`) muestra `output/`
con el prompt, modelo, LoRA y workflow de cada imagen; permite favoritos, estrellas, colecciones y mover o
borrar en lote. Funciona aunque ComfyUI esté apagado. Detalles:

- **Acceso:** `galeria.danielriquelme.cl`, login con usuario `admin` y la contraseña de
  `sops -d cluster/apps/comfyui/secret-smartgallery.sops.yaml`. Debe estar además en la app «Homelab admin»
  de Cloudflare Access (el túnel tiene comodín: sin Access, el Ingress queda público).
- **LAN:** `http://galeria.lan` (Ingress; requiere `192.168.1.131 galeria.lan comfyui.lan` en `/etc/hosts`).
- **LAN/tailnet:** `http://192.168.1.131:30189` o `http://k3s-node-1-k3s:30189` (NodePort, sin pasar por
  Cloudflare; pide el mismo login de SmartGallery).
- **Estado:** base SQLite, miniaturas y zips en `smartgallery/` del mismo volumen.
- **Arranque:** indexa todo antes de abrir el puerto (~7 archivos/s); el startup probe da 30 min.
- **Nodo:** solo `k3s-node-1`: NumPy de la imagen exige x86-64-v2 y `k3s-node-2`/`-3` son VMs con CPU
  genérica de KVM.
- **Borrado:** definitivo (sin `DELETE_TO`); se recupera desde los snapshots diarios de sanoid.

**Carpetas por fecha:** los `SaveImage` de los workflows guardados usan `filename_prefix` =
`%date:yyyy-MM-dd%/<nombre>`; el frontend lo reemplaza con la fecha local del navegador al encolar. En
workflows nuevos, usar el mismo patrón. Los prefijos anteriores quedaron en
`user/default/workflows-antes-fecha-20261005/`.

## GPU compartida

Time-slicing no reparte VRAM: si Plex transcodifica o Ollama tiene un modelo cargado mientras ComfyUI
genera, ComfyUI descarga parte del modelo a RAM (más lento) o puede quedarse sin memoria. Ver uso con
`kubectl -n ollama-stack exec deploy/ollama -- nvidia-smi`.

## Problemas comunes

- **Pod en Init `check-env`:** falta el entorno → ejecutar `06-job-build-env.yaml`.
- **"no available server" tras el login:** pod no listo (`kubectl -n comfyui logs deploy/comfyui`) o WebSocket
  `/ws` bloqueado.
