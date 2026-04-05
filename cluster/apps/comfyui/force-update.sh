#!/bin/bash
# Fuerza actualización de ComfyUI: aplica deployment y reinicia el pod.
# Estructura unificada: todo bajo /app (un solo mount). Init: app, Manager, venv.
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
echo "Aplicando deployment y reiniciando comfyui (forzando actualización)..."
kubectl apply -f "$DIR/00-deployment.yaml"
kubectl rollout restart deployment/comfyui -n comfyui
echo "Esperando que el pod termine init (~1-2 min)..."
kubectl rollout status deployment/comfyui -n comfyui --timeout=180s
echo "Listo."
