#!/bin/bash

# Script para monitorear el uso de GPU de Plex durante transcoding

echo "🎬 Monitoreando uso de GPU de Plex..."
echo "Presiona Ctrl+C para salir"
echo ""

# Obtener el nombre del pod de Plex
PLEX_POD=$(kubectl get pods -n plex -o jsonpath='{.items[0].metadata.name}')

if [ -z "$PLEX_POD" ]; then
    echo "❌ Error: No se encontró el pod de Plex"
    exit 1
fi

echo "📱 Pod de Plex: $PLEX_POD"
echo ""

# Monitorear GPU cada 2 segundos
while true; do
    clear
    echo "🎬 Plex GPU Monitor - $(date)"
    echo "=================================="
    
    # Mostrar uso de GPU
    kubectl exec -n plex $PLEX_POD -- nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw --format=csv,noheader,nounits | while IFS=',' read -r gpu_util mem_used mem_total temp power; do
        echo "🖥️  GPU Usage: ${gpu_util}%"
        echo "💾 Memory: ${mem_used}MB / ${mem_total}MB ($(( mem_used * 100 / mem_total ))%)"
        echo "🌡️  Temperature: ${temp}°C"
        echo "⚡ Power: ${power}W"
    done
    
    echo ""
    echo "📊 Procesos activos:"
    kubectl exec -n plex $PLEX_POD -- nvidia-smi pmon -c 1 | tail -n +3
    
    echo ""
    echo "⏰ Actualizando en 2 segundos... (Ctrl+C para salir)"
    sleep 2
done
