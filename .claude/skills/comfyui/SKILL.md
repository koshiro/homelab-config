---
name: comfyui
description: Operar y depurar ComfyUI del homelab (namespace comfyui, RTX 3070 en k3s-node-1) - Media Assets, assets de output/input, LoadImage y rutas [output], workflows que no encuentran imágenes, nodos marcados como faltantes, frontend (comfyui-frontend-package), custom nodes, flags de arranque, actualizar ComfyUI o el entorno, SmartGallery y modelos. Usar SIEMPRE que la tarea toque ComfyUI, antes de explorar el pod o el repo. Prompts para Z-Image van a la skill z-image-turbo-prompting.
---

# ComfyUI

Manifiestos en `cluster/apps/comfyui/` (README con acceso, galería, modelos y cómo actualizar). Todo el estado
vive en el NFS `/app` (código, venv, custom_nodes, modelos, `user/`, `output/`). Cambios en los manifiestos: PR y
merge; los aplica Flux (desde 2026-10-16), no `kubectl apply -k`. El ConfigMap del shim lleva hash y reinicia el deployment.

```bash
C="python3 -I .claude/skills/comfyui/comfy.py"
$C assets                     # output/ en disco vs BD de assets, más nuevos y user_metadata de muestra
$C src <archivo-re> [<línea-re>]   # fuentes TS/Vue del frontend instalado (sourcemaps): la verdad, no la doc
$C show <sufijo.ts> [desde] [hasta]
$C api '/api/assets?include_tags=output&limit=2'   # API interna desde el pod (sin Cloudflare Access)
$C logs [regex]
```

UI para probar con el navegador: `http://192.168.1.15:30188` (NodePort; el dominio pide Access). El objeto
`window.app` (o `window.comfyAPI.app.app`) permite leer `app.graph._nodes` y valores de widgets.

## Cómo funciona (0.38 / frontend 1.53)

- **`--enable-assets`** activa la BD `/app/user/comfyui.db` (SQLite) y el escaneo de `models`, `input`,
  `output`. Sin ella, Media Assets sale del historial de trabajos, que vive en memoria y se pierde al reiniciar.
- **Historial** (`/api/jobs`, `PromptQueue.history`): en memoria, máx. 10 000. Nada lo persiste.
- **Valores de LoadImage**: `nombre.png` = `input/`; `sub/nombre.png [output]` = `output/sub/`. El backend
  acepta ambos; el desplegable solo lista la raíz de `input/`.
- **Media input missing**: para valores `[output]` el frontend OSS solo busca en `/api/jobs` (y solo el
  `preview_output` de cada trabajo). Tras reiniciar, todo `[output]` aparece faltante: es un falso positivo y
  **no bloquea Run** (solo cambia icono y tooltip; el backend valida y ejecuta).
- **Insertar asset como nodo** (`useMediaAssetActions.createAssetWidgetPath`): usa `asset.name` +
  `user_metadata.subfolder`. El backend no llena ese campo → lo agrega el shim
  `cluster/apps/comfyui/custom-nodes/homelab_asset_subfolder` (envuelve los builders de
  `app/assets/api/routes.py`). Sin el shim, `2026-10-14/x.png` se insertaba como `x.png [output]`: nodo vacío u
  otra imagen (hay cientos de nombres repetidos entre carpetas).
- Las salidas van a carpetas por fecha (`%date:yyyy-MM-dd%/…`), así que todo lo anterior afecta a casi todo.

## Trampas

- Primer escaneo de assets: `created_at` = hora del escaneo → orden revuelto en el panel. Se corrigió en la
  BD con el mtime (respaldo `comfyui.db.bak-*`); si se borra la BD, repetir (`asset_contents.mtime_ns`).
- Al actualizar ComfyUI o el frontend, revisar con `$C logs homelab_asset` que el shim cargó y con
  `$C src useMediaAssetActions createAssetWidgetPath` si upstream ya usa `loader_path` (TODO BE-933/934): en
  ese caso retirar el shim.
- Actualizar el entorno (`06-job-build-env.yaml`, ver README § Actualizar) con solo `kubectl scale --replicas=0` →
  Flux devuelve ComfyUI a 1 réplica en ≤10 min, a mitad del Job (`replicas: 1` en git): `flux suspend ks comfyui`
  antes y `flux resume ks comfyui` al terminar. Versiones reales: PyTorch 2.14.1+cu130, driver 580. (2026-10-16)
- No probar cambios encolando el workflow del usuario: un grafo mínimo `LoadImage → PreviewImage` por
  `POST /api/prompt` valida rutas sin gastar GPU (sale a `temp/`, se borra al reiniciar).
- El usuario no quiere un custom node para persistir el historial (2026-10-15); las imágenes `[output]` de un
  workflow se reseleccionan desde Media Assets.

## Ciclo de aprendizaje

Igual que la skill `homelab`: secuencia repetida → subcomando en `comfy.py`; error con arreglo → Trampas;
bitácora en `.claude/skills/homelab/references/bitacora.md`.
