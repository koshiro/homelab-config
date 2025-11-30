#!/bin/bash
# Script para verificar el estado de los respaldos
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

echo "=== Verificando estado de respaldos ==="
echo "Fecha: $(date)"
echo ""

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

echo "1. Verificando cronjobs activos..."
cronjobs=$(api_request "GET" "cronjob")
echo "Cronjobs de respaldo:"
echo "${cronjobs}" | jq -r '.[] | select(.command | contains("backup")) | "ID: \(.id) - \(.description) - Habilitado: \(.enabled)"'

echo ""
echo "2. Ejecutando respaldo manual inmediato..."

# Crear cronjob para ejecutar respaldo inmediatamente
backup_job=$(api_request "POST" "cronjob" '{
    "command": "/root/scripts/backup-pod-configs.sh",
    "description": "Respaldo manual inmediato",
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

if echo "${backup_job}" | jq -e '.id' > /dev/null 2>&1; then
    job_id=$(echo "${backup_job}" | jq -r '.id')
    echo "✅ Cronjob de respaldo creado con ID: ${job_id}"
    
    echo "Esperando 60 segundos para que se ejecute..."
    sleep 60
    
    # Eliminar el cronjob temporal
    echo "Eliminando cronjob temporal..."
    api_request "DELETE" "cronjob/id/${job_id}" > /dev/null
    echo "✅ Cronjob temporal eliminado"
else
    echo "❌ Error al crear cronjob de respaldo:"
    echo "${backup_job}"
fi

echo ""
echo "3. Verificando si se crearon respaldos..."

# Crear un script de verificación en TrueNAS
verification_script='#!/bin/bash
echo "=== Verificación de respaldos ==="
echo "Fecha: $(date)"
echo ""

# Verificar directorios de respaldo
echo "1. Directorios de respaldo:"
ls -la /mnt/homelab-storage/backups/ 2>/dev/null || echo "No se encontró el directorio de respaldos"

echo ""
echo "2. Respaldos de pods:"
ls -la /mnt/homelab-storage/backups/pod-configs/ 2>/dev/null || echo "No se encontró el directorio de respaldos de pods"

echo ""
echo "3. Respaldos de hoy:"
today=$(date +%Y%m%d)
if [ -d "/mnt/homelab-storage/backups/pod-configs/${today}" ]; then
    echo "Directorio de respaldos de hoy encontrado:"
    ls -la /mnt/homelab-storage/backups/pod-configs/${today}/
else
    echo "No se encontró directorio de respaldos para hoy (${today})"
fi

echo ""
echo "4. Verificando kubectl:"
if command -v kubectl > /dev/null 2>&1; then
    echo "kubectl está instalado"
    echo "Probando conectividad al cluster:"
    kubectl get nodes 2>/dev/null || echo "No se puede conectar al cluster"
else
    echo "kubectl no está instalado"
fi

echo ""
echo "5. Verificando pods disponibles:"
if command -v kubectl > /dev/null 2>&1; then
    echo "Pods en namespace plex:"
    kubectl get pods -n plex 2>/dev/null || echo "No se puede acceder al namespace plex"
    
    echo "Pods en namespace sonarr:"
    kubectl get pods -n sonarr 2>/dev/null || echo "No se puede acceder al namespace sonarr"
    
    echo "Pods en namespace radarr:"
    kubectl get pods -n radarr 2>/dev/null || echo "No se puede acceder al namespace radarr"
else
    echo "No se puede verificar pods (kubectl no disponible)"
fi
'

# Crear archivo de verificación
echo "${verification_script}" | api_request "POST" "filesystem/put" "{
    \"path\": \"/root/scripts/verify-backups.sh\",
    \"content\": \"$(echo "${verification_script}" | base64 -w 0)\"
}" > /dev/null

# Ejecutar verificación
echo "Ejecutando verificación..."
verification_job=$(api_request "POST" "cronjob" '{
    "command": "/root/scripts/verify-backups.sh",
    "description": "Verificación de respaldos",
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
echo "=== Verificación completada ==="
echo ""
echo "Si no se generaron respaldos, el problema puede ser:"
echo "1. kubectl no está configurado correctamente en TrueNAS"
echo "2. Los pods no tienen los labels correctos (app=servicename)"
echo "3. Los namespaces no coinciden"
echo "4. Problemas de conectividad entre TrueNAS y el cluster"
echo ""
echo "Para solucionar:"
echo "1. Configurar SSH: ssh-copy-id root@192.168.1.20"
echo "2. Acceder a TrueNAS: ssh root@192.168.1.20"
echo "3. Verificar kubectl: kubectl get nodes"
echo "4. Ejecutar respaldo manual: /root/scripts/backup-pod-configs.sh"

