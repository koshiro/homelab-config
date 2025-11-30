#!/bin/bash
# Script de Mitigación Rápida - Resiliencia Post-Apagón
# Fecha: 2025-10-21
# Basado en: docs/RESILIENCIA-POST-APAGON-ANALISIS.md

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}Mitigación Rápida - Resiliencia${NC}"
echo -e "${GREEN}=====================================${NC}"
echo ""

# 1. Arreglar Overseerr health checks
echo -e "${YELLOW}[1/5] Aplicando corrección de health checks en Overseerr...${NC}"
kubectl apply -f cluster/05-services/overseerr/deployment.yml
echo -e "${GREEN}✓ Overseerr deployment actualizado${NC}"
echo ""

# 2. Eliminar storage-diagnostic fallido
echo -e "${YELLOW}[2/5] Limpiando storage-diagnostic fallido...${NC}"
kubectl delete daemonset storage-diagnostic -n default 2>/dev/null || echo "DaemonSet ya eliminado"
kubectl delete configmap storage-check-script -n default 2>/dev/null || echo "ConfigMap ya eliminado"
echo -e "${GREEN}✓ Storage-diagnostic limpiado${NC}"
echo ""

# 3. Crear directorio de backups si no existe
echo -e "${YELLOW}[3/5] Preparando directorio de backups...${NC}"
mkdir -p backups
echo -e "${GREEN}✓ Directorio backups listo${NC}"
echo ""

# 4. Backup de configs actuales
echo -e "${YELLOW}[4/5] Creando backups de configuraciones...${NC}"
DATE=$(date +%Y%m%d-%H%M)
BACKUP_COUNT=0

for app in plex sonarr radarr bazarr prowlarr overseerr qbittorrent; do
  POD=$(kubectl get pods -n $app -l app=$app -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  if [ -n "$POD" ]; then
    echo -e "  Backup de ${app}..."
    if kubectl exec -n $app $POD -- tar czf /tmp/${app}-config-backup.tar.gz /config 2>/dev/null; then
      kubectl cp $app/$POD:/tmp/${app}-config-backup.tar.gz ./backups/${app}-config-${DATE}.tar.gz 2>/dev/null
      kubectl exec -n $app $POD -- rm /tmp/${app}-config-backup.tar.gz 2>/dev/null || true
      echo -e "  ${GREEN}✓${NC} ${app} backed up"
      BACKUP_COUNT=$((BACKUP_COUNT + 1))
    else
      echo -e "  ${YELLOW}⚠${NC} ${app} backup failed (puede ser normal si /config no existe)"
    fi
  else
    echo -e "  ${YELLOW}⚠${NC} ${app} pod no encontrado"
  fi
done

echo -e "${GREEN}✓ Backups creados: ${BACKUP_COUNT}/7${NC}"
echo ""

# 5. Verificar estado del cluster
echo -e "${YELLOW}[5/5] Verificando estado del cluster...${NC}"
echo ""
echo -e "${YELLOW}Nodos:${NC}"
kubectl get nodes -o wide

echo ""
echo -e "${YELLOW}Pods del Media Stack:${NC}"
kubectl get pods -A | grep -E "NAMESPACE|plex|sonarr|radarr|qbittorrent|bazarr|prowlarr|overseerr" | head -20

echo ""
echo -e "${YELLOW}PVCs en riesgo (local-path):${NC}"
kubectl get pvc -A | grep local-path

echo ""
echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}Mitigación Rápida COMPLETADA${NC}"
echo -e "${GREEN}=====================================${NC}"
echo ""
echo -e "${YELLOW}Próximos pasos recomendados:${NC}"
echo "1. Revisar: docs/RESILIENCIA-POST-APAGON-ANALISIS.md"
echo "2. Verificar que Overseerr ya no reinicie: kubectl get pods -n overseerr -w"
echo "3. Planificar Fase 2: Implementar NFS monitor DaemonSet"
echo "4. Planificar migración completa: MIGRATION-PLAN-FINAL.md"
echo ""
echo -e "${YELLOW}Backups guardados en:${NC} ./backups/"
ls -lh ./backups/ | tail -10





