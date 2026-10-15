"""Agrega user_metadata.subfolder/jobId a las respuestas de /api/assets para salidas (output/temp).

El frontend (comfyui-frontend-package 1.53–1.55) arma el valor del widget al insertar un asset como nodo con
`asset.name` + `user_metadata.subfolder` (useMediaAssetActions.createAssetWidgetPath). El backend no llena ese
campo, así que `output/2026-10-14/x.png` se insertaba como `x.png [output]`: nodo vacío u otra imagen con el
mismo nombre en la raíz. Se deriva el subfolder de loader_path sin tocar la BD ni el código de ComfyUI.
Retirar cuando upstream resuelva el TODO(BE-933/934) de getAssetStoredFilename.
"""
import logging

NODE_CLASS_MAPPINGS = {}

try:
    from app.assets.api import routes

    def _with_subfolder(asset):
        tags = asset.tags or []
        if not asset.loader_path or not ("output" in tags or "temp" in tags):
            return asset
        meta = dict(asset.user_metadata or {})
        meta.setdefault("subfolder", asset.loader_path.rpartition("/")[0])
        meta.setdefault("jobId", asset.job_id or "")
        return asset.model_copy(update={"user_metadata": meta})

    def _wrap(fn):
        def wrapper(*args, **kwargs):
            return _with_subfolder(fn(*args, **kwargs))
        wrapper.__wrapped__ = fn
        return wrapper

    for _name in ("_build_asset_response", "_build_record_response"):
        if not hasattr(getattr(routes, _name), "__wrapped__"):
            setattr(routes, _name, _wrap(getattr(routes, _name)))
    logging.info("[homelab_asset_subfolder] /api/assets con subfolder en user_metadata")
except Exception:
    logging.exception("[homelab_asset_subfolder] no se pudo aplicar; ¿cambió app.assets.api.routes?")
