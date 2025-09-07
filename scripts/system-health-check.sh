#!/bin/bash
# Script para verificación de salud del sistema y cluster
# Ejecutar desde TrueNAS

set -e

# Configuración
BACKUP_BASE="/mnt/homelab-storage/backups/system-health"
DATE=$(date +%Y%m%d)
BACKUP_DIR="${BACKUP_BASE}/${DATE}"

# Crear directorio de respaldo
mkdir -p "${BACKUP_DIR}"

# Limpiar respaldos antiguos (mantener 30 días)
find ${BACKUP_BASE} -type d -mtime +30 -exec rm -rf {} \; 2>/dev/null || true

echo "=== Iniciando verificación de salud del sistema - $(date) ==="

# Verificación de salud del ZFS Pool
echo "Verificando salud del ZFS Pool..."
zpool status -v > ${BACKUP_DIR}/zfs-status.txt
zfs list -t snapshot > ${BACKUP_DIR}/zfs-snapshots.txt
zpool list -v > ${BACKUP_DIR}/zfs-pools.txt

# Verificación de espacio en disco
echo "Verificando espacio en disco..."
df -h > ${BACKUP_DIR}/disk-usage.txt
du -sh /mnt/homelab-storage/* > ${BACKUP_DIR}/storage-usage.txt

# Verificación del estado del cluster
echo "Verificando estado del cluster..."
kubectl get nodes > ${BACKUP_DIR}/nodes-status.txt
kubectl get pods -A > ${BACKUP_DIR}/pods-status.txt
kubectl get pods -A --field-selector=status.phase!=Running > ${BACKUP_DIR}/pods-not-running.txt

# Verificación de recursos
echo "Verificando uso de recursos..."
kubectl top nodes > ${BACKUP_DIR}/node-resources.txt 2>/dev/null || echo "No se pudo obtener métricas de nodos" > ${BACKUP_DIR}/node-resources.txt
kubectl top pods -A > ${BACKUP_DIR}/pod-resources.txt 2>/dev/null || echo "No se pudo obtener métricas de pods" > ${BACKUP_DIR}/pod-resources.txt

# Verificación de conectividad
echo "Verificando conectividad de servicios..."
echo "=== Verificación de Conectividad $(date) ===" > ${BACKUP_DIR}/connectivity.txt

# Verificar servicios críticos
services=("plex.danielriquelme.cl" "sonarr.danielriquelme.cl" "radarr.danielriquelme.cl" "bazarr.danielriquelme.cl" "prowlarr.danielriquelme.cl" "overseerr.danielriquelme.cl" "qbittorrent.danielriquelme.cl")

for service in "${services[@]}"; do
    echo -n "Verificando ${service}... "
    if curl -s -o /dev/null -w "%{http_code}" "http://${service}" | grep -q "200\|302\|401"; then
        echo "✅ OK" >> ${BACKUP_DIR}/connectivity.txt
        echo "✅ OK"
    else
        echo "❌ ERROR" >> ${BACKUP_DIR}/connectivity.txt
        echo "❌ ERROR"
    fi
done

# Verificación de logs de errores
echo "Verificando logs de errores..."
kubectl get events --sort-by='.lastTimestamp' --field-selector type=Warning > ${BACKUP_DIR}/k8s-warnings.txt

# Verificación de estado de los volúmenes persistentes
echo "Verificando volúmenes persistentes..."
kubectl get pv > ${BACKUP_DIR}/persistent-volumes.txt
kubectl get pvc -A > ${BACKUP_DIR}/persistent-volume-claims.txt

# Verificación de configuraciones de red
echo "Verificando configuraciones de red..."
kubectl get ingress -A > ${BACKUP_DIR}/ingress-status.txt
kubectl get networkpolicies -A > ${BACKUP_DIR}/networkpolicies-status.txt

# Verificación de servicios de monitoreo
echo "Verificando servicios de monitoreo..."
kubectl get pods -n monitoring > ${BACKUP_DIR}/monitoring-pods.txt

# Crear archivo de resumen
echo "=== Resumen de verificación de salud - $(date) ===" > ${BACKUP_DIR}/health-summary.txt
echo "Archivos generados:" >> ${BACKUP_DIR}/health-summary.txt
ls -la ${BACKUP_DIR}/*.txt >> ${BACKUP_DIR}/health-summary.txt
echo "" >> ${BACKUP_DIR}/health-summary.txt
echo "Tamaño total del respaldo:" >> ${BACKUP_DIR}/health-summary.txt
du -sh ${BACKUP_DIR} >> ${BACKUP_DIR}/health-summary.txt

# Verificar si hay problemas críticos
echo "" >> ${BACKUP_DIR}/health-summary.txt
echo "=== Verificación de problemas críticos ===" >> ${BACKUP_DIR}/health-summary.txt

# Verificar pods no funcionando
if [ -s ${BACKUP_DIR}/pods-not-running.txt ]; then
    echo "⚠️  ADVERTENCIA: Hay pods que no están funcionando:" >> ${BACKUP_DIR}/health-summary.txt
    cat ${BACKUP_DIR}/pods-not-running.txt >> ${BACKUP_DIR}/health-summary.txt
else
    echo "✅ Todos los pods están funcionando correctamente" >> ${BACKUP_DIR}/health-summary.txt
fi

# Verificar espacio en disco
DISK_USAGE=$(df /mnt/homelab-storage | tail -1 | awk '{print $5}' | sed 's/%//')
if [ ${DISK_USAGE} -gt 80 ]; then
    echo "⚠️  ADVERTENCIA: Uso de disco alto: ${DISK_USAGE}%" >> ${BACKUP_DIR}/health-summary.txt
else
    echo "✅ Uso de disco normal: ${DISK_USAGE}%" >> ${BACKUP_DIR}/health-summary.txt
fi

# Verificar estado del ZFS
if grep -q "DEGRADED\|FAULTED" ${BACKUP_DIR}/zfs-status.txt; then
    echo "⚠️  ADVERTENCIA: Problemas detectados en el pool ZFS" >> ${BACKUP_DIR}/health-summary.txt
else
    echo "✅ Pool ZFS funcionando correctamente" >> ${BACKUP_DIR}/health-summary.txt
fi

echo "=== Verificación de salud completada - $(date) ==="
echo "Ubicación: ${BACKUP_DIR}"
echo "Tamaño total: $(du -sh ${BACKUP_DIR} | cut -f1)"
