#!/bin/bash
# Script para respaldo de configuración del cluster Kubernetes
# Ejecutar desde TrueNAS con acceso a kubectl

set -e

# Configuración
BACKUP_BASE="/mnt/homelab-storage/backups/cluster-config"
DATE=$(date +%Y%m%d)
BACKUP_DIR="${BACKUP_BASE}/${DATE}"

# Crear directorio de respaldo
mkdir -p "${BACKUP_DIR}"

# Limpiar respaldos antiguos (mantener 30 días)
find ${BACKUP_BASE} -type d -mtime +30 -exec rm -rf {} \; 2>/dev/null || true

echo "=== Iniciando respaldo de configuración del cluster - $(date) ==="

# Respaldo de recursos de Kubernetes
echo "Respaldando recursos de Kubernetes..."
kubectl get all -A -o yaml > ${BACKUP_DIR}/k8s-resources.yaml
kubectl get pvc -A -o yaml > ${BACKUP_DIR}/pvc.yaml
kubectl get secrets -A -o yaml > ${BACKUP_DIR}/secrets.yaml
kubectl get configmaps -A -o yaml > ${BACKUP_DIR}/configmaps.yaml
kubectl get ingress -A -o yaml > ${BACKUP_DIR}/ingress.yaml
kubectl get networkpolicies -A -o yaml > ${BACKUP_DIR}/networkpolicies.yaml

# Respaldo de configuraciones específicas de la ARR Suite
echo "Respaldando configuraciones de la ARR Suite..."
kubectl get deployment -n plex plex -o yaml > ${BACKUP_DIR}/plex-deployment.yaml
kubectl get deployment -n sonarr sonarr -o yaml > ${BACKUP_DIR}/sonarr-deployment.yaml
kubectl get deployment -n radarr radarr -o yaml > ${BACKUP_DIR}/radarr-deployment.yaml
kubectl get deployment -n bazarr bazarr -o yaml > ${BACKUP_DIR}/bazarr-deployment.yaml
kubectl get deployment -n prowlarr prowlarr -o yaml > ${BACKUP_DIR}/prowlarr-deployment.yaml
kubectl get deployment -n overseerr overseerr -o yaml > ${BACKUP_DIR}/overseerr-deployment.yaml
kubectl get deployment -n qbittorrent qbittorrent -o yaml > ${BACKUP_DIR}/qbittorrent-deployment.yaml

# Respaldo de servicios
kubectl get svc -A -o yaml > ${BACKUP_DIR}/services.yaml

# Respaldo de configuraciones de red
kubectl get ingress -A -o yaml > ${BACKUP_DIR}/ingress.yaml
kubectl get networkpolicies -A -o yaml > ${BACKUP_DIR}/networkpolicies.yaml

# Respaldo de configuraciones de almacenamiento
kubectl get storageclass -o yaml > ${BACKUP_DIR}/storageclass.yaml
kubectl get pv -o yaml > ${BACKUP_DIR}/persistent-volumes.yaml

# Respaldo de configuraciones de monitoreo
kubectl get deployment -n monitoring -o yaml > ${BACKUP_DIR}/monitoring-deployments.yaml
kubectl get svc -n monitoring -o yaml > ${BACKUP_DIR}/monitoring-services.yaml

# Respaldo de configuraciones de Traefik
kubectl get deployment -n kube-system traefik -o yaml > ${BACKUP_DIR}/traefik-deployment.yaml
kubectl get svc -n kube-system traefik -o yaml > ${BACKUP_DIR}/traefik-service.yaml

# Respaldo de configuraciones de Cloudflare
kubectl get deployment -n cloudflared cloudflared -o yaml > ${BACKUP_DIR}/cloudflared-deployment.yaml

# Crear archivo de resumen
echo "=== Resumen del respaldo del cluster - $(date) ===" > ${BACKUP_DIR}/backup-summary.txt
echo "Archivos respaldados:" >> ${BACKUP_DIR}/backup-summary.txt
ls -la ${BACKUP_DIR}/*.yaml >> ${BACKUP_DIR}/backup-summary.txt
echo "" >> ${BACKUP_DIR}/backup-summary.txt
echo "Tamaño total del respaldo:" >> ${BACKUP_DIR}/backup-summary.txt
du -sh ${BACKUP_DIR} >> ${BACKUP_DIR}/backup-summary.txt

# Información del cluster
echo "" >> ${BACKUP_DIR}/backup-summary.txt
echo "=== Información del cluster ===" >> ${BACKUP_DIR}/backup-summary.txt
kubectl version >> ${BACKUP_DIR}/backup-summary.txt
kubectl get nodes >> ${BACKUP_DIR}/backup-summary.txt

echo "=== Respaldo del cluster completado exitosamente - $(date) ==="
echo "Ubicación: ${BACKUP_DIR}"
echo "Tamaño total: $(du -sh ${BACKUP_DIR} | cut -f1)"
