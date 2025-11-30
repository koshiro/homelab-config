#!/bin/bash
# Script de Verificación de Estado de Resiliencia
# Verifica el estado actual del cluster en términos de resiliencia post-apagón

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       ESTADO DE RESILIENCIA POST-APAGÓN - CLUSTER         ║${NC}"
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo ""

# 1. Estado de Nodos
echo -e "${YELLOW}[1] Estado de Nodos${NC}"
kubectl get nodes -o wide
echo ""

# 2. Estado del Media Stack
echo -e "${YELLOW}[2] Estado del Media Stack${NC}"
echo -e "${BLUE}App         Pod                             Status      Restarts  Age${NC}"
for ns in plex sonarr radarr bazarr prowlarr qbittorrent overseerr; do
  POD=$(kubectl get pod -n $ns -l app=$ns -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  if [ -n "$POD" ]; then
    STATUS=$(kubectl get pod -n $ns $POD -o jsonpath='{.status.phase}')
    RESTARTS=$(kubectl get pod -n $ns $POD -o jsonpath='{.status.containerStatuses[0].restartCount}')
    AGE=$(kubectl get pod -n $ns $POD -o jsonpath='{.status.startTime}')
    
    if [ "$STATUS" = "Running" ] && [ "$RESTARTS" -eq 0 ]; then
      echo -e "${GREEN}✓${NC} ${ns}\t${POD}\t${STATUS}\t${RESTARTS}\t${AGE}"
    elif [ "$STATUS" = "Running" ]; then
      echo -e "${YELLOW}⚠${NC} ${ns}\t${POD}\t${STATUS}\t${RESTARTS}\t${AGE}"
    else
      echo -e "${RED}✗${NC} ${ns}\t${POD}\t${STATUS}\t${RESTARTS}\t${AGE}"
    fi
  else
    echo -e "${RED}✗${NC} ${ns}\tNo pod encontrado"
  fi
done
echo ""

# 3. PVCs en riesgo (local-path)
echo -e "${YELLOW}[3] Configuraciones en Riesgo (local-path)${NC}"
VULNERABLE_PVCS=$(kubectl get pvc -A | grep local-path | wc -l | tr -d ' ')
if [ "$VULNERABLE_PVCS" -gt 0 ]; then
  echo -e "${RED}⚠ ${VULNERABLE_PVCS} PVCs en local-path (vulnerable a pérdida)${NC}"
  kubectl get pvc -A | grep -E "NAMESPACE|local-path" | head -10
else
  echo -e "${GREEN}✓ No hay PVCs en local-path${NC}"
fi
echo ""

# 4. PVCs en NFS (protegidos)
echo -e "${YELLOW}[4] Media Library (NFS - Protegido)${NC}"
kubectl get pvc -A | grep media-library-pvc | awk '{print $1,$2,$6}'
echo ""

# 5. Sistema de Monitoreo NFS
echo -e "${YELLOW}[5] Sistema de Monitoreo NFS${NC}"
NFS_MONITOR=$(kubectl get daemonset -n kube-system nfs-monitor 2>/dev/null)
if [ $? -eq 0 ]; then
  echo -e "${GREEN}✓ NFS Monitor DaemonSet activo${NC}"
  kubectl get daemonset -n kube-system nfs-monitor
  echo ""
  echo -e "${BLUE}Pods del monitor:${NC}"
  kubectl get pods -n kube-system -l app=nfs-monitor -o wide
else
  echo -e "${RED}✗ NFS Monitor DaemonSet NO implementado${NC}"
  echo -e "${YELLOW}  Ejecutar: ./scripts/apply-nfs-monitor.sh${NC}"
fi
echo ""

# 6. Health Checks Review
echo -e "${YELLOW}[6] Health Checks - Overseerr (ejemplo)${NC}"
OVERSEERR_POD=$(kubectl get pod -n overseerr -l app=overseerr -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$OVERSEERR_POD" ]; then
  LIVENESS=$(kubectl get pod -n overseerr $OVERSEERR_POD -o jsonpath='{.spec.containers[0].livenessProbe.initialDelaySeconds}')
  TIMEOUT=$(kubectl get pod -n overseerr $OVERSEERR_POD -o jsonpath='{.spec.containers[0].livenessProbe.timeoutSeconds}')
  
  if [ "$LIVENESS" -ge 60 ] && [ "$TIMEOUT" -ge 5 ]; then
    echo -e "${GREEN}✓ Health checks apropiados (initialDelay: ${LIVENESS}s, timeout: ${TIMEOUT}s)${NC}"
  else
    echo -e "${YELLOW}⚠ Health checks podrían ser muy agresivos (initialDelay: ${LIVENESS}s, timeout: ${TIMEOUT}s)${NC}"
  fi
else
  echo -e "${RED}✗ No se pudo verificar${NC}"
fi
echo ""

# 7. Backups Recientes
echo -e "${YELLOW}[7] Backups Disponibles (local)${NC}"
if [ -d "./backups" ]; then
  BACKUP_COUNT=$(ls -1 ./backups/*.tar.gz 2>/dev/null | wc -l | tr -d ' ')
  if [ "$BACKUP_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✓ ${BACKUP_COUNT} backups encontrados${NC}"
    echo -e "${BLUE}Más recientes:${NC}"
    ls -lht ./backups/*.tar.gz 2>/dev/null | head -5 | awk '{print "  " $9, "(" $5 ")"}'
  else
    echo -e "${YELLOW}⚠ No hay backups locales${NC}"
    echo -e "${YELLOW}  Ejecutar: ./scripts/quick-resilience-fix.sh${NC}"
  fi
else
  echo -e "${YELLOW}⚠ Directorio backups no existe${NC}"
fi
echo ""

# 8. Resumen de Resiliencia
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                    RESUMEN DE RESILIENCIA                  ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Calcular score
SCORE=0
MAX_SCORE=6

# Nodos OK
NODES_READY=$(kubectl get nodes --no-headers | grep " Ready " | wc -l | tr -d ' ')
NODES_TOTAL=$(kubectl get nodes --no-headers | wc -l | tr -d ' ')
if [ "$NODES_READY" -eq "$NODES_TOTAL" ]; then
  echo -e "${GREEN}✓${NC} Todos los nodos listos ($NODES_READY/$NODES_TOTAL)"
  SCORE=$((SCORE + 1))
else
  echo -e "${RED}✗${NC} Nodos no listos ($NODES_READY/$NODES_TOTAL)"
fi

# Media stack OK
RUNNING_APPS=$(kubectl get pods -A | grep -E "plex|sonarr|radarr|qbittorrent|bazarr|prowlarr|overseerr" | grep -c "Running")
if [ "$RUNNING_APPS" -ge 7 ]; then
  echo -e "${GREEN}✓${NC} Media stack corriendo ($RUNNING_APPS/7+ apps)"
  SCORE=$((SCORE + 1))
else
  echo -e "${YELLOW}⚠${NC} Media stack parcial ($RUNNING_APPS apps)"
fi

# Media en NFS
MEDIA_NFS=$(kubectl get pvc -A | grep -c media-library-pvc)
if [ "$MEDIA_NFS" -ge 5 ]; then
  echo -e "${GREEN}✓${NC} Media files en NFS (protegido)"
  SCORE=$((SCORE + 1))
else
  echo -e "${YELLOW}⚠${NC} Media files parcialmente en NFS"
fi

# Configs en local-path (negativo)
if [ "$VULNERABLE_PVCS" -gt 0 ]; then
  echo -e "${RED}✗${NC} Configs en local-path (vulnerable: $VULNERABLE_PVCS PVCs)"
else
  echo -e "${GREEN}✓${NC} Configs en NFS (protegido)"
  SCORE=$((SCORE + 1))
fi

# NFS Monitor
if kubectl get daemonset -n kube-system nfs-monitor &>/dev/null; then
  echo -e "${GREEN}✓${NC} NFS Monitor activo"
  SCORE=$((SCORE + 1))
else
  echo -e "${RED}✗${NC} NFS Monitor NO implementado"
fi

# Backups
if [ "$BACKUP_COUNT" -gt 0 ]; then
  echo -e "${GREEN}✓${NC} Backups disponibles ($BACKUP_COUNT)"
  SCORE=$((SCORE + 1))
else
  echo -e "${YELLOW}⚠${NC} Sin backups recientes"
fi

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Cálculo de nivel de resiliencia
PERCENTAGE=$((SCORE * 100 / MAX_SCORE))

if [ "$PERCENTAGE" -ge 80 ]; then
  echo -e "${GREEN}RESILIENCIA: ALTA ($SCORE/$MAX_SCORE - $PERCENTAGE%)${NC}"
  echo -e "${GREEN}✓ El cluster puede recuperarse de un apagón con mínima intervención${NC}"
elif [ "$PERCENTAGE" -ge 50 ]; then
  echo -e "${YELLOW}RESILIENCIA: MEDIA ($SCORE/$MAX_SCORE - $PERCENTAGE%)${NC}"
  echo -e "${YELLOW}⚠ El cluster puede recuperarse pero requiere intervención manual${NC}"
  echo -e "${YELLOW}⚠ Riesgo de pérdida de configuraciones en crash de Proxmox${NC}"
else
  echo -e "${RED}RESILIENCIA: BAJA ($SCORE/$MAX_SCORE - $PERCENTAGE%)${NC}"
  echo -e "${RED}✗ Alto riesgo de pérdida de datos en apagón${NC}"
  echo -e "${RED}✗ Recuperación requiere intervención manual extensa${NC}"
fi

echo ""
echo -e "${BLUE}Próximos pasos:${NC}"
if ! kubectl get daemonset -n kube-system nfs-monitor &>/dev/null; then
  echo "  1. Implementar NFS Monitor: ./scripts/apply-nfs-monitor.sh"
fi
if [ "$VULNERABLE_PVCS" -gt 0 ]; then
  echo "  2. Migrar configs a NFS: Ver MIGRATION-PLAN-FINAL.md"
fi
if [ "$BACKUP_COUNT" -eq 0 ]; then
  echo "  3. Crear backups: ./scripts/quick-resilience-fix.sh"
fi

echo ""
echo -e "${BLUE}Documentación:${NC}"
echo "  - docs/RESILIENCIA-POST-APAGON-ANALISIS.md"
echo "  - docs/RESUMEN-ACCIONES-RESILIENCIA.md"
echo "  - MIGRATION-PLAN-FINAL.md"
echo ""





