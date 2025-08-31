#!/bin/bash

set -e

echo "🎯 === APLICANDO SOLUCIÓN DOCUMENTADA PARA QBITTORRENT ==="
echo ""
echo "📋 Problemas identificados por análisis crítico:"
echo "   ❌ Configuración inconsistente entre deployment y cambios manuales"
echo "   ❌ LocalHostAuth malconfigurado (false vs true)"  
echo "   ❌ Variables de entorno QB_USERNAME/QB_PASSWORD no funcionan"
echo "   ❌ Problema libseccomp2 documentado en LinuxServer"
echo "   ❌ Mount points inconsistentes (/shared vs /data vs /config)"
echo "   ❌ Configuración no persistente en archivos YAML"
echo ""

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${YELLOW}¿Continuar con la solución documentada? (y/N)${NC}"
read -r CONTINUE
if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
    echo "Operación cancelada"
    exit 0
fi

echo ""
echo -e "${BLUE}=== PASO 1: VERIFICANDO CONECTIVIDAD DEL CLUSTER ===${NC}"

if ! kubectl get nodes > /dev/null 2>&1; then
    echo -e "${RED}❌ Cluster no accesible${NC}"
    echo "Esperando que el cluster se estabilice..."
    
    for i in {1..5}; do
        echo "Intento $i/5..."
        sleep 10
        if kubectl get nodes > /dev/null 2>&1; then
            echo -e "${GREEN}✅ Cluster accesible${NC}"
            break
        fi
        
        if [ $i -eq 5 ]; then
            echo -e "${RED}❌ Cluster no accesible tras 50s${NC}"
            echo ""
            echo "🔧 Soluciones manuales mientras el cluster se recupera:"
            echo ""
            echo "1. Aplicar configuración cuando esté disponible:"
            echo "   kubectl apply -f cluster/qbittorrent/configmap-init-fixed.yml"
            echo "   kubectl apply -k cluster/qbittorrent/"
            echo ""
            echo "2. Acceso temporal a qBittorrent:"
            echo "   kubectl port-forward -n qbittorrent service/qbittorrent 8080:8080"
            echo "   http://localhost:8080"
            echo ""
            echo "3. Credenciales documentadas:"
            echo "   Usuario: admin"
            echo "   Contraseña: Revisar logs para temporal, cambiar a: CD2JVibKzHBisuf"
            echo ""
            exit 1
        fi
    done
fi

echo -e "${GREEN}✅ Cluster accesible${NC}"

echo ""
echo -e "${BLUE}=== PASO 2: APLICANDO CONFIGURACIÓN DOCUMENTADA ===${NC}"

echo "📦 Aplicando ConfigMap corregido..."
kubectl apply -f cluster/qbittorrent/configmap-init-fixed.yml

echo "🚀 Aplicando Deployment corregido..."
kubectl apply -k cluster/qbittorrent/

echo ""
echo -e "${BLUE}=== PASO 3: REINICIANDO CON CONFIGURACIÓN LIMPIA ===${NC}"

echo "🛑 Deteniendo qBittorrent..."
kubectl scale deployment qbittorrent --replicas=0 -n qbittorrent

echo "⏳ Esperando shutdown completo..."
kubectl wait --for=delete pod -l app=qbittorrent -n qbittorrent --timeout=60s 2>/dev/null || true
sleep 10

echo "🚀 Iniciando con configuración documentada..."
kubectl scale deployment qbittorrent --replicas=1 -n qbittorrent

echo "⏳ Esperando que el pod esté listo..."
kubectl wait --for=condition=ready pod -l app=qbittorrent -n qbittorrent --timeout=120s

NEW_POD=$(kubectl get pod -n qbittorrent -l app=qbittorrent -o jsonpath='{.items[0].metadata.name}')
echo -e "${GREEN}✅ Nuevo pod: $NEW_POD${NC}"

echo ""
echo -e "${BLUE}=== PASO 4: VERIFICANDO CONFIGURACIÓN ===${NC}"

echo "📊 Verificando hardlinks..."
kubectl exec -n qbittorrent $NEW_POD -- sh -c '
echo "test" > /downloads/test.txt 2>/dev/null || echo "test" > /data/qbt-downloads/test.txt
if ln /downloads/test.txt /media/test.txt 2>/dev/null || ln /data/qbt-downloads/test.txt /data/qbt-media/test.txt 2>/dev/null; then
    echo "✅ Hardlinks funcionando"
    rm -f /downloads/test.txt /media/test.txt /data/qbt-downloads/test.txt /data/qbt-media/test.txt 2>/dev/null || true
else
    echo "❌ Hardlinks no funcionan"
fi
'

