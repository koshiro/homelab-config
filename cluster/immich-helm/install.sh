#!/bin/bash

# Script para instalar Immich en Kubernetes usando Helm

# Colores para salida
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Instalación de Immich en Kubernetes usando Helm ===${NC}"

# Verificar si kubectl está instalado
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl no está instalado. Por favor, instálalo antes de continuar.${NC}"
    exit 1
fi

# Verificar si helm está instalado
if ! command -v helm &> /dev/null; then
    echo -e "${RED}Error: helm no está instalado. Por favor, instálalo antes de continuar.${NC}"
    exit 1
fi

# Crear namespace si no existe
echo -e "${YELLOW}Creando namespace immich...${NC}"
kubectl create namespace immich --dry-run=client -o yaml | kubectl apply -f -

# Aplicar PersistentVolumes y PersistentVolumeClaims
echo -e "${YELLOW}Aplicando PersistentVolumes y PersistentVolumeClaims...${NC}"
kubectl apply -f pv.yaml

# Inicializar volúmenes
echo -e "${YELLOW}Inicializando volúmenes...${NC}"
kubectl apply -f init-volumes.yaml

# Esperar a que el job de inicialización termine
echo -e "${YELLOW}Esperando a que el job de inicialización termine...${NC}"
kubectl wait --for=condition=complete --timeout=60s job/immich-init-volumes -n immich

# Añadir repositorio de Helm de Immich
echo -e "${YELLOW}Añadiendo repositorio de Helm de Immich...${NC}"
helm repo add immich https://immich-app.github.io/immich-charts
helm repo update

# Instalar Immich usando los valores personalizados
echo -e "${YELLOW}Instalando Immich usando Helm...${NC}"
helm install immich immich/immich -n immich -f values.yaml

echo -e "${GREEN}Instalación completada.${NC}"
echo -e "${YELLOW}Para verificar el estado de la instalación, ejecuta:${NC}"
echo "kubectl get pods -n immich"
echo -e "${YELLOW}Para migrar datos desde una instalación existente, ejecuta:${NC}"
echo "kubectl apply -f migration-job.yaml"
echo -e "${YELLOW}Una vez que Immich esté en funcionamiento, podrás acceder a él en:${NC}"
echo "https://immich.danielriquelme.cl"
