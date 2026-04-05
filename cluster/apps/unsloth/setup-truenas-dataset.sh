#!/usr/bin/env bash
# Crear dataset y (opcional) share NFS para Unsloth/qwen-coder en TrueNAS.
# Ejecutar desde tu máquina con acceso a la API de TrueNAS (o desde un host con curl).
# Requiere TRUENAS_API_KEY en el entorno o en homelab_vars.yml.
set -e
TRUENAS_HOST="${TRUENAS_HOST:-192.168.1.20}"
POOL="${POOL:-homelab-storage}"
DATASET="${DATASET:-llm}"
# API key: export TRUENAS_API_KEY="tu-key" o usar la de ansible/vars
if [ -z "$TRUENAS_API_KEY" ]; then
  echo "Export TRUENAS_API_KEY con tu API key de TrueNAS."
  exit 1
fi
BASE="https://${TRUENAS_HOST}/api/v2.0"
CURL_OPTS=(-k -s -H "Authorization: Bearer ${TRUENAS_API_KEY}" -H "Content-Type: application/json")

# Crear dataset
echo "Creando dataset ${POOL}/${DATASET}..."
curl "${CURL_OPTS[@]}" -X POST "${BASE}/pool/dataset" \
  -d "{\"name\": \"${POOL}/${DATASET}\"}" || true

# Verificar
curl "${CURL_OPTS[@]}" "${BASE}/pool/dataset?limit=100" | jq '.[] | select(.name | contains("llm")) | .name'
echo "Dataset listo. Path NFS: /mnt/${POOL}/${DATASET}"
