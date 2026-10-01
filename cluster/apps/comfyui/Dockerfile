# Imagen ComfyUI para homelab: jemeyer + git + deps Manager
# Evita apt-get y pip install en cada arranque.
#
# Build: docker build -t ghcr.io/<tu-usuario>/comfyui-homelab:latest .
# Push:  docker push ghcr.io/<tu-usuario>/comfyui-homelab:latest
# Luego cambiar en 00-deployment.yaml: image: ghcr.io/<tu-usuario>/comfyui-homelab:latest
#
FROM ghcr.io/jemeyer/comfyui:latest

USER root
# gcc/g++: Triton (p. ej. rutas SageAttention/auto) JIT-compile utilidades CUDA y fallan sin CC.
# Sin esto: RuntimeError: Failed to find C compiler (triton/backends/nvidia/driver.py).
RUN apt-get update && apt-get install -y --no-install-recommends git gcc g++ \
  && rm -rf /var/lib/apt/lists/*

# Deps mínimas para ComfyUI-Manager (GitPython, toml, etc.) + ComfyUI app (sqlalchemy, comfy-aimdo)
# El resto (transformers, uv) se instala a demanda o en venv persistente
RUN /venv/bin/pip install --no-cache-dir -q \
  GitPython toml PyGithub typer rich typing-extensions chardet sqlalchemy comfy-aimdo
