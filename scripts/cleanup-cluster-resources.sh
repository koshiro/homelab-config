#!/bin/bash
# shellcheck disable=SC2034,SC2155
# Script para limpiar recursos obsoletos del cluster de forma segura
# Reduce la carga en etcd eliminando recursos innecesarios
#
# MODO SEGURO: Por defecto, solo simula los cambios (--dry-run).
#              Para ejecutar los cambios, usa el argumento --apply.

set -euo pipefail

# --- Configuración y Colores ---
DRY_RUN=true
if [[ "${1:-}" == "--apply" ]]; then
    DRY_RUN=false
fi

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

# --- Función Principal de Limpieza ---
main() {
    info "=== Limpieza de Recursos del Cluster ==="
    info "Ejecutando en: $(hostname) - $(date)"
    if [ "$DRY_RUN" = true ]; then
        warning "Modo de simulación (dry-run) activado. No se realizarán cambios."
        info "Para aplicar los cambios, ejecuta: $0 --apply"
    else
        warning "MODO DE APLICACIÓN ACTIVADO. Se eliminarán recursos del cluster."
        sleep 5
    fi
    echo

    # 1. Limpiar pods terminados
    info "🧹 1. Limpiando pods en estado 'Succeeded' y 'Failed'..."
    local pods_to_delete=$(kubectl get pods --all-namespaces -o json | jq -r '.items[] | select(.status.phase == "Succeeded" or .status.phase == "Failed") | "\(.metadata.namespace)/\(.metadata.name)"')
    if [[ -n "$pods_to_delete" ]]; then
        echo "$pods_to_delete" | while read -r pod; do
            if [ "$DRY_RUN" = false ]; then
                kubectl delete pod -n "${pod%/*}" "${pod#*/}" --ignore-not-found=true
            fi
            echo "   - [POD] ${pod} (será eliminado)"
        done
    else
        success "   No hay pods terminados para limpiar."
    fi
    echo

    # 2. Limpiar jobs completados (más de 1 hora)
    info "🧹 2. Limpiando Jobs completados hace más de 1 hora..."
    local jobs_to_delete=$(kubectl get jobs --all-namespaces -o json | jq -r '.items[] | select(.status.succeeded == 1) | select((.status.completionTime | fromdate) < (now - 3600)) | "\(.metadata.namespace)/\(.metadata.name)"')
    if [[ -n "$jobs_to_delete" ]]; then
        echo "$jobs_to_delete" | while read -r job; do
            if [ "$DRY_RUN" = false ]; then
                kubectl delete job -n "${job%/*}" "${job#*/}" --ignore-not-found=true
            fi
            echo "   - [JOB] ${job} (será eliminado)"
        done
    else
        success "   No hay jobs completados antiguos para limpiar."
    fi
    echo

    # 3. Listar PVCs huérfanos (Bound pero no montados)
    info "🧹 3. Identificando PVCs huérfanos (Bound pero no utilizados)..."
    local orphan_pvcs=0
    local all_pvcs=$(kubectl get pvc --all-namespaces -o json | jq -r '.items[] | select(.status.phase == "Bound") | "\(.metadata.namespace)/\(.metadata.name)"')
    local pods_with_volumes=$(kubectl get pods --all-namespaces -o json | jq -r '.items[] | .spec.volumes[]? | select(.persistentVolumeClaim.claimName != null) | "\(.persistentVolumeClaim.claimName)"')
    
    echo "$all_pvcs" | while read -r pvc_full; do
        local pvc_name="${pvc_full#*/}"
        if ! echo "$pods_with_volumes" | grep -q "^${pvc_name}$"; then
            warning "   - [PVC HUÉRFANO] ${pvc_full}"
            orphan_pvcs=$((orphan_pvcs + 1))
        fi
    done
    if [ "$orphan_pvcs" -eq 0 ]; then
        success "   No se encontraron PVCs huérfanos."
    else
        info "   Se encontraron ${orphan_pvcs} PVCs huérfanos. Su eliminación debe ser manual."
    fi
    echo

    # 4. Mostrar estadísticas del cluster
    info "📊 Estadísticas actuales del cluster:"
    local node_count=$(kubectl get nodes --no-headers | wc -l | tr -d ' ')
    local pod_count=$(kubectl get pods --all-namespaces --no-headers | wc -l | tr -d ' ')
    local pvc_count=$(kubectl get pvc --all-namespaces --no-headers | wc -l | tr -d ' ')
    echo "   - Nodos: ${node_count}"
    echo "   - Pods Totales: ${pod_count}"
    echo "   - PVCs Totales: ${pvc_count}"
    echo

    # 5. Verificar estado del cluster
    info "🔍 Verificando estado del cluster..."
    kubectl get nodes -o wide
    echo
    kubectl top nodes
    echo

    if [ "$DRY_RUN" = true ]; then
        success "Simulación de limpieza completada."
    else
        success "✅ Limpieza completada."
    fi
    info "💡 Considera ejecutar este script periódicamente para mantener el cluster optimizado."
}

# --- Ejecutar Script ---
main "$@"
