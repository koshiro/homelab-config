#!/bin/bash
# Script para convertir una Raspberry Pi con CasaOS en un nodo de Kubernetes

# Variables de configuración
PI_HOST="pibot.local"
PI_USER="daniel"
K3S_MASTER_HOST="192.168.1.131" # Ajusta esta IP según tu configuración
K3S_TOKEN=$(cat /var/lib/rancher/k3s/server/node-token 2>/dev/null || echo "OBTENER_DEL_NODO_MAESTRO")

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

# Verificar que podemos conectarnos al host
print_header "Verificando conectividad con $PI_HOST"
ssh -q $PI_USER@$PI_HOST exit
check_success "Conexión SSH a $PI_HOST" "exit"

# Verificar que la instancia de Immich en K8s está funcionando correctamente
print_header "Antes de continuar"
echo -e "${YELLOW}¡Importante!${NC} Asegúrate de que:"
echo "1. La instancia de Immich en Kubernetes está funcionando correctamente"
echo "2. Has verificado que todos los datos se han migrado correctamente"
echo "3. Has realizado una copia de seguridad de cualquier dato importante en la Pi"
echo ""
read -p "¿Deseas continuar? (s/n): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Ss]$ ]]; then
    echo -e "${RED}Operación cancelada por el usuario${NC}"
    exit 1
fi

# Detener CasaOS y servicios relacionados
print_header "Deteniendo servicios en $PI_HOST"
ssh $PI_USER@$PI_HOST "sudo systemctl stop casaos casaos-gateway casaos-user-service docker containerd"
check_success "Detener servicios"

# Desinstalar CasaOS
print_header "Desinstalando CasaOS"
ssh $PI_USER@$PI_HOST "curl -fsSL https://get.casaos.io/uninstall | sudo bash"
check_success "Desinstalar CasaOS"

# Limpiar Docker
print_header "Limpiando Docker"
ssh $PI_USER@$PI_HOST "sudo apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras"
check_success "Purgar paquetes Docker"

ssh $PI_USER@$PI_HOST "sudo rm -rf /var/lib/docker /etc/docker /var/run/docker.sock"
check_success "Eliminar archivos Docker residuales"

# Instalar paquetes necesarios
print_header "Instalando paquetes necesarios"
ssh $PI_USER@$PI_HOST "sudo apt-get update && sudo apt-get install -y curl openssh-server"
check_success "Instalar paquetes básicos"

# Configurar cgroup para Raspberry Pi
print_header "Configurando cgroups para Kubernetes"
ssh $PI_USER@$PI_HOST "sudo sed -i 's/^CMDLINE=.*/CMDLINE=\"cgroup_enable=cpuset cgroup_enable=memory cgroup_memory=1 swapaccount=1\"/' /boot/firmware/cmdline.txt 2>/dev/null || sudo sed -i 's/$/ cgroup_enable=cpuset cgroup_enable=memory cgroup_memory=1 swapaccount=1/' /boot/firmware/cmdline.txt"
check_success "Configurar cgroups en cmdline.txt"

# Instalar K3s como agente
print_header "Instalando K3s como nodo worker"
ssh $PI_USER@$PI_HOST "curl -sfL https://get.k3s.io | K3S_URL=https://$K3S_MASTER_HOST:6443 K3S_TOKEN=$K3S_TOKEN sh -"
check_success "Instalar K3s"

# Verificar instalación
print_header "Verificando instalación de K3s"
ssh $PI_USER@$PI_HOST "sudo systemctl status k3s-agent"
check_success "K3s-agent está en ejecución"

# Mostrar mensaje final
print_header "Proceso completado"
echo -e "La Raspberry Pi ${YELLOW}$PI_HOST${NC} ha sido configurada como nodo worker en el clúster K3s."
echo -e "Para verificar que el nodo se ha unido correctamente al clúster, ejecuta:"
echo -e "${GREEN}kubectl get nodes${NC}"
echo ""
echo -e "${YELLOW}Nota:${NC} Es posible que el nodo tarde unos minutos en aparecer en el clúster."
echo -e "Si el nodo no aparece después de 5 minutos, verifica los logs en la Raspberry Pi:"
echo -e "${GREEN}ssh $PI_USER@$PI_HOST sudo journalctl -u k3s-agent${NC}"
