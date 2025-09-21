#!/bin/bash
# Script para configurar cronjobs en TrueNAS
# Ejecutar desde TrueNAS con acceso a la API

set -e

# Configuración de TrueNAS
TRUENAS_IP="192.168.1.20"
API_KEY_FILE="/root/.truenas-api-key"

# Verificar que existe la API key
if [ ! -f "${API_KEY_FILE}" ]; then
    echo "ERROR: No se encontró el archivo de API key en ${API_KEY_FILE}"
    exit 1
fi

API_KEY=$(cat ${API_KEY_FILE})

# Función para crear un cronjob
create_cronjob() {
    local description="$1"
    local command="$2"
    local minute="$3"
    local hour="$4"
    local dom="$5"
    local month="$6"
    local dow="$7"
    
    echo "Creando cronjob: ${description}"
    
    curl -k -X POST "https://${TRUENAS_IP}/api/v2.0/cronjob" \
        -H "Authorization: Bearer ${API_KEY}" \
        -H "Content-Type: application/json" \
        -d "{
            \"command\": \"${command}\",
            \"description\": \"${description}\",
            \"enabled\": true,
            \"schedule\": {
                \"minute\": \"${minute}\",
                \"hour\": \"${hour}\",
                \"dom\": \"${dom}\",
                \"month\": \"${month}\",
                \"dow\": \"${dow}\"
            },
            \"user\": \"root\"
        }"
    
    echo ""
}

echo "=== Configurando cronjobs en TrueNAS ==="

# 1. Respaldo de configuraciones de pods (CRÍTICO)
echo "1. Configurando respaldo de configuraciones de pods..."
create_cronjob \
    "Respaldo diario de configuraciones de pods" \
    "/root/scripts/backup-pod-configs.sh" \
    "0" "3" "*" "*" "*"

# 2. Respaldo de configuración del cluster
echo "2. Configurando respaldo de configuración del cluster..."
create_cronjob \
    "Respaldo diario de configuración del cluster" \
    "/root/scripts/backup-cluster-config.sh" \
    "30" "3" "*" "*" "*"

# 3. Verificación de salud del sistema
echo "3. Configurando verificación de salud del sistema..."
create_cronjob \
    "Verificación diaria de salud del sistema" \
    "/root/scripts/system-health-check.sh" \
    "0" "4" "*" "*" "*"

# 4. Limpieza de logs del sistema
echo "4. Configurando limpieza de logs..."
create_cronjob \
    "Limpieza semanal de logs del sistema" \
    "find /var/log -name \"*.log\" -mtime +30 -delete && find /var/log -name \"*.gz\" -mtime +7 -delete" \
    "0" "2" "*" "*" "0"

# 5. Verificación de salud del ZFS
echo "5. Configurando verificación de ZFS..."
create_cronjob \
    "Verificación diaria de salud del ZFS" \
    "zpool status -v > /mnt/homelab-storage/backups/system-health/zfs-status-\$(date +%Y%m%d).txt" \
    "0" "5" "*" "*" "*"

# 6. Limpieza de snapshots antiguos
echo "6. Configurando limpieza de snapshots..."
create_cronjob \
    "Limpieza semanal de snapshots antiguos" \
    "zfs list -H -t snapshot -o name,creation | awk '\$2 < \"'\$(date -d '30 days ago' +%Y-%m-%d)'\" {print \$1}' | xargs -r zfs destroy" \
    "0" "1" "*" "*" "0"

# 7. Verificación de estado del cluster (cada 6 horas)
echo "7. Configurando verificación del cluster..."
create_cronjob \
    "Verificación del estado del cluster cada 6 horas" \
    "kubectl get pods -A --field-selector=status.phase!=Running > /mnt/homelab-storage/backups/system-health/pod-status-\$(date +%Y%m%d-%H%M).txt" \
    "0" "0,6,12,18" "*" "*" "*"

# 8. Verificación de conectividad (cada 4 horas)
echo "8. Configurando verificación de conectividad..."
create_cronjob \
    "Verificación de conectividad cada 4 horas" \
    "curl -s -o /dev/null -w 'Plex: %{http_code}' http://plex.danielriquelme.cl > /mnt/homelab-storage/backups/system-health/connectivity-\$(date +%Y%m%d-%H%M).txt" \
    "0" "0,4,8,12,16,20" "*" "*" "*"

# 9. Limpieza de archivos temporales
echo "9. Configurando limpieza de archivos temporales..."
create_cronjob \
    "Limpieza diaria de archivos temporales" \
    "find /tmp -name \"*.tmp\" -mtime +1 -delete && find /var/tmp -name \"*.tmp\" -mtime +1 -delete" \
    "0" "6" "*" "*" "*"

# 10. Respaldo de configuraciones de infraestructura (semanal)
echo "10. Configurando respaldo de infraestructura..."
create_cronjob \
    "Respaldo semanal de configuraciones de infraestructura" \
    "mkdir -p /mnt/homelab-storage/backups/infrastructure/\$(date +%Y%m%d) && cp -r /root/homelab-config/ansible /mnt/homelab-storage/backups/infrastructure/\$(date +%Y%m%d)/ && cp -r /root/homelab-config/cluster /mnt/homelab-storage/backups/infrastructure/\$(date +%Y%m%d)/" \
    "0" "5" "*" "*" "0"

echo "=== Configuración de cronjobs completada ==="

# Verificar cronjobs creados
echo "=== Verificando cronjobs creados ==="
curl -k -X GET "https://${TRUENAS_IP}/api/v2.0/cronjob" \
    -H "Authorization: Bearer ${API_KEY}" \
    -H "Content-Type: application/json" | jq '.[] | {id: .id, description: .description, enabled: .enabled, schedule: .schedule}'

echo ""
echo "=== Resumen ==="
echo "Se han configurado 10 cronjobs en TrueNAS:"
echo "1. Respaldo diario de configuraciones de pods (03:00)"
echo "2. Respaldo diario de configuración del cluster (03:30)"
echo "3. Verificación diaria de salud del sistema (04:00)"
echo "4. Limpieza semanal de logs del sistema (02:00 domingos)"
echo "5. Verificación diaria de salud del ZFS (05:00)"
echo "6. Limpieza semanal de snapshots antiguos (01:00 domingos)"
echo "7. Verificación del estado del cluster cada 6 horas"
echo "8. Verificación de conectividad cada 4 horas"
echo "9. Limpieza diaria de archivos temporales (06:00)"
echo "10. Respaldo semanal de infraestructura (05:00 domingos)"
echo ""
echo "Los scripts deben estar ubicados en /root/scripts/ en TrueNAS"
echo "Asegúrate de que kubectl esté configurado correctamente en TrueNAS"
