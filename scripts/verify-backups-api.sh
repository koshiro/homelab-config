#!/bin/bash
# Script para verificar y corregir respaldos usando la API de TrueNAS
# Ejecutar desde la máquina local

set -e

# Configuración
TRUENAS_IP="192.168.1.20"
API_KEY_FILE="/Users/daniel/git/homelab-config/.truenas-api-key"

# Verificar que existe la API key
if [ ! -f "${API_KEY_FILE}" ]; then
    echo "ERROR: No se encontró el archivo de API key en ${API_KEY_FILE}"
    exit 1
fi

API_KEY=$(cat "${API_KEY_FILE}")

echo "=== Verificando sistema de respaldos en TrueNAS ==="

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

# Verificar estado de los cronjobs
echo "1. Verificando cronjobs de respaldo..."
cronjobs=$(api_request "GET" "cronjob")
echo "Cronjobs configurados:"
echo "${cronjobs}" | jq -r '.[] | select(.command | contains("backup")) | "ID: \(.id) - \(.description) - Habilitado: \(.enabled) - Comando: \(.command)"'

# Verificar si los scripts existen en TrueNAS
echo ""
echo "2. Verificando scripts de respaldo..."
# Nota: No podemos verificar archivos directamente con la API, pero podemos intentar ejecutar los scripts

# Verificar directorios de respaldo
echo ""
echo "3. Verificando directorios de respaldo..."
# Usar la API para verificar el sistema de archivos
backup_dirs=$(api_request "GET" "filesystem/listdir" '{"path": "/mnt/homelab-storage/backups"}')
echo "Directorios de respaldo encontrados:"
echo "${backup_dirs}" | jq -r '.[] | select(.type == "DIRECTORY") | .name' 2>/dev/null || echo "No se pudieron listar los directorios"

# Verificar respaldos recientes
echo ""
echo "4. Verificando respaldos recientes..."
today=$(date +%Y%m%d)
yesterday=$(date -d "yesterday" +%Y%m%d 2>/dev/null || date -v-1d +%Y%m%d)

echo "Buscando respaldos del día de hoy (${today}):"
today_backups=$(api_request "GET" "filesystem/listdir" "{\"path\": \"/mnt/homelab-storage/backups/pod-configs/${today}\"}" 2>/dev/null || echo "[]")
echo "${today_backups}" | jq -r '.[] | select(.type == "FILE") | .name' 2>/dev/null || echo "No se encontraron respaldos de hoy"

echo ""
echo "Buscando respaldos de ayer (${yesterday}):"
yesterday_backups=$(api_request "GET" "filesystem/listdir" "{\"path\": \"/mnt/homelab-storage/backups/pod-configs/${yesterday}\"}" 2>/dev/null || echo "[]")
echo "${yesterday_backups}" | jq -r '.[] | select(.type == "FILE") | .name' 2>/dev/null || echo "No se encontraron respaldos de ayer"

# Ejecutar script de respaldo manualmente
echo ""
echo "5. Ejecutando respaldo manual..."
echo "Ejecutando backup-pod-configs.sh..."

# Crear un cronjob temporal para ejecutar el script
temp_cronjob=$(api_request "POST" "cronjob" '{
    "command": "/root/scripts/backup-pod-configs.sh",
    "description": "Respaldo manual temporal",
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

if echo "${temp_cronjob}" | jq -e '.id' > /dev/null 2>&1; then
    cronjob_id=$(echo "${temp_cronjob}" | jq -r '.id')
    echo "✅ Cronjob temporal creado con ID: ${cronjob_id}"
    
    # Esperar un momento para que se ejecute
    echo "Esperando 30 segundos para que se ejecute..."
    sleep 30
    
    # Eliminar el cronjob temporal
    echo "Eliminando cronjob temporal..."
    api_request "DELETE" "cronjob/id/${cronjob_id}" > /dev/null
    echo "✅ Cronjob temporal eliminado"
else
    echo "❌ Error al crear cronjob temporal:"
    echo "${temp_cronjob}"
fi

# Verificar respaldos después de la ejecución manual
echo ""
echo "6. Verificando respaldos después de la ejecución manual..."
new_backups=$(api_request "GET" "filesystem/listdir" "{\"path\": \"/mnt/homelab-storage/backups/pod-configs/${today}\"}" 2>/dev/null || echo "[]")
echo "Respaldos encontrados después de la ejecución:"
echo "${new_backups}" | jq -r '.[] | select(.type == "FILE") | "\(.name) - \(.size) bytes - \(.mtime)"' 2>/dev/null || echo "No se encontraron nuevos respaldos"

echo ""
echo "=== Verificación completada ==="
echo ""
echo "Si solo ves respaldos de Plex, el problema puede ser:"
echo "1. Los scripts no están presentes en TrueNAS"
echo "2. kubectl no está configurado correctamente en TrueNAS"
echo "3. Los pods no tienen los labels correctos (app=servicename)"
echo "4. Los namespaces no coinciden con los esperados"
echo ""
echo "Para solucionar:"
echo "1. Configurar SSH a TrueNAS: ssh-copy-id root@192.168.1.20"
echo "2. Desplegar scripts: ./scripts/deploy-to-truenas.sh"
echo "3. Configurar kubectl: ssh root@192.168.1.20 '/root/scripts/setup-kubectl-truenas.sh'"

