#!/bin/bash
# Este script verifica la instalación y funcionamiento de Immich en el clúster Kubernetes

# Colores para output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Funciones de utilidad
print_header() {
    echo -e "\n${YELLOW}==== $1 ====${NC}\n"
}

check_success() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ $1${NC}"
    else
        echo -e "${RED}✗ $1${NC}"
        [ -n "$2" ] && [ "$2" = "exit" ] && exit 1
    fi
}

# Verificar existencia del namespace
print_header "Verificando namespace de Immich"
kubectl get namespace immich
check_success "Namespace immich existe"

# Verificar PVCs
print_header "Verificando Persistent Volume Claims"
kubectl get pvc -n immich
check_success "PVCs de Immich existen"

# Verificar Pods
print_header "Verificando Pods de Immich"
kubectl get pods -n immich
check_success "Pods de Immich están creados"

# Verificar estado de los Pods
print_header "Verificando estado de los Pods"
READY_COUNT=$(kubectl get pods -n immich -o jsonpath="{.items[*].status.containerStatuses[*].ready}" | tr -s '[:space:]' ' ' | sed 's/ /+/g' | bc)
TOTAL_COUNT=$(kubectl get pods -n immich -o jsonpath="{.items[*].status.containerStatuses[*].ready}" | wc -w)

if [ "$READY_COUNT" -eq "$TOTAL_COUNT" ]; then
    echo -e "${GREEN}✓ Todos los contenedores están listos ($READY_COUNT/$TOTAL_COUNT)${NC}"
else
    echo -e "${RED}✗ No todos los contenedores están listos ($READY_COUNT/$TOTAL_COUNT)${NC}"
fi

# Verificar conectividad de red
print_header "Verificando conectividad de red"
SERVER_POD=$(kubectl get pod -n immich -l app=immich-server -o jsonpath="{.items[0].metadata.name}")
if [ -n "$SERVER_POD" ]; then
    echo "Verificando conexión desde immich-server a immich-db..."
    kubectl exec -n immich $SERVER_POD -- sh -c "nc -zv immich-db 5432" 2>/dev/null
    check_success "Conexión a la base de datos"
    
    echo "Verificando conexión desde immich-server a immich-redis..."
    kubectl exec -n immich $SERVER_POD -- sh -c "nc -zv immich-redis 6379" 2>/dev/null
    check_success "Conexión a Redis"
else
    echo -e "${RED}✗ No se encontró un pod para immich-server${NC}"
fi

# Verificar montaje de volúmenes
print_header "Verificando montaje de volúmenes"
if [ -n "$SERVER_POD" ]; then
    kubectl exec -n immich $SERVER_POD -- sh -c "df -h | grep -E '(library|upload)'"
    check_success "Volúmenes montados correctamente"
fi

# Verificar acceso externo
print_header "Verificando acceso externo (Ingress)"
kubectl get ingress -n immich
check_success "Ingress configurado"

# Comprobar servicio web
print_header "Verificando servicio web"
curl -s -o /dev/null -w "%{http_code}" -H "Host: immich.danielriquelme.cl" http://localhost
check_success "Servicio web responde"

echo -e "\n${GREEN}Verificación completada.${NC}\n"
