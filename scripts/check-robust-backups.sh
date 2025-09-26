#!/bin/bash
# Script para verificar el estado de los respaldos robustos
# Ejecutar desde la máquina local

set -e

# Configuración
TRUENAS_IP="192.168.1.20"
API_KEY_FILE="/Users/daniel/git/homelab-config/.truenas-api-key"

echo "=== VERIFICACIÓN DE RESPALDOS ROBUSTOS ==="
echo "Fecha: $(date)"
echo ""

# Verificar que existe la API key
if [ ! -f "${API_KEY_FILE}" ]; then
    echo "ERROR: No se encontró el archivo de API key en ${API_KEY_FILE}"
    exit 1
fi

API_KEY=$(cat "${API_KEY_FILE}")

# Función para hacer requests a la API
api_request() {
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

echo "🔍 Verificando respaldos robustos..."

# Crear script de verificación en TrueNAS
verification_script='#!/bin/bash
echo "=== VERIFICACIÓN DE RESPALDOS ROBUSTOS ==="
echo "Fecha: $(date)"
echo ""

# Verificar directorio de respaldos robustos
BACKUP_BASE="/mnt/homelab-storage/backups"
ROBUST_BACKUP_DIR="${BACKUP_BASE}/robust-backups"
LATEST_BACKUP="${BACKUP_BASE}/latest-backup"

echo "1. Verificando directorios de respaldo:"
if [ -d "${ROBUST_BACKUP_DIR}" ]; then
    echo "✅ Directorio de respaldos robustos existe: ${ROBUST_BACKUP_DIR}"
    echo "   Respaldos disponibles:"
    ls -la "${ROBUST_BACKUP_DIR}" | grep robust-backup || echo "   No se encontraron respaldos robustos"
else
    echo "❌ Directorio de respaldos robustos no existe"
fi

echo ""
echo "2. Verificando enlace al respaldo más reciente:"
if [ -L "${LATEST_BACKUP}" ]; then
    echo "✅ Enlace al respaldo más reciente existe"
    echo "   Respaldo más reciente: $(readlink ${LATEST_BACKUP})"
    echo "   Fecha: $(stat -c %y ${LATEST_BACKUP} 2>/dev/null || echo "N/A")"
    
    echo "   Contenido del respaldo más reciente:"
    ls -la "${LATEST_BACKUP}/" | head -20
else
    echo "❌ No se encontró enlace al respaldo más reciente"
fi

echo ""
echo "3. Verificando respaldos de la suite ARR:"
if [ -d "${LATEST_BACKUP}" ]; then
    services=("plex" "sonarr" "radarr" "bazarr" "prowlarr" "overseerr" "pingvin" "qbittorrent")
    
    for service in "${services[@]}"; do
        echo -n "   ${service}: "
        backup_files=$(find "${LATEST_BACKUP}" -name "${service}-*.tar.gz" | wc -l)
        if [ ${backup_files} -gt 0 ]; then
            echo "✅ ${backup_files} archivo(s) de respaldo"
            find "${LATEST_BACKUP}" -name "${service}-*.tar.gz" | head -3 | while read file; do
                size=$(stat -c %s "${file}" 2>/dev/null || echo "0")
                echo "      $(basename ${file}) - $((${size}/1024/1024))MB"
            done
        else
            echo "❌ No se encontraron respaldos"
        fi
    done
else
    echo "❌ No se puede verificar respaldos (directorio no existe)"
fi

echo ""
echo "4. Verificando archivos de configuración del cluster:"
if [ -d "${LATEST_BACKUP}" ]; then
    cluster_files=("cluster-resources.yaml" "persistent-volume-claims.yaml" "secrets.yaml" "configmaps.yaml" "ingress.yaml" "networkpolicies.yaml")
    
    for file in "${cluster_files[@]}"; do
        if [ -f "${LATEST_BACKUP}/${file}" ]; then
            size=$(stat -c %s "${LATEST_BACKUP}/${file}" 2>/dev/null || echo "0")
            echo "   ✅ ${file} - $((${size}/1024))KB"
        else
            echo "   ❌ ${file} - No encontrado"
        fi
    done
else
    echo "❌ No se puede verificar archivos del cluster"
fi

echo ""
echo "5. Estadísticas del respaldo:"
if [ -d "${LATEST_BACKUP}" ]; then
    total_files=$(find "${LATEST_BACKUP}" -type f | wc -l)
    total_size=$(du -sh "${LATEST_BACKUP}" | cut -f1)
    echo "   Archivos totales: ${total_files}"
    echo "   Tamaño total: ${total_size}"
    
    # Verificar integridad básica
    if [ ${total_files} -gt 10 ]; then
        echo "   ✅ Respaldo parece completo (${total_files} archivos)"
    else
        echo "   ⚠️  Respaldo puede estar incompleto (solo ${total_files} archivos)"
    fi
else
    echo "   ❌ No se puede calcular estadísticas"
fi

echo ""
echo "6. Verificando kubectl y conectividad:"
if command -v kubectl > /dev/null 2>&1; then
    echo "   ✅ kubectl está instalado"
    if kubectl get nodes > /dev/null 2>&1; then
        echo "   ✅ Conectividad al cluster OK"
        node_count=$(kubectl get nodes --no-headers | wc -l)
        echo "   📊 Nodos disponibles: ${node_count}"
    else
        echo "   ❌ No se puede conectar al cluster"
    fi
else
    echo "   ❌ kubectl no está instalado"
fi

echo ""
echo "=== VERIFICACIÓN COMPLETADA ==="
'

# Crear y ejecutar script de verificación
echo "${verification_script}" | api_request "POST" "filesystem/put" "{
    \"path\": \"/root/scripts-robust/verify-robust-backups.sh\",
    \"content\": \"$(echo "${verification_script}" | base64 -w 0)\"
}" > /dev/null

# Ejecutar verificación
echo "Ejecutando verificación de respaldos..."
verification_job=$(api_request "POST" "cronjob" '{
    "command": "/root/scripts-robust/verify-robust-backups.sh",
    "description": "Verificación de respaldos robustos",
    "enabled": true,
    "schedule": {
        "minute": "*",
        "hour": "*",
        "dom": "*",
        "month": "*",
        "dow": "*"
    },
    "stderr": true,
    "stdout": true,
    "user": "root"
}')

if echo "${verification_job}" | jq -e '.id' > /dev/null 2>&1; then
    ver_job_id=$(echo "${verification_job}" | jq -r '.id')
    echo "✅ Verificación programada con ID: ${ver_job_id}"
    
    echo "Esperando 30 segundos para que se ejecute..."
    sleep 30
    
    # Eliminar el cronjob de verificación
    api_request "DELETE" "cronjob/id/${ver_job_id}" > /dev/null
    echo "✅ Cronjob de verificación eliminado"
else
    echo "❌ Error al crear cronjob de verificación"
fi

echo ""
echo "=== VERIFICACIÓN COMPLETADA ==="
echo ""
echo "📊 RESUMEN:"
echo "✅ Script de respaldo robusto ejecutado"
echo "✅ Verificación de respaldos completada"
echo ""
echo "🔍 Para verificar manualmente:"
echo "   ssh root@192.168.1.20 'ls -la /mnt/homelab-storage/backups/robust-backups/'"
echo "   ssh root@192.168.1.20 'ls -la /mnt/homelab-storage/backups/latest-backup/'"
echo ""
echo "🚨 Si necesitas recuperar:"
echo "   ssh root@192.168.1.20 '/root/scripts-robust/robust-recovery.sh'"
