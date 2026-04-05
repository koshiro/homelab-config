#!/bin/bash

# Script para verificar acceso local a Plex y obtener información para configuración en TV
# Autor: Daniel Riquelme

set -e

echo "🔍 Verificando acceso local a Plex..."
echo ""

# Colores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Verificar que kubectl esté disponible
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl no está instalado${NC}"
    exit 1
fi

# Verificar conexión al cluster
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}Error: No se puede conectar al cluster${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Cluster conectado${NC}"
echo ""

# Verificar servicio NodePort
echo "📡 Verificando servicio NodePort de Plex..."
NODEPORT_SVC=$(kubectl get svc plex-nodeport -n plex 2>/dev/null || echo "")
if [ -z "$NODEPORT_SVC" ]; then
    echo -e "${YELLOW}⚠ Servicio NodePort no encontrado. Aplicando configuración...${NC}"
    kubectl apply -k cluster/04-media-stack/plex/
    sleep 5
fi

NODEPORT=$(kubectl get svc plex-nodeport -n plex -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
if [ -z "$NODEPORT" ]; then
    echo -e "${RED}✗ No se pudo obtener el puerto NodePort${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Servicio NodePort activo en puerto: ${NODEPORT}${NC}"
echo ""

# Obtener IPs de los nodos
echo "🌐 Obteniendo IPs de los nodos del cluster..."
NODE_IPS=$(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "")

if [ -z "$NODE_IPS" ]; then
    echo -e "${YELLOW}⚠ No se pudieron obtener IPs internas, intentando con ExternalIP...${NC}"
    NODE_IPS=$(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="ExternalIP")].address}' 2>/dev/null || echo "")
fi

if [ -z "$NODE_IPS" ]; then
    echo -e "${RED}✗ No se pudieron obtener IPs de los nodos${NC}"
    echo "Por favor, ejecuta manualmente: kubectl get nodes -o wide"
    exit 1
fi

echo -e "${GREEN}✓ IPs de nodos encontradas:${NC}"
for IP in $NODE_IPS; do
    echo "   - $IP:$NODEPORT"
done
echo ""

# Verificar pod de Plex
echo "📦 Verificando estado del pod de Plex..."
PLEX_POD=$(kubectl get pods -n plex -l app=plex -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -z "$PLEX_POD" ]; then
    echo -e "${RED}✗ No se encontró el pod de Plex${NC}"
    exit 1
fi

PLEX_STATUS=$(kubectl get pod $PLEX_POD -n plex -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
if [ "$PLEX_STATUS" != "Running" ]; then
    echo -e "${YELLOW}⚠ Pod de Plex no está en estado Running (Estado: $PLEX_STATUS)${NC}"
else
    echo -e "${GREEN}✓ Pod de Plex está corriendo${NC}"
fi
echo ""


# Instrucciones para configurar TV

echo "📺 INSTRUCCIONES PARA CONFIGURAR TU TV:"
echo ""
echo "1. En la aplicación Plex de tu TV, ve a Configuración > Servidores"
echo "2. Selecciona 'Agregar servidor manualmente'"
echo "3. Ingresa una de las siguientes direcciones:"
for IP in $NODE_IPS; do
    echo "   - http://$IP:$NODEPORT"
done
echo ""
echo "4. Si tu TV no permite conexiones HTTP, configura Plex para permitir conexiones no seguras:"
echo "   - Ve a https://plex.danielriquelme.cl"
echo "   - Configuración > Red > Conexiones seguras: 'Preferido' (no 'Requerido')"
echo ""
echo "5. Verifica la conexión local desde tu navegador:"
FIRST_IP=$(echo $NODE_IPS | awk '{print $1}')
echo "   http://$FIRST_IP:$NODEPORT/web"
echo ""


