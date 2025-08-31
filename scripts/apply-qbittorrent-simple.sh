#!/bin/bash

echo "🔧 === APLICANDO SOLUCIÓN SIMPLE PARA QBITTORRENT ==="
echo ""

# Función para esperar cluster
wait_for_cluster() {
    echo "⏳ Esperando conectividad del cluster..."
    for i in {1..10}; do
        if kubectl get nodes >/dev/null 2>&1; then
            echo "✅ Cluster conectado"
            return 0
        fi
        echo "Intento $i/10 - esperando 10s..."
        sleep 10
    done
    return 1
}

# Función para aplicar configuración
apply_config() {
    echo ""
    echo "📦 Aplicando configuración corregida..."
    
    if ! kubectl apply -f cluster/qbittorrent/configmap-simple-fix.yml; then
        echo "❌ Error aplicando ConfigMap"
        return 1
    fi
    
    if ! kubectl apply -k cluster/qbittorrent/; then
        echo "❌ Error aplicando Deployment"
        return 1
    fi
    
    echo "✅ Configuración aplicada"
    return 0
}

# Función para reiniciar qBittorrent
restart_qbittorrent() {
    echo ""
    echo "🔄 Reiniciando qBittorrent..."
    
    # Escalar a 0
    kubectl scale deployment qbittorrent --replicas=0 -n qbittorrent
    
    # Esperar que se eliminen los pods
    echo "⏳ Esperando shutdown..."
    kubectl wait --for=delete pod -l app=qbittorrent -n qbittorrent --timeout=60s 2>/dev/null || sleep 15
    
    # Escalar a 1
    kubectl scale deployment qbittorrent --replicas=1 -n qbittorrent
    
    # Esperar que esté listo
    echo "⏳ Esperando startup..."
    if kubectl wait --for=condition=ready pod -l app=qbittorrent -n qbittorrent --timeout=120s; then
        echo "✅ qBittorrent reiniciado exitosamente"
        return 0
    else
        echo "⚠️  Timeout esperando pod - puede estar iniciando aún"
        return 1
    fi
}

# Función para obtener credenciales
get_credentials() {
    echo ""
    echo "🔐 Obteniendo credenciales..."
    
    POD_NAME=$(kubectl get pod -n qbittorrent -l app=qbittorrent -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [ -n "$POD_NAME" ]; then
        echo "📱 Pod: $POD_NAME"
        
        # Esperar un poco más para que genere logs
        sleep 10
        
        TEMP_PASS=$(kubectl logs -n qbittorrent $POD_NAME 2>/dev/null | grep -E "session.*:" | tail -1 | sed 's/.*: //')
        
        if [ -n "$TEMP_PASS" ]; then
            echo "🔑 Contraseña temporal encontrada: $TEMP_PASS"
        else
            echo "⚠️  No se encontró contraseña temporal en logs aún"
        fi
        
        return 0
    else
        echo "❌ No se pudo obtener información del pod"
        return 1
    fi
}

# Función para mostrar instrucciones
show_instructions() {
    echo ""
    echo "🎯 === INSTRUCCIONES FINALES ==="
    echo ""
    echo "1. 🌐 ACCESO EXTERNO:"
    echo "   URL: https://qbittorrent.danielriquelme.cl"
    echo "   Usuario: admin"
    if [ -n "$TEMP_PASS" ]; then
        echo "   Contraseña temporal: $TEMP_PASS"
    else
        echo "   Contraseña temporal: Revisar logs del pod"
    fi
    echo "   Cambiar contraseña a: CD2JVibKzHBisuf"
    echo ""
    echo "2. ⚙️  CONFIGURACIÓN SONARR/RADARR:"
    echo "   Host: qbittorrent.qbittorrent.svc.cluster.local"
    echo "   Puerto: 8080"
    echo "   Usuario: admin"
    echo "   Contraseña: CD2JVibKzHBisuf"
    echo ""
    echo "3. 📂 RUTAS HARDLINKS:"
    echo "   Downloads: /downloads"
    echo "   Media: /media"
    echo ""
    echo "4. 🔍 VERIFICACIÓN:"
    echo "   kubectl logs -n qbittorrent <pod-name>"
    echo "   kubectl port-forward -n qbittorrent service/qbittorrent 8080:8080"
}

# Ejecución principal
main() {
    if ! wait_for_cluster; then
        echo ""
        echo "❌ No se pudo conectar al cluster"
        echo "Ejecuta manualmente cuando esté disponible:"
        echo ""
        echo "kubectl apply -f cluster/qbittorrent/configmap-simple-fix.yml"
        echo "kubectl apply -k cluster/qbittorrent/"
        echo "kubectl scale deployment qbittorrent --replicas=0 -n qbittorrent"
        echo "kubectl scale deployment qbittorrent --replicas=1 -n qbittorrent"
        echo ""
        exit 1
    fi
    
    if ! apply_config; then
        echo "❌ Error aplicando configuración"
        exit 1
    fi
    
    if restart_qbittorrent; then
        get_credentials
    else
        echo "⚠️  Reinicio con problemas, pero continuando..."
    fi
    
    show_instructions
}

# Preguntar confirmación
echo "Este script aplicará la configuración corregida de qBittorrent"
echo "¿Continuar? (y/N)"
read -r CONFIRM

if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
    main
else
    echo "Cancelado por el usuario"
fi

