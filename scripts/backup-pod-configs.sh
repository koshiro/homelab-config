#!/bin/bash
# Script para respaldo de configuraciones de pods en TrueNAS
# Ejecutar desde TrueNAS con acceso a kubectl

set -e

# Configuración
BACKUP_BASE="/mnt/homelab-storage/backups/pod-configs"
DATE=$(date +%Y%m%d)
BACKUP_DIR="${BACKUP_BASE}/${DATE}"

# Crear directorio de respaldo
mkdir -p "${BACKUP_DIR}"

# Función para respaldar un pod
backup_pod() {
    local namespace=$1
    local pod_name=$2
    local config_path=$3
    local backup_name=$4
    
    echo "Respaldando ${backup_name}..."
    
    # Obtener el nombre real del pod
    local real_pod=$(kubectl get pods -n ${namespace} -l app=${pod_name} -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [ -z "${real_pod}" ]; then
        echo "ERROR: No se encontró el pod ${pod_name} en namespace ${namespace}"
        return 1
    fi
    
    # Crear respaldo
    kubectl exec -n ${namespace} ${real_pod} -- tar czf /tmp/${backup_name}-${DATE}.tar.gz ${config_path}
    kubectl cp ${namespace}/${real_pod}:/tmp/${backup_name}-${DATE}.tar.gz ${BACKUP_DIR}/
    kubectl exec -n ${namespace} ${real_pod} -- rm -f /tmp/${backup_name}-${DATE}.tar.gz
    
    echo "✅ ${backup_name} respaldado exitosamente"
}

# Limpiar respaldos antiguos (mantener 7 días)
find ${BACKUP_BASE} -type d -mtime +7 -exec rm -rf {} \; 2>/dev/null || true

echo "=== Iniciando respaldo de configuraciones de pods - $(date) ==="

# Respaldo de Plex (CRÍTICO - 15Gi)
backup_pod "plex" "plex" "/config" "plex-config"

# Respaldo de Sonarr (CRÍTICO - 5Gi)
backup_pod "sonarr" "sonarr" "/config" "sonarr-config"

# Respaldo de Radarr
backup_pod "radarr" "radarr" "/config" "radarr-config"

# Respaldo de Bazarr
backup_pod "bazarr" "bazarr" "/config" "bazarr-config"

# Respaldo de Prowlarr
backup_pod "prowlarr" "prowlarr" "/config" "prowlarr-config"

# Respaldo de Overseerr
backup_pod "overseerr" "overseerr" "/config" "overseerr-config"

# Respaldo de Pingvin
backup_pod "pingvin" "pingvin" "/config" "pingvin-config"

# Respaldo de qBittorrent
backup_pod "qbittorrent" "qbittorrent" "/config" "qbittorrent-config"

# Crear archivo de resumen
echo "=== Resumen del respaldo - $(date) ===" > ${BACKUP_DIR}/backup-summary.txt
echo "Archivos respaldados:" >> ${BACKUP_DIR}/backup-summary.txt
ls -la ${BACKUP_DIR}/*.tar.gz >> ${BACKUP_DIR}/backup-summary.txt
echo "" >> ${BACKUP_DIR}/backup-summary.txt
echo "Tamaño total del respaldo:" >> ${BACKUP_DIR}/backup-summary.txt
du -sh ${BACKUP_DIR} >> ${BACKUP_DIR}/backup-summary.txt

echo "=== Respaldo completado exitosamente - $(date) ==="
echo "Ubicación: ${BACKUP_DIR}"
echo "Tamaño total: $(du -sh ${BACKUP_DIR} | cut -f1)"
