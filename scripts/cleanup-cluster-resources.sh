#!/bin/bash

# Script para limpiar recursos obsoletos del cluster
# Reduce la carga en etcd eliminando recursos innecesarios

echo "=== Limpieza de Recursos del Cluster ==="
echo "Ejecutando en: $(hostname) - $(date)"

# 1. Limpiar pods completados y fallidos
echo "🧹 Limpiando pods completados y fallidos..."
kubectl delete pods --field-selector=status.phase=Succeeded --all-namespaces --ignore-not-found=true
kubectl delete pods --field-selector=status.phase=Failed --all-namespaces --ignore-not-found=true

# 2. Limpiar jobs completados
echo "🧹 Limpiando jobs completados..."
kubectl delete jobs --field-selector=status.successful=1 --all-namespaces --ignore-not-found=true

# 3. Limpiar configmaps obsoletos (mantener solo los necesarios)
echo "🧹 Limpiando configmaps obsoletos..."
kubectl get configmaps --all-namespaces -o json | jq -r '.items[] | select(.metadata.name | startswith("kube-root-ca.crt") | not) | select(.metadata.name | startswith("kubelet-config") | not) | select(.metadata.name | startswith("coredns") | not) | "\(.metadata.namespace) \(.metadata.name)"' | while read namespace name; do
    if [ -n "$namespace" ] && [ -n "$name" ]; then
        echo "  Eliminando configmap: $namespace/$name"
        kubectl delete configmap "$name" -n "$namespace" --ignore-not-found=true
    fi
done

# 4. Limpiar secrets obsoletos (mantener solo los necesarios)
echo "🧹 Limpiando secrets obsoletos..."
kubectl get secrets --all-namespaces -o json | jq -r '.items[] | select(.metadata.name | startswith("default-token") | not) | select(.metadata.name | startswith("sh.helm.release") | not) | select(.metadata.name | startswith("k3s") | not) | "\(.metadata.namespace) \(.metadata.name)"' | while read namespace name; do
    if [ -n "$namespace" ] && [ -n "$name" ]; then
        echo "  Eliminando secret: $namespace/$name"
        kubectl delete secret "$name" -n "$namespace" --ignore-not-found=true
    fi
done

# 5. Limpiar eventos antiguos (más de 1 hora)
echo "🧹 Limpiando eventos antiguos..."
kubectl get events --all-namespaces --sort-by='.lastTimestamp' | awk '$1 != "NAMESPACE" && $2 != "LAST" {print $1 " " $2}' | while read namespace name; do
    if [ -n "$namespace" ] && [ -n "$name" ]; then
        kubectl delete events "$name" -n "$namespace" --ignore-not-found=true
    fi
done

# 6. Limpiar PVCs en estado Bound pero sin pods
echo "🧹 Limpiando PVCs huérfanos..."
kubectl get pvc --all-namespaces -o json | jq -r '.items[] | select(.status.phase == "Bound") | "\(.metadata.namespace) \(.metadata.name)"' | while read namespace name; do
    if [ -n "$namespace" ] && [ -n "$name" ]; then
        # Verificar si hay pods usando este PVC
        if ! kubectl get pods --all-namespaces -o json | jq -e --arg pvc "$name" --arg ns "$namespace" '.items[] | select(.spec.volumes[]?.persistentVolumeClaim?.claimName == $pvc and .metadata.namespace == $ns)' > /dev/null; then
            echo "  PVC huérfano encontrado: $namespace/$name"
            # No eliminar automáticamente, solo reportar
        fi
    fi
done

# 7. Mostrar estadísticas después de la limpieza
echo ""
echo "📊 Estadísticas después de la limpieza:"
echo "  Pods totales: $(kubectl get pods --all-namespaces --no-headers | wc -l)"
echo "  ConfigMaps: $(kubectl get configmaps --all-namespaces --no-headers | wc -l)"
echo "  Secrets: $(kubectl get secrets --all-namespaces --no-headers | wc -l)"
echo "  PVCs: $(kubectl get pvc --all-namespaces --no-headers | wc -l)"

# 8. Verificar estado del cluster
echo ""
echo "🔍 Verificando estado del cluster..."
kubectl get nodes
kubectl top nodes

echo ""
echo "✅ Limpieza completada"
echo "💡 Considera ejecutar este script periódicamente para mantener el cluster optimizado"
