#!/bin/bash

# Script para actualizar Plex Media Server en Kubernetes
# Evita conflictos de GPU usando estrategia Recreate

set -e

echo "🎬 Actualizando Plex Media Server..."

# Verificar que kubectl esté disponible
if ! command -v kubectl &> /dev/null; then
    echo "❌ Error: kubectl no está instalado o no está en el PATH"
    exit 1
fi

# Verificar que el namespace plex existe
if ! kubectl get namespace plex &> /dev/null; then
    echo "❌ Error: El namespace 'plex' no existe"
    exit 1
fi

echo "📋 Estado actual de Plex:"
kubectl get pods -n plex

echo ""
echo "🔄 Iniciando actualización de Plex..."

# Forzar la descarga de la nueva imagen
echo "📥 Descargando nueva imagen de Plex..."
kubectl rollout restart deployment/plex -n plex

echo "⏳ Esperando a que el nuevo pod esté listo..."
kubectl rollout status deployment/plex -n plex --timeout=300s

echo ""
echo "✅ Actualización completada!"
echo "📋 Estado final:"
kubectl get pods -n plex

echo ""
echo "🔍 Verificando versión de Plex:"
kubectl exec -n plex $(kubectl get pods -n plex -o jsonpath='{.items[0].metadata.name}') -- /usr/lib/plexmediaserver/Plex\ Media\ Server --version

echo ""
echo "🎉 ¡Plex actualizado exitosamente!"
