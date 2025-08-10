#!/bin/bash

# Script para desplegar Gitea con PostgreSQL
# Autor: Generado para homelab-config
# Fecha: $(date)

set -e

echo "🚀 Desplegando Gitea con PostgreSQL..."

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

print_status "Verificando conectividad SSH al cluster..."
if ssh ubuntu@192.168.1.131 "echo 'SSH OK'" >/dev/null 2>&1; then
    print_success "Conectividad SSH establecida"
else
    print_error "No se puede conectar via SSH al cluster"
    exit 1
fi

print_status "Creando namespace si no existe..."
ssh ubuntu@192.168.1.131 "sudo k3s kubectl apply -f -" < cluster/gitea/namespace.yml

print_status "Eliminando deployment anterior de Gitea (si existe)..."
ssh ubuntu@192.168.1.131 "sudo k3s kubectl delete deployment gitea -n $NAMESPACE --ignore-not-found=true"
ssh ubuntu@192.168.1.131 "sudo k3s kubectl delete deployment gitea-postgres -n $NAMESPACE --ignore-not-found=true"

print_status "Esperando que los pods se eliminen..."
sleep 10

print_status "Aplicando PVCs..."
ssh ubuntu@192.168.1.131 "sudo k3s kubectl apply -f -" < cluster/gitea/pvc.yml
ssh ubuntu@192.168.1.131 "sudo k3s kubectl apply -f -" < cluster/gitea/pvc-nvme.yml

print_status "Aplicando configuración de PostgreSQL..."
ssh ubuntu@192.168.1.131 "sudo k3s kubectl apply -f -" < cluster/gitea/postgres.yml

print_status "Esperando que PostgreSQL esté listo..."
ssh ubuntu@192.168.1.131 "sudo k3s kubectl wait --for=condition=Ready pod -l app=gitea-postgres -n $NAMESPACE --timeout=120s" || print_warning "PostgreSQL tardó más de lo esperado en estar listo"

print_status "Aplicando configuración de Gitea..."
ssh ubuntu@192.168.1.131 "sudo k3s kubectl apply -f -" < cluster/gitea/configmap-app-ini.yml
ssh ubuntu@192.168.1.131 "sudo k3s kubectl apply -f -" < cluster/gitea/deployment.yml

print_status "Esperando que Gitea esté listo..."
ssh ubuntu@192.168.1.131 "sudo k3s kubectl wait --for=condition=Ready pod -l app=gitea -n $NAMESPACE --timeout=180s" || print_warning "Gitea tardó más de lo esperado en estar listo"

print_status "Aplicando servicios e ingress..."
ssh ubuntu@192.168.1.131 "sudo k3s kubectl apply -f -" < cluster/gitea/service.yml
ssh ubuntu@192.168.1.131 "sudo k3s kubectl apply -f -" < cluster/gitea/ingress.yml

print_success "✅ Despliegue completado!"

print_status "Verificando estado de los pods..."
ssh ubuntu@192.168.1.131 "sudo k3s kubectl get pods -n $NAMESPACE"

echo ""
print_status "Ejecutando verificación automática..."
./scripts/verify-gitea-postgres.sh

echo ""
print_success "🎉 Gitea con PostgreSQL desplegado exitosamente!"
echo ""
print_status "Próximos pasos:"
print_status "1. Accede a https://gitea.danielriquelme.cl"
print_status "2. Completa la configuración inicial de Gitea"
print_status "3. La base de datos PostgreSQL ya está configurada"
