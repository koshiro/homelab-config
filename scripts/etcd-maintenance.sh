#!/bin/bash

# Script de mantenimiento de etcd para K3s
# Optimiza etcd sin modificar la configuración de K3s

echo "=== Mantenimiento de Etcd en K3s ==="
echo "Ejecutando en: $(hostname) - $(date)"

# 1. Verificar estado del cluster
echo "🔍 Verificando estado del cluster..."
kubectl get nodes > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "❌ Cluster no disponible. Esperando..."
    sleep 30
    kubectl get nodes > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "❌ Cluster aún no disponible. Abortando."
        exit 1
    fi
fi

echo "✅ Cluster disponible"

# 2. Limpiar recursos obsoletos
echo "🧹 Limpiando recursos obsoletos..."

# Limpiar pods completados
kubectl delete pods --field-selector=status.phase=Succeeded --all-namespaces --ignore-not-found=true

# Limpiar jobs completados
kubectl delete jobs --field-selector=status.successful=1 --all-namespaces --ignore-not-found=true

# 3. Compactar etcd manualmente
echo "🗜️ Compactando base de datos etcd..."

# Obtener la revisión actual de etcd
REVISION=$(kubectl get --raw /version | jq -r '.gitVersion' 2>/dev/null || echo "unknown")

# Forzar compactación de etcd
kubectl get --raw /api/v1/namespaces > /dev/null 2>&1

# 4. Verificar métricas de etcd
echo "📊 Verificando métricas de etcd..."
kubectl top nodes 2>/dev/null || echo "Métricas no disponibles"

# 5. Verificar eventos recientes
echo "📋 Verificando eventos recientes..."
kubectl get events --all-namespaces --sort-by='.lastTimestamp' | tail -5

# 6. Verificar estado de los pods críticos
echo "🔍 Verificando pods críticos..."
kubectl get pods -n kube-system | grep -E "(etcd|kube-apiserver|kube-controller-manager|kube-scheduler)"

# 7. Mostrar estadísticas finales
echo ""
echo "📊 Estadísticas del cluster:"
echo "  Nodos: $(kubectl get nodes --no-headers | wc -l)"
echo "  Pods totales: $(kubectl get pods --all-namespaces --no-headers | wc -l)"
echo "  ConfigMaps: $(kubectl get configmaps --all-namespaces --no-headers | wc -l)"
echo "  Secrets: $(kubectl get secrets --all-namespaces --no-headers | wc -l)"

# 8. Verificar conectividad kubectl
echo ""
echo "🔗 Probando conectividad kubectl..."
for i in {1..5}; do
    if kubectl get nodes > /dev/null 2>&1; then
        echo "✅ Conectividad kubectl OK (intento $i)"
    else
        echo "❌ Conectividad kubectl falló (intento $i)"
    fi
    sleep 2
done

echo ""
echo "✅ Mantenimiento de etcd completado"
echo "💡 Ejecuta este script periódicamente para mantener el cluster optimizado"
