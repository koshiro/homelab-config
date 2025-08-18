#!/bin/bash

# 🏠 Script de Configuración del Dashboard Homepage para Homelab
# Este script configura y despliega Homepage con Tailscale para acceso privado

set -e

echo "🏠 Configurando Dashboard Homepage para Homelab..."
echo "=================================================="

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Función para logging
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Verificar que estamos en el directorio correcto
if [[ ! -f "cluster/kustomization.yml" ]]; then
    log_error "Este script debe ejecutarse desde el directorio raíz del proyecto"
    exit 1
fi

# Verificar que kubectl esté disponible
if ! command -v kubectl &> /dev/null; then
    log_error "kubectl no está instalado o no está en el PATH"
    exit 1
fi

# Verificar conexión al clúster
log_info "Verificando conexión al clúster Kubernetes..."
if ! kubectl cluster-info &> /dev/null; then
    log_error "No se puede conectar al clúster Kubernetes"
    exit 1
fi

log_success "Conectado al clúster: $(kubectl cluster-info | head -n1)"

# Verificar que Tailscale esté funcionando
log_info "Verificando estado de Tailscale..."
if ! kubectl get pods -n tailscale &> /dev/null; then
    log_warning "Namespace de Tailscale no encontrado. Asegúrate de que esté desplegado."
else
    TAILSCALE_PODS=$(kubectl get pods -n tailscale -o jsonpath='{.items[*].status.phase}' | tr ' ' '\n' | grep -c "Running" || echo "0")
    if [[ $TAILSCALE_PODS -gt 0 ]]; then
        log_success "Tailscale está funcionando con $TAILSCALE_PODS pods"
    else
        log_warning "Tailscale no tiene pods corriendo"
    fi
fi

# Verificar que Traefik esté funcionando
log_info "Verificando estado de Traefik..."
if ! kubectl get pods -n traefik &> /dev/null; then
    log_warning "Namespace de Traefik no encontrado. Asegúrate de que esté desplegado."
else
    TRAEFIK_PODS=$(kubectl get pods -n traefik -o jsonpath='{.items[*].status.phase}' | tr ' ' '\n' | grep -c "Running" || echo "0")
    if [[ $TRAEFIK_PODS -gt 0 ]]; then
        log_success "Traefik está funcionando con $TRAEFIK_PODS pods"
    else
        log_warning "Traefik no tiene pods corriendo"
    fi
fi

# Verificar y encriptar secretos con SOPS
log_info "Verificando secretos y encriptación..."
if [[ -f "scripts/encrypt-homepage-secrets.sh" ]]; then
    log_info "Ejecutando encriptación de secretos..."
    ./scripts/encrypt-homepage-secrets.sh
else
    log_warning "Script de encriptación no encontrado. Asegúrate de encriptar manualmente:"
    log_info "sops -e -i cluster/homepage/secret-credentials.sops.yml"
fi

# Desplegar Homepage
log_info "Desplegando Homepage..."
kubectl apply -k cluster/homepage/

# Esperar a que el pod esté listo
log_info "Esperando a que Homepage esté listo..."
kubectl wait --for=condition=ready pod -l app=homepage -n homepage --timeout=300s

# Verificar el estado
log_info "Verificando estado del despliegue..."
kubectl get pods -n homepage
kubectl get svc -n homepage
kubectl get ingress -n homepage

# Obtener la IP del servicio
log_info "Obteniendo información del servicio..."
HOMEPAGE_SERVICE_IP=$(kubectl get svc homepage -n homepage -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "N/A")

if [[ "$HOMEPAGE_SERVICE_IP" != "N/A" ]]; then
    log_success "Homepage está disponible en: http://$HOMEPAGE_SERVICE_IP:3000"
else
    log_info "Homepage está disponible internamente en: http://homepage.homepage.svc.cluster.local:3000"
fi

# Verificar acceso a través de Tailscale
log_info "Verificando acceso a través de Tailscale..."
if command -v tailscale &> /dev/null; then
    TAILSCALE_STATUS=$(tailscale status 2>/dev/null | grep -c "Running" || echo "0")
    if [[ $TAILSCALE_STATUS -gt 0 ]]; then
        log_success "Tailscale está funcionando en tu máquina local"
        log_info "Puedes acceder a Homepage a través de tu red Tailscale"
    else
        log_warning "Tailscale no está funcionando en tu máquina local"
    fi
else
    log_warning "Tailscale no está instalado en tu máquina local"
fi

# Mostrar información de configuración
echo ""
echo "🎯 Configuración de Homepage Completada"
echo "======================================"
echo ""
echo "📱 Acceso al Dashboard:"
echo "   - Local: http://192.168.1.131/homepage"
echo "   - Tailscale: https://homepage.tail*.ts.net"
echo ""
echo "🔧 Servicios Monitoreados:"
echo "   - Proxmox (192.168.1.100:8006)"
echo "   - TrueNAS (192.168.1.20)"
echo "   - Kubernetes (192.168.1.131:32634)"
echo "   - Plex, Sonarr, Radarr, etc."
echo ""
echo "📊 Widgets Disponibles:"
echo "   - Estado del sistema"
echo "   - Contenedores Docker"
echo "   - Pods de Kubernetes"
echo "   - Métricas de servicios"
echo ""
echo "🔐 Credenciales:"
echo "   - Edita cluster/homepage/secret-credentials.sops.yml"
echo "   - Configura las API keys de tus servicios"
echo "   - Usa SOPS para encriptar los secretos"
echo ""
echo "🚀 Próximos pasos:"
echo "   1. Configura las credenciales en el archivo de secretos"
echo "   2. Personaliza la configuración según tus necesidades"
echo "   3. Accede al dashboard a través de Tailscale"
echo "   4. Configura los widgets de monitoreo"
echo ""

log_success "¡Dashboard Homepage configurado exitosamente!"
log_info "Revisa los logs si encuentras algún problema: kubectl logs -f -l app=homepage -n homepage"
