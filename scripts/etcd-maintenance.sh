#!/bin/bash
# shellcheck disable=SC2155
# Script de diagnóstico y mantenimiento de etcd para K3s
#
# Este script realiza comprobaciones de salud no destructivas en el
# cluster y etcd, y realiza una limpieza básica de recursos.

set -euo pipefail

# --- Configuración y Colores ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- Funciones de Logging ---
info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
success() { echo -e "${GREEN}✅ $1${NC}"; }
warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
error() { echo -e "${RED}❌ $1${NC}"; }

# --- Función Principal ---
main() {
    info "=== Diagnóstico y Mantenimiento de Etcd en K3s ==="
    info "Ejecutando en: $(hostname) - $(date)"
    echo

    # 1. Verificar estado del cluster
    info "🔍 1. Verificando estado del cluster..."
    if ! kubectl get nodes > /dev/null 2>&1; then
        error "El cluster no está disponible o kubectl no está configurado."
        exit 1
    fi
    success "El cluster está disponible."
    kubectl get nodes
    echo

    # 2. Limpiar recursos obsoletos para reducir la carga
    info "🧹 2. Limpiando recursos obsoletos (Pods y Jobs terminados)..."
    kubectl delete pods --field-selector=status.phase=Succeeded --all-namespaces --ignore-not-found=true
    kubectl delete pods --field-selector=status.phase=Failed --all-namespaces --ignore-not-found=true
    kubectl delete jobs --field-selector=status.successful=1 --all-namespaces --ignore-not-found=true
    success "Limpieza de pods y jobs completada."
    echo

    # 3. Verificar el estado del pod de etcd
    info "🔍 3. Verificando el estado del pod de etcd en el master..."
    local master_node=$(kubectl get nodes -l node-role.kubernetes.io/master=true,node-role.kubernetes.io/control-plane=true -o jsonpath='{.items[0].metadata.name}')
    if [[ -z "$master_node" ]]; then
        error "No se pudo identificar el nodo master."
        exit 1
    fi
    info "   Master node identificado: ${master_node}"
    
    local etcd_pod=$(kubectl get pods -n kube-system --field-selector=spec.nodeName=${master_node} -l component=etcd -o jsonpath='{.items[0].metadata.name}')
    if [[ -z "$etcd_pod" ]]; then
        error "No se pudo encontrar el pod de etcd en el nodo master."
        exit 1
    fi
    info "   Etcd pod identificado: ${etcd_pod}"

    local etcd_status=$(kubectl get pod "${etcd_pod}" -n kube-system -o jsonpath='{.status.phase}')
    if [[ "$etcd_status" == "Running" ]]; then
        success "   El pod de etcd está en estado 'Running'."
    else
        error "   ¡El pod de etcd está en estado '${etcd_status}'!"
    fi
    echo

    # 4. Verificar el estado de salud de etcd
    info "❤️‍🩹 4. Verificando la salud del miembro etcd..."
    local etcd_health=$(kubectl exec -n kube-system "${etcd_pod}" -- etcdctl endpoint health --cluster -w table)
    if echo "${etcd_health}" | grep -q "is healthy"; then
        success "   El endpoint de etcd está saludable."
        echo "${etcd_health}"
    else
        error "   ¡El endpoint de etcd reporta problemas!"
        echo "${etcd_health}"
    fi
    echo

    # 5. Verificar el estado de la base de datos de etcd (tamaño)
    info "🗂️  5. Verificando el tamaño de la base de datos de etcd..."
    local etcd_db_status=$(kubectl exec -n kube-system "${etcd_pod}" -- etcdctl endpoint status --cluster -w table)
    echo "${etcd_db_status}"
    # Extraer el tamaño de la DB y advertir si es grande
    local db_size=$(echo "${etcd_db_status}" | awk 'NR>1 {print $6}')
    local db_size_mb=$(echo "${db_size}" | sed 's/.$//' | awk '{printf "%.0f", $1/1024/1024}')
    if (( db_size_mb > 1024 )); then # Mayor a 1GB
        warning "   El tamaño de la base de datos de etcd (${db_size_mb}MB) es grande. Considera una limpieza más profunda o un snapshot."
    else
        success "   El tamaño de la base de datos de etcd (${db_size_mb}MB) es saludable."
    fi
    echo
    
    # 6. Mostrar estadísticas finales del cluster
    info "📊 6. Estadísticas finales del cluster:"
    local node_count=$(kubectl get nodes --no-headers | wc -l | tr -d ' ')
    local pod_count=$(kubectl get pods --all-namespaces --no-headers | wc -l | tr -d ' ')
    echo "   - Nodos: ${node_count}"
    echo "   - Pods Totales: ${pod_count}"
    echo

    success "✅ Diagnóstico de etcd completado."
    info "💡 Si persisten los problemas, revisa los logs del pod de etcd: kubectl logs ${etcd_pod} -n kube-system"
}

# --- Ejecutar Script ---
main "$@"
