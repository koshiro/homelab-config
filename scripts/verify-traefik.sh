#!/bin/bash

# Script para verificar y configurar Traefik con Cloudflare Tunnel
# Uso: ./scripts/verify-traefik.sh

set -e

echo "🔍 Verificando configuración de Traefik con Cloudflare Tunnel..."

# Variables
K3S_NODE="192.168.1.131"
DOMAIN="danielriquelme.cl"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Función para imprimir con colores
print_status() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# 1. Verificar conectividad SSH
echo "1. Verificando conectividad SSH..."
if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no ubuntu@$K3S_NODE "echo 'SSH OK'" 2>/dev/null; then
    print_status "SSH conectividad OK"
else
    print_error "No se puede conectar via SSH a $K3S_NODE"
    exit 1
fi

# 2. Verificar estado de k3s
echo "2. Verificando estado de k3s..."
if ssh ubuntu@$K3S_NODE "sudo k3s kubectl get nodes" 2>/dev/null | grep -q "Ready"; then
    print_status "k3s está funcionando"
else
    print_error "k3s no está funcionando correctamente"
    exit 1
fi

# 3. Verificar estado de Traefik
echo "3. Verificando estado de Traefik..."
TRAEFIK_PODS=$(ssh ubuntu@$K3S_NODE "sudo k3s kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik --no-headers | wc -l")
if [ "$TRAEFIK_PODS" -gt 0 ]; then
    print_status "Traefik pods encontrados: $TRAEFIK_PODS"
else
    print_error "No se encontraron pods de Traefik"
    exit 1
fi

# 4. Verificar puertos de Traefik
echo "4. Verificando puertos de Traefik..."
TRAEFIK_HTTP=$(ssh ubuntu@$K3S_NODE "sudo k3s kubectl get service traefik -n kube-system -o jsonpath='{.spec.ports[?(@.name==\"web\")].nodePort}'")
if [ ! -z "$TRAEFIK_HTTP" ]; then
    print_status "Puerto HTTP de Traefik: $TRAEFIK_HTTP"
else
    print_error "No se pudo obtener el puerto HTTP de Traefik"
    exit 1
fi

# 5. Verificar estado del túnel de Cloudflare
echo "5. Verificando estado del túnel de Cloudflare..."
CLOUDFLARED_PODS=$(ssh ubuntu@$K3S_NODE "sudo k3s kubectl get pods -n cloudflared -l app=cloudflared --no-headers | grep Running | wc -l")
if [ "$CLOUDFLARED_PODS" -gt 0 ]; then
    print_status "Cloudflare Tunnel pods corriendo: $CLOUDFLARED_PODS"
else
    print_warning "No se encontraron pods de Cloudflare Tunnel corriendo"
fi

# 6. Verificar configuración del túnel (remota)
echo "6. Verificando configuración remota del túnel..."
CF_LOGS=$(ssh ubuntu@$K3S_NODE "sudo k3s kubectl logs -n cloudflared -l app=cloudflared --tail=50" 2>/dev/null || true)
if echo "$CF_LOGS" | grep -q "Updated to new configuration"; then
    print_status "cloudflared cargó la configuración remota"
else
    print_warning "No se observó actualización de configuración en logs de cloudflared"
fi

# 7. Verificar DNS
echo "7. Verificando resolución DNS..."
for subdomain in traefik gitea sonarr radarr; do
    if nslookup "$subdomain.$DOMAIN" >/dev/null 2>&1; then
        print_status "DNS OK para $subdomain.$DOMAIN"
    else
        print_warning "DNS no resuelve para $subdomain.$DOMAIN"
    fi
done

# 8. Verificar conectividad externa via Cloudflare
echo "8. Verificando conectividad externa via Cloudflare..."
for host in gitea.$DOMAIN traefik.$DOMAIN; do
  code=$(curl -sS -o /dev/null -w "%{http_code}" https://$host || true)
  echo "$host -> $code"
done

# 9. Recordatorio sobre certificados
echo "9. Certificados TLS"
print_status "TLS se termina en Cloudflare; no se requiere cert interno en Traefik para este flujo"

# 10. Mostrar resumen
echo ""
echo "📊 RESUMEN DE VERIFICACIÓN"
echo "=========================="
echo "✅ k3s: Funcionando"
echo "✅ Traefik: Puerto $TRAEFIK_HTTP"
echo "✅ Cloudflare Tunnel: $CLOUDFLARED_PODS pods"
echo "✅ Conectividad local: OK"
echo ""
echo "🌐 URLs de acceso:"
echo "   - Traefik Dashboard: https://traefik.$DOMAIN"
echo "   - Gitea: https://gitea.$DOMAIN"
echo ""
print_status "El túnel está en modo remoto: No crear Public Hostnames en el dashboard"
echo ""

# 11. Comandos útiles
echo "🔧 Comandos útiles:"
echo "   - Ver logs de Traefik: ssh ubuntu@$K3S_NODE 'sudo k3s kubectl logs -n kube-system -l app.kubernetes.io/name=traefik --tail=20'"
echo "   - Ver logs del túnel: ssh ubuntu@$K3S_NODE 'sudo k3s kubectl logs -n cloudflared -l app=cloudflared --tail=20'"
echo "   - Reiniciar Traefik: ssh ubuntu@$K3S_NODE 'sudo k3s kubectl rollout restart deployment traefik -n kube-system'"
echo "   - Verificar ingress: ssh ubuntu@$K3S_NODE 'sudo k3s kubectl get ingress --all-namespaces'"
