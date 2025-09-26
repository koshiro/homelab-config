#!/bin/bash

# Script detallado para monitorear transcoding de Plex

echo "🎬 Monitor Detallado de Transcoding de Plex"
echo "=========================================="
echo ""

# Obtener el nombre del pod de Plex
PLEX_POD=$(kubectl get pods -n plex -o jsonpath='{.items[0].metadata.name}')

if [ -z "$PLEX_POD" ]; then
    echo "❌ Error: No se encontró el pod de Plex"
    exit 1
fi

echo "📱 Pod de Plex: $PLEX_POD"
echo "⏰ Iniciando monitoreo cada 1 segundo..."
echo "Presiona Ctrl+C para salir"
echo ""

# Función para mostrar estadísticas
show_stats() {
    local timestamp=$(date '+%H:%M:%S')
    
    # Obtener estadísticas de GPU
    local gpu_stats=$(kubectl exec -n plex $PLEX_POD -- nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw --format=csv,noheader,nounits 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        IFS=',' read -r gpu_util mem_used mem_total temp power <<< "$gpu_stats"
        local mem_percent=$(( mem_used * 100 / mem_total ))
        
        echo "[$timestamp] 🖥️  GPU: ${gpu_util}% | 💾 RAM: ${mem_used}MB/${mem_total}MB (${mem_percent}%) | 🌡️  ${temp}°C | ⚡ ${power}W"
        
        # Detectar actividad de transcoding
        if [ "$gpu_util" -gt 5 ]; then
            echo "    🔥 TRANSCODING ACTIVO - Procesando video"
        elif [ "$gpu_util" -gt 0 ]; then
            echo "    ⚡ Actividad menor de GPU"
        else
            echo "    😴 GPU en reposo"
        fi
    else
        echo "[$timestamp] ❌ Error obteniendo estadísticas de GPU"
    fi
    
    # Mostrar procesos activos
    local processes=$(kubectl exec -n plex $PLEX_POD -- nvidia-smi pmon -c 1 2>/dev/null | tail -n +3 | grep -v "^\s*$")
    if [ ! -z "$processes" ]; then
        echo "    📊 Procesos: $processes"
    fi
}

# Monitoreo continuo
while true; do
    show_stats
    echo ""
    sleep 1
done
