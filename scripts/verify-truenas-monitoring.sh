#!/bin/bash

# Script para verificar que el monitoreo de TrueNAS esté funcionando correctamente

echo "🔍 Verificando monitoreo de TrueNAS..."

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Función para verificar estado
check_status() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✅ $2${NC}"
    else
        echo -e "${RED}❌ $2${NC}"
    fi
}

# 1. Verificar que el namespace de monitoring existe
echo "📊 Verificando namespace de monitoring..."
kubectl get namespace monitoring >/dev/null 2>&1
check_status $? "Namespace monitoring existe"

# 2. Verificar que el exporter de TrueNAS esté desplegado
echo "🚀 Verificando deployment del exporter de TrueNAS..."
kubectl get deployment truenas-node-exporter -n monitoring >/dev/null 2>&1
check_status $? "Deployment truenas-node-exporter existe"

# 3. Verificar que el pod esté corriendo
echo "🐳 Verificando estado del pod..."
POD_STATUS=$(kubectl get pods -n monitoring -l app=truenas-node-exporter -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
if [ "$POD_STATUS" = "Running" ]; then
    echo -e "${GREEN}✅ Pod está corriendo (${POD_STATUS})${NC}"
else
    echo -e "${RED}❌ Pod no está corriendo (${POD_STATUS})${NC}"
fi

# 4. Verificar que el servicio esté disponible
echo "🔌 Verificando servicio..."
kubectl get service truenas-node-exporter -n monitoring >/dev/null 2>&1
check_status $? "Servicio truenas-node-exporter existe"

# 5. Verificar que el ServiceMonitor esté configurado
echo "📡 Verificando ServiceMonitor..."
kubectl get servicemonitor truenas-node-exporter-monitor -n monitoring >/dev/null 2>&1
check_status $? "ServiceMonitor configurado"

# 6. Verificar que Prometheus esté scrapeando las métricas
echo "📊 Verificando métricas en Prometheus..."
PROMETHEUS_POD=$(kubectl get pods -n monitoring -l app=prometheus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$PROMETHEUS_POD" ]; then
    echo "🔍 Pod de Prometheus encontrado: $PROMETHEUS_POD"
    
    # Verificar targets
    echo "🎯 Verificando targets de Prometheus..."
    kubectl exec -n monitoring $PROMETHEUS_POD -- wget -qO- http://localhost:9090/api/v1/targets | grep -q "truenas-node-exporter"
    check_status $? "Target de TrueNAS configurado en Prometheus"
else
    echo -e "${YELLOW}⚠️ No se pudo encontrar el pod de Prometheus${NC}"
fi

# 7. Verificar que el dashboard esté configurado
echo "📈 Verificando dashboard de Grafana..."
kubectl get configmap truenas-dashboard-simple -n monitoring >/dev/null 2>&1
check_status $? "Dashboard de TrueNAS configurado"

# 8. Verificar conectividad con TrueNAS
echo "🌐 Verificando conectividad con TrueNAS..."
if curl -k -s "https://192.168.1.20/api/v2.0/system/info" >/dev/null 2>&1; then
    echo -e "${GREEN}✅ TrueNAS es accesible${NC}"
else
    echo -e "${RED}❌ No se puede acceder a TrueNAS${NC}"
fi

# 9. Verificar métricas del exporter
echo "📊 Verificando métricas del exporter..."
EXPORTER_POD=$(kubectl get pods -n monitoring -l app=truenas-node-exporter -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$EXPORTER_POD" ]; then
    echo "🔍 Pod del exporter encontrado: $EXPORTER_POD"
    
    # Verificar endpoint de métricas
    kubectl exec -n monitoring $EXPORTER_POD -- wget -qO- http://localhost:9100/metrics | grep -q "node_cpu_seconds_total"
    check_status $? "Métricas del exporter disponibles"
else
    echo -e "${YELLOW}⚠️ No se pudo encontrar el pod del exporter${NC}"
fi

echo ""
echo "🎉 Verificación completada!"
echo ""
echo "📋 Resumen de verificación:"
echo "   - Namespace monitoring: $(kubectl get namespace monitoring >/dev/null 2>&1 && echo '✅' || echo '❌')"
echo "   - Deployment: $(kubectl get deployment truenas-node-exporter -n monitoring >/dev/null 2>&1 && echo '✅' || echo '❌')"
echo "   - Servicio: $(kubectl get service truenas-node-exporter -n monitoring >/dev/null 2>&1 && echo '✅' || echo '❌')"
echo "   - ServiceMonitor: $(kubectl get servicemonitor truenas-node-exporter-monitor -n monitoring >/dev/null 2>&1 && echo '✅' || echo '❌')"
echo "   - Dashboard: $(kubectl get configmap truenas-dashboard-simple -n monitoring >/dev/null 2>&1 && echo '✅' || echo '❌')"
echo ""
echo "🔗 Para acceder a Grafana:"
echo "   - URL: https://grafana.danielriquelme.cl"
echo "   - Dashboard: TrueNAS System Metrics"
echo ""
echo "📊 Para ver métricas del exporter:"
echo "   - kubectl port-forward -n monitoring svc/truenas-node-exporter 9100:9100"
echo "   - http://localhost:9100/metrics"
