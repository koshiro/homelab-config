#!/usr/bin/env bash
# Crea/actualiza un SMB share para el dataset de ComfyUI en TrueNAS.
# Así puedes:
#   - Copiar modelos fácilmente (\\truenas\comfyui\models)
#   - Ver las imágenes generadas (\\truenas\comfyui\output)
#
# Requiere:
#   - Archivo .truenas-api-key en la raíz del repo (mismo que usa setup-truenas-dataset.sh)
#   - Servicio SMB habilitado en TrueNAS (Services → SMB → Start + Enable)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
API_KEY_FILE="${REPO_ROOT}/.truenas-api-key"

TRUENAS_IP="192.168.1.20"
DATASET_NAME="homelab-storage/comfyui"
DATASET_PATH="/mnt/${DATASET_NAME}"
SMB_NAME="comfyui"

if [ ! -f "${API_KEY_FILE}" ]; then
    echo "ERROR: No se encontró ${API_KEY_FILE}"
    echo "Crea el archivo con tu API key de TrueNAS (mismo archivo que para setup-truenas-dataset.sh)."
    exit 1
fi
API_KEY="$(cat "${API_KEY_FILE}")"

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

echo "=== Setup SMB share ComfyUI en TrueNAS ==="

# Verificar que el dataset existe
EXISTING_DATASET="$(api GET "pool/dataset?limit=1000" 2>/dev/null | jq -r --arg name "${DATASET_NAME}" '.[] | select(.name == $name) | .name' 2>/dev/null || true)"
if [ -z "${EXISTING_DATASET}" ]; then
    echo "ERROR: El dataset ${DATASET_NAME} no existe todavía."
    echo "Primero ejecuta: ./setup-truenas-dataset.sh"
    exit 1
fi

# Comprobar si ya existe un SMB share apuntando al dataset
SMB_SHARES="$(api GET "sharing/smb" 2>/dev/null || true)"
SMB_ID="$(echo "${SMB_SHARES}" | jq -r --arg path "${DATASET_PATH}" '.[] | select(.path == $path) | .id' 2>/dev/null | head -1)"

if [ -n "${SMB_ID}" ] && [ "${SMB_ID}" != "null" ]; then
    echo "SMB share para ${DATASET_PATH} ya existe (id=${SMB_ID})."
    echo "Asegurando que no esté en solo lectura..."
    CURRENT="$(echo "${SMB_SHARES}" | jq -r --arg id "${SMB_ID}" '.[] | select(.id == ($id | tonumber))')"
    if [ -n "${CURRENT}" ]; then
        UPDATE="$(echo "${CURRENT}" | jq -c 'del(.id) | .readonly = false')"
        api "PUT" "sharing/smb/id/${SMB_ID}" "${UPDATE}" >/dev/null 2>&1 && echo "Share actualizado (readonly=false)." || true
    fi
else
    echo "Creando SMB share para ${DATASET_PATH}..."
    # purpose = MULTIPROTOCOL_SHARE porque el mismo path se usa vía NFS y por pods de Kubernetes.
    # readonly = false explícito para poder copiar modelos y crear archivos desde el cliente SMB.
    PAYLOAD="$(jq -nc \
      --arg path "${DATASET_PATH}" \
      --arg name "${SMB_NAME}" \
      --arg comment "ComfyUI workspace (models/input/output/user)" \
      '{path: $path, name: $name, comment: $comment, enabled: true, readonly: false, purpose: "MULTIPROTOCOL_SHARE"}')"

    RESULT="$(api POST "sharing/smb" "${PAYLOAD}" 2>/dev/null || true)"

    if echo "${RESULT}" | jq -e '.id' >/dev/null 2>&1; then
        ID_CREATED="$(echo "${RESULT}" | jq -r '.id')"
        echo "SMB share creado correctamente (id=${ID_CREATED})."
    elif echo "${RESULT}" | grep -qi "already exists"; then
        echo "El SMB share ya existía según la API."
    else
        echo "Respuesta API SMB: ${RESULT}"
        echo "Si falla, puedes crear el share manualmente en TrueNAS:"
        echo "  Shares → Windows Shares (SMB) → Add"
        echo "  - Path: ${DATASET_PATH}"
        echo "  - Name: ${SMB_NAME}"
        echo "  - Purpose: MULTIPROTOCOL_SHARE"
        echo "  - Read Only: desmarcado"
        exit 1
    fi
fi

# Aplicar permisos Unix 0777 al dataset y subdirs para que el usuario SMB pueda escribir.
# (TrueNAS SMB mapea el usuario de red a Unix; sin esto puede quedar solo lectura.)
echo "Aplicando permisos de escritura (0777) al dataset y subdirectorios..."
for sub in "${DATASET_PATH}" "${DATASET_PATH}/models" "${DATASET_PATH}/input" "${DATASET_PATH}/output" "${DATASET_PATH}/user" "${DATASET_PATH}/user/default" "${DATASET_PATH}/custom_nodes" "${DATASET_PATH}/venv"; do
    api "POST" "filesystem/setperm" "{\"path\": \"${sub}\", \"mode\": \"0777\"}" >/dev/null 2>&1 || true
done
echo "Permisos aplicados."

echo ""
echo "Listo."
echo "Ahora deberías ver el share SMB '${SMB_NAME}' en tu red (\\${TRUENAS_IP}\\${SMB_NAME} o \\\\truenas\\${SMB_NAME})."
echo "- Modelos:    \\${TRUENAS_IP}\\${SMB_NAME}\\models"
echo "- Imágenes:   \\${TRUENAS_IP}\\${SMB_NAME}\\output"
echo "- Workflows:  \\${TRUENAS_IP}\\${SMB_NAME}\\user"
echo ""
