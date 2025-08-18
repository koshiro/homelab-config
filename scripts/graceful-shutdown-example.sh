#!/bin/bash

# 🛑 Script de Ejemplo: Apagado Ordenado del Cluster
# Este script demuestra cómo usar el playbook de apagado ordenado
# para mantenimiento de hardware o actualizaciones del sistema

set -e

echo "🛑 Script de Apagado Ordenado del Cluster"
echo "=========================================="

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
if [[ ! -f "ansible/inventory" ]]; then
    log_error "Este script debe ejecutarse desde el directorio raíz del proyecto"
    exit 1
fi

# Verificar que Ansible esté disponible
if ! command -v ansible-playbook &> /dev/null; then
    log_error "ansible-playbook no está instalado o no está en el PATH"
    exit 1
fi

# Función para mostrar el estado actual del cluster
show_cluster_status() {
    log_info "📊 Estado actual del cluster:"
    echo "----------------------------------------"
    
    # Verificar conectividad a Proxmox
    if ping -c 1 192.168.1.100 &> /dev/null; then
        log_success "Proxmox: ✅ Accesible"
    else
        log_error "Proxmox: ❌ No accesible"
        return 1
    fi
    
    # Verificar conectividad a TrueNAS
    if ping -c 1 192.168.1.20 &> /dev/null; then
        log_success "TrueNAS: ✅ Accesible"
    else
        log_warning "TrueNAS: ⚠️ No accesible"
    fi
    
    # Verificar conectividad a nodos Kubernetes
    for node_ip in "192.168.1.131" "192.168.1.132" "192.168.1.133"; do
        if ping -c 1 $node_ip &> /dev/null; then
            log_success "k3s-node: ✅ $node_ip accesible"
        else
            log_warning "k3s-node: ⚠️ $node_ip no accesible"
        fi
    done
    
    echo "----------------------------------------"
}

# Función para confirmar el apagado
confirm_shutdown() {
    echo ""
    log_warning "⚠️  ADVERTENCIA: OPERACIÓN CRÍTICA"
    echo "=========================================="
    echo "Este proceso apagará TODO el cluster de manera ordenada:"
    echo ""
    echo "1. 🐳 Drenar nodos Kubernetes (evacuar pods)"
    echo "2. 💾 Detener servicios TrueNAS (NFS, SMB, SSH, HTTP)"
    echo "3. 🖥️  Apagar VMs de Kubernetes"
    echo "4. 🗄️  Apagar VM de TrueNAS"
    echo "5. 🖥️  Apagar Proxmox host"
    echo ""
    echo "🚨 ESTO APAGARÁ COMPLETAMENTE EL SERVIDOR"
    echo ""
    
    read -p "¿Estás SEGURO de que quieres continuar? (escribe 'SI' en mayúsculas): " confirmation
    
    if [[ "$confirmation" != "SI" ]]; then
        log_info "Operación cancelada por el usuario"
        exit 0
    fi
    
    echo ""
    log_warning "Última confirmación:"
    echo "El servidor se apagará completamente en 10 segundos."
    echo "Presiona CTRL+C para cancelar."
    
    for i in {10..1}; do
        echo -n "$i... "
        sleep 1
    done
    echo ""
}

# Función para ejecutar el apagado ordenado
execute_graceful_shutdown() {
    log_info "🚀 Iniciando apagado ordenado del cluster..."
    
    # Cambiar al directorio de Ansible
    cd ansible
    
    # Ejecutar el playbook de apagado ordenado
    log_info "Ejecutando playbook de apagado ordenado..."
    
    if ansible-playbook -i inventory playbooks/utils/playbook_graceful_shutdown_cluster.yml; then
        log_success "✅ Apagado ordenado completado exitosamente"
        return 0
    else
        log_error "❌ Error durante el apagado ordenado"
        return 1
    fi
}

# Función para mostrar instrucciones post-apagado
show_post_shutdown_instructions() {
    echo ""
    log_success "🎉 APAGADO ORDENADO COMPLETADO"
    echo "====================================="
    echo ""
    echo "📋 PRÓXIMOS PASOS:"
    echo "1. 🔧 Realiza el mantenimiento de hardware necesario"
    echo "2. ⚡ Enciende el servidor Proxmox"
    echo "3. ⏳ Espera a que todas las VMs arranquen (5-10 minutos)"
    echo "4. ✅ Verifica el estado del cluster:"
    echo "    cd ansible"
    echo "    ansible-playbook -i inventory playbook_homelab.yml --check"
    echo ""
    echo "🚨 IMPORTANTE:"
    echo "- El cluster puede tardar varios minutos en estabilizarse"
    echo "- Los servicios pueden tardar en estar disponibles"
    echo "- Verifica que TrueNAS esté funcionando antes de usar el cluster"
    echo ""
    echo "📚 Para más detalles, consulta:"
    echo "- docs/GRACEFUL_SHUTDOWN_GUIDE.md"
    echo "- README.md (sección de Apagado Ordenado)"
}

# Función principal
main() {
    echo ""
    log_info "Iniciando proceso de apagado ordenado..."
    
    # Mostrar estado actual
    if ! show_cluster_status; then
        log_error "No se puede verificar el estado del cluster. Abortando."
        exit 1
    fi
    
    # Confirmar operación
    confirm_shutdown
    
    # Ejecutar apagado ordenado
    if execute_graceful_shutdown; then
        show_post_shutdown_instructions
    else
        log_error "El apagado ordenado falló. Revisa los logs para más detalles."
        exit 1
    fi
}

# Ejecutar función principal
main "$@"
