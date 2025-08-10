#!/bin/bash

# Script para verificar que Gitea con PostgreSQL esté funcionando correctamente
# Autor: Generado para homelab-config
# Fecha: $(date)

set -e

echo "🔍 Verificando configuración de Gitea con PostgreSQL..."

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Función para mostrar mensajes
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# Variables
NAMESPACE="gitea"
POSTGRES_POD=""
GITEA_POD=""

print_status "Verificando conectividad SSH al cluster..."
if ssh ubuntu@192.168.1.131 "echo 'SSH OK'" >/dev/null 2>&1; then
    print_success "Conectividad SSH establecida"
else
    print_error "No se puede conectar via SSH al cluster"
    exit 1
fi

print_status "Verificando estado del namespace $NAMESPACE..."
if ssh ubuntu@192.168.1.131 "sudo k3s kubectl get namespace $NAMESPACE" >/dev/null 2>&1; then
    print_success "Namespace $NAMESPACE existe"
else
    print_error "Namespace $NAMESPACE no encontrado"
    exit 1
fi

print_status "Verificando pods de PostgreSQL..."
POSTGRES_POD=$(ssh ubuntu@192.168.1.131 "sudo k3s kubectl get pods -n $NAMESPACE -l app=gitea-postgres -o jsonpath='{.items[0].metadata.name}' 2>/dev/null" || echo "")

if [ -n "$POSTGRES_POD" ]; then
    print_success "Pod PostgreSQL encontrado: $POSTGRES_POD"
    
    # Verificar estado del pod
    POSTGRES_STATUS=$(ssh ubuntu@192.168.1.131 "sudo k3s kubectl get pod $POSTGRES_POD -n $NAMESPACE -o jsonpath='{.status.phase}'" 2>/dev/null || echo "")
    if [ "$POSTGRES_STATUS" = "Running" ]; then
        print_success "PostgreSQL está ejecutándose"
    else
        print_warning "PostgreSQL estado: $POSTGRES_STATUS"
    fi
else
    print_error "Pod PostgreSQL no encontrado"
    exit 1
fi

print_status "Verificando pods de Gitea..."
GITEA_POD=$(ssh ubuntu@192.168.1.131 "sudo k3s kubectl get pods -n $NAMESPACE -l app=gitea -o jsonpath='{.items[0].metadata.name}' 2>/dev/null" || echo "")

if [ -n "$GITEA_POD" ]; then
    print_success "Pod Gitea encontrado: $GITEA_POD"
    
    # Verificar estado del pod
    GITEA_STATUS=$(ssh ubuntu@192.168.1.131 "sudo k3s kubectl get pod $GITEA_POD -n $NAMESPACE -o jsonpath='{.status.phase}'" 2>/dev/null || echo "")
    if [ "$GITEA_STATUS" = "Running" ]; then
        print_success "Gitea está ejecutándose"
    else
        print_warning "Gitea estado: $GITEA_STATUS"
    fi
else
    print_error "Pod Gitea no encontrado"
    exit 1
fi

print_status "Verificando conectividad de PostgreSQL..."
DB_TEST=$(ssh ubuntu@192.168.1.131 "sudo k3s kubectl exec $POSTGRES_POD -n $NAMESPACE -- pg_isready -U gitea -d gitea" 2>/dev/null || echo "ERROR")

if [[ "$DB_TEST" == *"accepting connections"* ]]; then
    print_success "PostgreSQL acepta conexiones"
else
    print_error "PostgreSQL no acepta conexiones: $DB_TEST"
fi

print_status "Verificando tablas de Gitea en PostgreSQL..."
TABLE_COUNT=$(ssh ubuntu@192.168.1.131 "sudo k3s kubectl exec $POSTGRES_POD -n $NAMESPACE -- psql -U gitea -d gitea -t -c \"SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';\"" 2>/dev/null | tr -d ' ' || echo "0")

if [ "$TABLE_COUNT" -gt "0" ]; then
    print_success "Base de datos Gitea tiene $TABLE_COUNT tablas"
else
    print_warning "Base de datos Gitea parece vacía (tablas: $TABLE_COUNT)"
    print_status "Esto es normal si es la primera instalación"
fi

print_status "Verificando servicio de Gitea..."
GITEA_SERVICE=$(ssh ubuntu@192.168.1.131 "sudo k3s kubectl get service gitea -n $NAMESPACE -o jsonpath='{.spec.ports[0].port}'" 2>/dev/null || echo "")

if [ -n "$GITEA_SERVICE" ]; then
    print_success "Servicio Gitea disponible en puerto $GITEA_SERVICE"
else
    print_error "Servicio Gitea no encontrado"
fi

print_status "Verificando health endpoint de Gitea..."
HEALTH_CHECK=$(ssh ubuntu@192.168.1.131 "sudo k3s kubectl exec $GITEA_POD -n $NAMESPACE -- wget -q -O - http://localhost:3000/api/healthz 2>/dev/null" || echo "ERROR")

if [[ "$HEALTH_CHECK" == *"ok"* ]] || [[ "$HEALTH_CHECK" == *"OK"* ]]; then
    print_success "Health check de Gitea: OK"
else
    print_warning "Health check de Gitea: $HEALTH_CHECK"
fi

print_status "Verificando logs de Gitea (últimas 5 líneas)..."
echo "--- Logs de Gitea ---"
ssh ubuntu@192.168.1.131 "sudo k3s kubectl logs $GITEA_POD -n $NAMESPACE --tail=5" 2>/dev/null || echo "No se pudieron obtener logs"
echo "--- Fin logs ---"

print_status "Verificando logs de PostgreSQL (últimas 5 líneas)..."
echo "--- Logs de PostgreSQL ---"
ssh ubuntu@192.168.1.131 "sudo k3s kubectl logs $POSTGRES_POD -n $NAMESPACE --tail=5" 2>/dev/null || echo "No se pudieron obtener logs"
echo "--- Fin logs ---"

print_status "Verificando ingress..."
INGRESS_HOST=$(ssh ubuntu@192.168.1.131 "sudo k3s kubectl get ingress gitea -n $NAMESPACE -o jsonpath='{.spec.rules[0].host}'" 2>/dev/null || echo "")

if [ -n "$INGRESS_HOST" ]; then
    print_success "Ingress configurado para: $INGRESS_HOST"
    print_status "Verificando acceso HTTPS..."
    
    if curl -s -k "https://$INGRESS_HOST" >/dev/null 2>&1; then
        print_success "HTTPS accesible en https://$INGRESS_HOST"
    else
        print_warning "HTTPS no accesible aún en https://$INGRESS_HOST"
        print_status "Esto puede ser normal si el túnel de Cloudflare aún se está configurando"
    fi
else
    print_error "Ingress no configurado"
fi

echo ""
print_success "✅ Verificación completada!"
echo ""
print_status "Resumen de URLs:"
print_status "- Gitea Web UI: https://$INGRESS_HOST"
print_status "- Health Check: https://$INGRESS_HOST/api/healthz"
echo ""
print_status "Para acceder a la configuración inicial de Gitea:"
print_status "1. Visita https://$INGRESS_HOST"
print_status "2. Completa la configuración inicial si es necesario"
print_status "3. La base de datos PostgreSQL ya está configurada automáticamente"
