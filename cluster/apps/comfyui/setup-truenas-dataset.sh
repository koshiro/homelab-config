#!/usr/bin/env bash
# Crea el dataset y share NFS para ComfyUI en TrueNAS.
# Requiere .truenas-api-key en la raíz del repo.
# Ejecutar antes del primer despliegue: ./setup-truenas-dataset.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
API_KEY_FILE="${REPO_ROOT}/.truenas-api-key"
TRUENAS_IP="192.168.1.20"
DATASET_NAME="homelab-storage/comfyui"
NFS_PATH="/mnt/${DATASET_NAME}"
AUTHORIZED_NETWORK="192.168.1.0/24"

if [ ! -f "${API_KEY_FILE}" ]; then
    echo "ERROR: No se encontró ${API_KEY_FILE}"
    echo "Crea el archivo con tu API key de TrueNAS."
    exit 1
fi
API_KEY=$(cat "${API_KEY_FILE}")

api() {
    local method=$1 endpoint=$2 data=$3
    if [ -n "${data}" ]; then
        curl -k -s -X "${method}" "https://${TRUENAS_IP}/api/v2.0/${endpoint}" \
            -H "Authorization: Bearer ${API_KEY}" \
            -H "Content-Type: application/json" \
            -d "${data}"
    else
        curl -k -s -X "${method}" "https://${TRUENAS_IP}/api/v2.0/${endpoint}" \
            -H "Authorization: Bearer ${API_KEY}"
    fi
}

echo "=== Setup dataset ComfyUI en TrueNAS ==="

# Verificar si el dataset ya existe
EXISTING=$(api "GET" "pool/dataset?limit=1000" 2>/dev/null | jq -r --arg name "${DATASET_NAME}" '.[] | select(.name == $name) | .name' 2>/dev/null || true)
if [ -n "${EXISTING}" ]; then
    echo "Dataset ${DATASET_NAME} ya existe."
else
    echo "Creando dataset ${DATASET_NAME}..."
    # POST pool/dataset - name es el path completo
    RESULT=$(api "POST" "pool/dataset" "{\"name\": \"${DATASET_NAME}\", \"type\": \"FILESYSTEM\"}" 2>/dev/null || true)
    if echo "${RESULT}" | jq -e .id >/dev/null 2>&1 || echo "${RESULT}" | jq -e .name >/dev/null 2>&1; then
        echo "Dataset creado correctamente."
    elif echo "${RESULT}" | grep -q "already exists"; then
        echo "Dataset ya existía."
    else
        echo "Respuesta API: ${RESULT}"
        echo "Si falla, crear manualmente en TrueNAS: Storage → Datasets → Add Dataset → homelab-storage/comfyui"
        exit 1
    fi
fi

# Crear share NFS si no existe
SHARES=$(api "GET" "sharing/nfs" 2>/dev/null || true)
ID=$(echo "${SHARES}" | jq -r --arg path "${NFS_PATH}" '.[] | select(.path == $path) | .id' 2>/dev/null | head -1)
if [ -n "${ID}" ] && [ "${ID}" != "null" ]; then
    echo "Share NFS para ${NFS_PATH} ya existe (id=${ID})."
    echo "Actualizando redes autorizadas..."
    CURRENT=$(echo "${SHARES}" | jq -r --arg id "${ID}" '.[] | select(.id == ($id | tonumber))')
    UPDATE=$(echo "${CURRENT}" | jq -c --arg net "${AUTHORIZED_NETWORK}" '{path: .path, comment: .comment, enabled: .enabled, networks: [$net], hosts: (if .hosts then .hosts else [] end)}')
    api "PUT" "sharing/nfs/id/${ID}" "${UPDATE}" >/dev/null 2>&1 && echo "Share actualizado." || true
else
    echo "Creando share NFS para ${NFS_PATH}..."
    api "POST" "sharing/nfs" "{\"path\": \"${NFS_PATH}\", \"comment\": \"ComfyUI models and output\", \"enabled\": true, \"networks\": [\"${AUTHORIZED_NETWORK}\"], \"hosts\": []}" >/dev/null 2>&1
    echo "Share NFS creado."
fi

# Crear estructura de directorios en el dataset (evita Permission denied)
echo "Creando estructura de directorios vía API TrueNAS..."
for dir in models input output user temp custom_nodes user/default venv; do
    api "POST" "filesystem/mkdir" "{\"path\": \"${NFS_PATH}/${dir}\"}" >/dev/null 2>&1 || true
done
# Permisos 0777 para que el contenedor pueda crear subdirs (p. ej. user/default)
for sub in "${NFS_PATH}" "${NFS_PATH}/models" "${NFS_PATH}/input" "${NFS_PATH}/output" \
  "${NFS_PATH}/user" "${NFS_PATH}/user/default" "${NFS_PATH}/temp" "${NFS_PATH}/custom_nodes" "${NFS_PATH}/venv"; do
    api "POST" "filesystem/setperm" "{\"path\": \"${sub}\", \"mode\": \"0777\"}" >/dev/null 2>&1 || true
done
echo "Directorios creados."

echo ""
echo "Completado. El PV de Kubernetes debe apuntar a: ${NFS_PATH}"
echo ""
