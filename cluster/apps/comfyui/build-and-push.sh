#!/usr/bin/env bash
# Construye y publica ghcr.io/koshiro/comfyui-homelab:latest (incluye git + gcc/g++ para Triton/SageAttention).
#
# Requisitos:
#   - Docker en ejecución (OrbStack / Docker Desktop / etc.)
#   - Sesión GHCR:  echo TOKEN | docker login ghcr.io -u USER --password-stdin
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
IMAGE="${IMAGE:-ghcr.io/koshiro/comfyui-homelab:latest}"

echo "==> Build ${IMAGE} (platform linux/amd64 — cluster k3s)"
docker build --platform linux/amd64 -t "${IMAGE}" -f "${ROOT}/Dockerfile" "${ROOT}"

echo "==> Push ${IMAGE}"
docker push "${IMAGE}"

echo "==> Listo. Actualiza el cluster con Flux o: kubectl rollout restart deployment/comfyui -n comfyui"
