#!/usr/bin/env bash
# Crea un snapshot ZFS en TrueNAS del dataset de Minecraft (respaldo antes de cambios).
# Usa .truenas-api-key desde la raíz del repo.
# Ejecutar: ./backup-snapshot-truenas.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
API_KEY_FILE="${REPO_ROOT}/.truenas-api-key"
TRUENAS_IP="192.168.1.20"

# Dataset en uso en el cluster (path NFS: /mnt/homelab-storage/minecraft-server)
DATASETS=("homelab-storage/minecraft-server")
SNAPSHOT_NAME="manual-$(date +%Y%m%d-%H%M)"

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
        curl -k -s -w "\n%{http_code}" -X "${method}" "https://${TRUENAS_IP}/api/v2.0/${endpoint}" \
            -H "Authorization: Bearer ${API_KEY}" \
            -H "Content-Type: application/json" \
            -d "${data}"
    else
        curl -k -s -w "\n%{http_code}" -X "${method}" "https://${TRUENAS_IP}/api/v2.0/${endpoint}" \
            -H "Authorization: Bearer ${API_KEY}"
    fi
}

echo "=== Respaldo Minecraft (snapshots ZFS en TrueNAS) ==="
echo "Fecha: $(date)"
echo ""

for dataset in "${DATASETS[@]}"; do
    full_name="${dataset}@${SNAPSHOT_NAME}"
    echo "Creando snapshot: ${full_name} ..."
    # Intentar body con "name" completo (dataset@snapshot) por si la API lo espera así
    resp=$(api "POST" "zfs/snapshot" "{\"name\": \"${full_name}\"}" 2>/dev/null || true)
    http_code=$(echo "$resp" | tail -1)
    body=$(echo "$resp" | sed '$d')

    if [ "$http_code" = "200" ] || echo "$body" | jq -e '.id' >/dev/null 2>&1; then
        echo "  OK: snapshot creado."
    else
        # Fallback: dataset + name por separado
        resp=$(api "POST" "zfs/snapshot" "{\"dataset\": \"${dataset}\", \"name\": \"${SNAPSHOT_NAME}\"}" 2>/dev/null || true)
        http_code=$(echo "$resp" | tail -1)
        body=$(echo "$resp" | sed '$d')
        if [ "$http_code" = "200" ] || echo "$body" | jq -e '.id' >/dev/null 2>&1; then
            echo "  OK: snapshot creado."
        elif echo "$body" | jq -e '.message' >/dev/null 2>&1; then
            err=$(echo "$body" | jq -r '.message')
            if echo "$err" | grep -qi "does not exist\|not found"; then
                echo "  (omitido: dataset ${dataset} no existe en TrueNAS)"
            else
                echo "  Error: $err"
            fi
        else
            echo "  API devolvió HTTP $http_code. Crear snapshot manualmente en TrueNAS:"
            echo "    Storage → Snapshots → Add → Dataset: ${dataset} → Name: ${SNAPSHOT_NAME}"
        fi
    fi
    echo ""
done

echo "Si la API falló (404), crear snapshot manualmente en TrueNAS:"
echo "  Storage → Snapshots → Add → Dataset: homelab-storage/minecraft-server → Name: ${SNAPSHOT_NAME}"
echo ""
echo "Para ver snapshots en TrueNAS: Storage → Snapshots"
echo "O por API: curl -k -s -H \"Authorization: Bearer \$(cat ${API_KEY_FILE})\" \"https://${TRUENAS_IP}/api/v2.0/zfs/snapshot\" | jq"
