#!/bin/bash

# Script para configurar Plex con acceso remoto a través de Cloudflare Tunnel
# Autor: Daniel Riquelme
# Fecha: $(date +%Y-%m-%d)

set -e

echo "🔧 Configurando Plex para acceso remoto..."

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Función para logging
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

# Verificar que kubectl esté disponible
if ! command -v kubectl &> /dev/null; then
    error "kubectl no está instalado o no está en el PATH"
    exit 1
fi

# Verificar conexión al cluster
if ! kubectl cluster-info &> /dev/null; then
    error "No se puede conectar al cluster de Kubernetes"
    exit 1
fi

log "Aplicando configuración de Plex..."

# Aplicar configuración de Plex
kubectl apply -k cluster/04-media-stack/plex/

# Aplicar configuración actualizada de Cloudflare Tunnel
kubectl apply -f cluster/06-external/cloudflared/configmap-tunnel.yml

log "Esperando que los pods estén listos..."

# Esperar a que Plex esté listo
kubectl wait --for=condition=ready pod -l app=plex -n plex --timeout=300s

# Verificar el estado de los pods
log "Verificando estado de los pods..."
kubectl get pods -n plex

# Verificar el servicio
log "Verificando servicio de Plex..."
kubectl get svc -n plex

# Verificar el ingress
log "Verificando ingress de Plex..."
kubectl get ingress -n plex

# Verificar el middleware
log "Verificando middleware de Plex..."
kubectl get middleware -n plex

# Verificar la configuración del túnel de Cloudflare
log "Verificando configuración del túnel de Cloudflare..."
kubectl get configmap cloudflared-tunnel-config -n cloudflared -o yaml

# Obtener la IP del servicio de Plex
PLEX_IP=$(kubectl get svc plex -n plex -o jsonpath='{.spec.clusterIP}')
log "IP del servicio Plex: $PLEX_IP"

# Verificar conectividad interna
log "Verificando conectividad interna al servicio Plex..."
kubectl run test-pod --rm -i --tty --image=busybox --restart=Never -- nslookup plex.plex.svc.cluster.local

log "✅ Configuración aplicada exitosamente!"
log ""
log "📋 Pasos siguientes:"
log "1. Accede a https://plex.danielriquelme.cl"
log "2. Configura tu servidor Plex"
log "3. En Configuración > Red > Acceso remoto:"
log "   - Marca 'Especificar puerto público manualmente'"
log "   - Puerto público: 443"
log "   - Puerto privado: 32400"
log "4. En Configuración > Red > Conexiones:"
log "   - Marca 'Mostrar conexiones avanzadas'"
log "   - URL personalizada para acceso: https://plex.danielriquelme.cl"
log ""
log "🔍 Para verificar el estado:"
log "kubectl get pods -n plex"
log "kubectl logs -f deployment/plex -n plex"
log ""
log "🌐 Para verificar el túnel:"
log "kubectl logs -f deployment/cloudflared -n cloudflared"
