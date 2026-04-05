#!/usr/bin/env bash
# Solo lectura: muestra el estado real del dataset ComfyUI y shares en TrueNAS.
# No modifica nada. Úsalo para revisar antes de cambiar permisos o SMB.
#
# Requiere: .truenas-api-key en la raíz del repo (igual que setup-truenas-dataset.sh)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
API_KEY_FILE="${REPO_ROOT}/.truenas-api-key"

TRUENAS_IP="192.168.1.20"
DATASET_NAME="homelab-storage/comfyui"
DATASET_PATH="/mnt/${DATASET_NAME}"

if [ ! -f "${API_KEY_FILE}" ]; then
    echo "ERROR: No se encontró ${API_KEY_FILE}"
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

echo "=============================================="
echo "Estado TrueNAS - ComfyUI (solo lectura)"
echo "=============================================="
echo ""

# 1) Dataset
echo "--- 1) Dataset ${DATASET_NAME} ---"
DATASETS="$(api GET "pool/dataset?limit=1000" 2>/dev/null || echo "[]")"
DS="$(echo "${DATASETS}" | jq -r --arg name "${DATASET_NAME}" '.[] | select(.name == $name)' 2>/dev/null || true)"
if [ -z "${DS}" ] || [ "${DS}" = "null" ]; then
    echo "No encontrado o API falló."
    echo "Respuesta cruda (primeros 500 chars):"
    echo "${DATASETS}" | head -c 500
    echo ""
else
    echo "${DS}" | jq -C .
fi
echo ""

# 2) SMB shares que apuntan a nuestro path
echo "--- 2) SMB share(s) con path ${DATASET_PATH} ---"
SMB_LIST="$(api GET "sharing/smb" 2>/dev/null || echo "[]")"
SMB_OUR="$(echo "${SMB_LIST}" | jq -r --arg p "${DATASET_PATH}" '[.[] | select(.path == $p)]' 2>/dev/null || echo "[]")"
if [ -z "${SMB_OUR}" ] || [ "${SMB_OUR}" = "[]" ]; then
    echo "Ningún SMB share usa este path."
    echo "Todos los SMB shares (paths):"
    echo "${SMB_LIST}" | jq -r '.[].path' 2>/dev/null || echo "${SMB_LIST}"
else
    echo "${SMB_OUR}" | jq -C .
fi
echo ""

# 3) NFS share (el que usa ComfyUI en k8s) — no tocar
echo "--- 3) NFS share para ${DATASET_PATH} (usado por ComfyUI) ---"
NFS_LIST="$(api GET "sharing/nfs" 2>/dev/null || echo "[]")"
NFS_OUR="$(echo "${NFS_LIST}" | jq -r --arg p "${DATASET_PATH}" '[.[] | select(.path == $p)]' 2>/dev/null || echo "[]")"
if [ -z "${NFS_OUR}" ] || [ "${NFS_OUR}" = "[]" ]; then
    echo "Ningún NFS share con este path."
else
    echo "${NFS_OUR}" | jq -C .
fi
echo ""

# 4) Intentar stat del path (si la API lo expone)
echo "--- 4) filesystem/stat de ${DATASET_PATH} (si existe endpoint) ---"
STAT_RESP="$(api POST "filesystem/stat" "{\"path\": \"${DATASET_PATH}\"}" 2>/dev/null || true)"
if echo "${STAT_RESP}" | jq -e . >/dev/null 2>&1; then
    echo "${STAT_RESP}" | jq -C .
else
    echo "Endpoint no disponible o error (no cambiar nada)."
    [ -n "${STAT_RESP}" ] && echo "Respuesta: ${STAT_RESP}"
fi
echo ""

# 5) Intentar getacl del path (si la API lo expone)
echo "--- 5) filesystem/getacl de ${DATASET_PATH} (raíz) ---"
ACL_RESP="$(api POST "filesystem/getacl" "{\"path\": \"${DATASET_PATH}\"}" 2>/dev/null || true)"
if echo "${ACL_RESP}" | jq -e .path >/dev/null 2>&1; then
    echo "${ACL_RESP}" | jq -C '{path, uid, gid, acltype, trivial, acl}'
else
    echo "Endpoint no disponible o error."
    [ -n "${ACL_RESP}" ] && echo "Respuesta: ${ACL_RESP}"
fi
echo ""

# 6) ACL de subdirectorios (donde suele fallar escritura SMB si tienen otro owner/permisos)
echo "--- 6) getacl ${DATASET_PATH}/output ---"
ACL_OUT="$(api POST "filesystem/getacl" "{\"path\": \"${DATASET_PATH}/output\"}" 2>/dev/null || true)"
if echo "${ACL_OUT}" | jq -e .path >/dev/null 2>&1; then
    echo "${ACL_OUT}" | jq -C '{path, uid, gid, acltype, trivial, acl}'
else
    echo "No disponible o error."; [ -n "${ACL_OUT}" ] && echo "${ACL_OUT}"
fi
echo "--- 7) getacl ${DATASET_PATH}/models ---"
ACL_MOD="$(api POST "filesystem/getacl" "{\"path\": \"${DATASET_PATH}/models\"}" 2>/dev/null || true)"
if echo "${ACL_MOD}" | jq -e .path >/dev/null 2>&1; then
    echo "${ACL_MOD}" | jq -C '{path, uid, gid, acltype, trivial, acl}'
else
    echo "No disponible o error."; [ -n "${ACL_MOD}" ] && echo "${ACL_MOD}"
fi
echo ""

echo "=============================================="
echo "Fin del informe. No se ha modificado nada."
echo "=============================================="
