# Unsloth – Fine-tuning LLM en el homelab

Entorno [Unsloth](https://unsloth.ai) en Jupyter Lab para entrenar Qwen2.5-Coder (y otros modelos) con LoRA o fine-tuning. Usa la misma GPU que Plex/ComfyUI (nodo `media-worker`).

## Prerrequisitos

- Nodo k3s con GPU y label `node-role.kubernetes.io/media-worker=true`
- Dataset NFS en TrueNAS: `homelab-storage/llm` (path `/mnt/homelab-storage/llm`)
- NVIDIA device plugin y runtime aplicados en el cluster

## Crear dataset en TrueNAS

```bash
export TRUENAS_API_KEY="tu-api-key"
./setup-truenas-dataset.sh
```

O crear manualmente en TrueNAS el dataset `llm` bajo el pool `homelab-storage`.

## Desplegar

```bash
kubectl apply -k cluster/apps/unsloth/
```

Añadir en el túnel de Cloudflare el hostname `unsloth.danielriquelme.cl` si usas configuración remota (en este repo ya está en `cluster/06-external/cloudflared/configmap-tunnel.yml`).

## Acceso

- **URL:** https://unsloth.danielriquelme.cl
- **Auth:** Basic auth (usuario/contraseña en el Secret `unsloth-basic-auth`). Dentro, Jupyter pide contraseña (por defecto `unsloth`, configurable con env `JUPYTER_PASSWORD` en el Deployment).

## Uso: entrenar Qwen2.5-Coder

1. Abre Jupyter Lab y ve a `/workspace/work` (persistido en NFS).
2. Usa los notebooks de Unsloth o la [documentación](https://docs.unsloth.ai) para:
   - Cargar `Qwen/Qwen2.5-Coder-7B-Instruct` o `Qwen2.5-Coder-3B-Instruct`
   - Preparar tu dataset (p. ej. codebase en formato chat)
   - Ejecutar fine-tuning/LoRA
3. **Exportar:** `save_pretrained_merged(..., save_method="merged_16bit")` a una carpeta bajo `/workspace/work/exported/`.

## Bajar cuando no entreno

Para liberar la GPU:

```bash
kubectl scale deployment unsloth -n unsloth --replicas=0
```

## Seguridad

- Cambiar contraseña de Jupyter en producción (env o Secret `unsloth-jupyter-secret`).
- Regenerar basic auth: `htpasswd -nb unsloth NUEVA_PASS | base64 -w0` y actualizar el Secret `unsloth-basic-auth`.