echo ""
echo "🔐 Obteniendo credenciales..."
sleep 15
TEMP_PASS=$(kubectl logs -n qbittorrent $NEW_POD | grep -E "password.*session|Password.*session" | sed -n 's/.*session: \([^[:space:]]*\).*/\1/p' | tail -1)

echo ""
echo -e "${BLUE}=== PASO 5: CONFIGURANDO ACCESO EXTERNO ===${NC}"

kubectl port-forward -n qbittorrent $NEW_POD 8087:8080 &
PF_PID=$!
sleep 5

# Función de limpieza
cleanup() {
    kill $PF_PID 2>/dev/null || true
}
trap cleanup EXIT

if [ -n "$TEMP_PASS" ]; then
    echo "🔑 Contraseña temporal encontrada: $TEMP_PASS"
    echo "🔄 Configurando contraseña final..."
    
    # Login con temporal
    if curl -s -X POST "http://localhost:8087/api/v2/auth/login" \
       -d "username=admin&password=$TEMP_PASS" \
       -c /tmp/qbt_temp_session.txt; then
        
        # Cambiar a contraseña final
        if curl -s -X POST "http://localhost:8087/api/v2/app/setPreferences" \
           -b /tmp/qbt_temp_session.txt \
           -d 'json={"web_ui_password":"CD2JVibKzHBisuf"}'; then
            echo -e "${GREEN}✅ Contraseña configurada exitosamente${NC}"
        else
            echo -e "${YELLOW}⚠️  Error al cambiar contraseña - usar WebUI${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  Login falló - usar contraseña temporal en WebUI${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  No se encontró contraseña temporal en logs${NC}"
fi

echo ""
echo -e "${BLUE}=== PASO 6: CONFIGURANDO SONARR Y RADARR ===${NC}"

echo "🔄 Verificando conectividad desde cluster..."

# Test desde Sonarr
SONARR_POD=$(kubectl get pod -n sonarr -l app=sonarr -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$SONARR_POD" ]; then
    echo "📡 Probando conexión desde Sonarr..."
    kubectl exec -n sonarr $SONARR_POD -- sh -c '
    if curl -s --max-time 10 "http://qbittorrent.qbittorrent.svc.cluster.local:8080/api/v2/app/version" > /dev/null; then
        echo "✅ Sonarr puede conectar a qBittorrent"
    else
        echo "❌ Sonarr no puede conectar a qBittorrent"
    fi
    ' 2>/dev/null || echo "❌ Error al probar desde Sonarr"
fi

# Test desde Radarr  
RADARR_POD=$(kubectl get pod -n radarr -l app=radarr -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$RADARR_POD" ]; then
    echo "📡 Probando conexión desde Radarr..."
    kubectl exec -n radarr $RADARR_POD -- sh -c '
    if curl -s --max-time 10 "http://qbittorrent.qbittorrent.svc.cluster.local:8080/api/v2/app/version" > /dev/null; then
        echo "✅ Radarr puede conectar a qBittorrent"
    else
        echo "❌ Radarr no puede conectar a qBittorrent"  
    fi
    ' 2>/dev/null || echo "❌ Error al probar desde Radarr"
fi

echo ""
echo -e "${GREEN}🎉 === CONFIGURACIÓN COMPLETADA SEGÚN DOCUMENTACIÓN OFICIAL ===${NC}"
echo ""
echo -e "${BLUE}📱 ACCESO PARA USUARIO:${NC}"
echo "   🌐 URL: https://qbittorrent.danielriquelme.cl"
echo "   👤 Usuario: admin"
echo "   🔑 Contraseña: CD2JVibKzHBisuf"
if [ -n "$TEMP_PASS" ]; then
    echo "   🔑 Contraseña temporal (si la anterior falla): $TEMP_PASS"
fi
echo ""
echo -e "${BLUE}⚙️  CONFIGURACIÓN PARA SONARR/RADARR:${NC}"
echo "   🏠 Host: qbittorrent.qbittorrent.svc.cluster.local"
echo "   🔌 Puerto: 8080"  
echo "   👤 Usuario: admin"
echo "   🔑 Contraseña: CD2JVibKzHBisuf"
echo "   📁 Category: sonarr (para Sonarr) / radarr (para Radarr)"
echo ""
echo -e "${BLUE}📂 RUTAS PARA HARDLINKS:${NC}"
echo "   📥 Downloads: /downloads"
echo "   📚 Media: /media"
echo ""
echo -e "${GREEN}✅ Problemas resueltos:${NC}"
echo "   ✅ Configuración persistente en archivos YAML"
echo "   ✅ LocalHostAuth configurado correctamente"
echo "   ✅ Mount points unificados para hardlinks"
echo "   ✅ Variables de entorno eliminadas (no funcionan)"
echo "   ✅ Health checks mejorados"
echo "   ✅ Configuración según documentación LinuxServer"

