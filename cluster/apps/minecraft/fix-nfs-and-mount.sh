#!/usr/bin/env bash
# Arregla el share NFS de Minecraft en TrueNAS (autoriza red) y muestra el comando para montar.
# Usa .truenas-api-key desde la raíz del repo.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
API_KEY_FILE="${REPO_ROOT}/.truenas-api-key"
TRUENAS_IP="192.168.1.20"
NFS_PATH="/mnt/homelab-storage/minecraft-server"
MOUNT_POINT="${HOME}/minecraft-server-data"
AUTHORIZED_NETWORK="192.168.1.0/24"

if [ ! -f "${API_KEY_FILE}" ]; then
    echo "ERROR: No se encontró ${API_KEY_FILE}"
    exit 1
fi
API_KEY=$(cat "${API_KEY_FILE}")

api() {
    local method=$1
    local endpoint=$2
    local data=$3
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

echo "Buscando share NFS para ${NFS_PATH}..."
# TrueNAS REST: sharing/nfs devuelve lista de shares
SHARES=$(api "GET" "sharing/nfs" 2>/dev/null || true)
if [ -z "${SHARES}" ] || [ "${SHARES}" = "[]" ]; then
    echo "No se pudo listar NFS shares o no hay ninguno. Comprueba la API key y que exista el share en TrueNAS."
    echo "Puedes autorizar la red manualmente: TrueNAS → Sharing → NFS → editar el share de minecraft → Authorized networks: 192.168.1.0/24"
else
    # Encontrar id del share cuyo path sea el de minecraft
    ID=$(echo "${SHARES}" | jq -r --arg path "${NFS_PATH}" '.[] | select(.path == $path) | .id' 2>/dev/null | head -1)
    if [ -n "${ID}" ] && [ "${ID}" != "null" ]; then
        echo "Share encontrado (id=${ID}). Actualizando redes autorizadas a ${AUTHORIZED_NETWORK}..."
        CURRENT=$(echo "${SHARES}" | jq -r --arg id "${ID}" '.[] | select(.id == ($id | tonumber))')
        UPDATE=$(echo "${CURRENT}" | jq -c --arg net "${AUTHORIZED_NETWORK}" '{path: .path, comment: .comment, enabled: .enabled, networks: [$net], hosts: (if .hosts then .hosts else [] end)}')
        api "PUT" "sharing/nfs/id/${ID}" "${UPDATE}" >/dev/null 2>&1 && echo "Share actualizado." || echo "No se pudo actualizar (puede que el API use otro formato)."
    else
        echo "No existe share para ${NFS_PATH}. Creando share NFS con red ${AUTHORIZED_NETWORK}..."
        api "POST" "sharing/nfs" "{\"path\": \"${NFS_PATH}\", \"comment\": \"Minecraft server data\", \"enabled\": true, \"networks\": [\"${AUTHORIZED_NETWORK}\"], \"hosts\": []}" >/dev/null 2>&1 && echo "Share creado." || echo "No se pudo crear (puede que el path no exista en TrueNAS)."
    fi
fi

echo ""
echo "Comando para montar el directorio (ejecutar en tu Mac):"
echo ""
echo "  sudo mount -t nfs -o resvport,vers=3 ${TRUENAS_IP}:${NFS_PATH} ${MOUNT_POINT}"
echo ""
echo "Desmontar cuando termines:"
echo "  sudo umount ${MOUNT_POINT}"
echo ""
echo "Datapacks van en: ${MOUNT_POINT}/world/datapacks/"
echo ""
