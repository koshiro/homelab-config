#!/bin/bash

# 🔄 Script de Restauración de Claves SOPS
# Autor: Daniel Riquelme
# Fecha: 21 de Agosto, 2025
# Descripción: Restaura las claves age de SOPS desde respaldo

set -euo pipefail

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuración
BACKUP_DIR="$HOME/.sops-backup"
LOCAL_KEY_PATH="$HOME/.config/sops/age/keys.txt"

# Función para mostrar información
info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Función para mostrar éxito
success() {
    echo -e "${GREEN}✅ $1${NC}"
}

# Función para mostrar advertencia
warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Función para mostrar error
error() {
    echo -e "${RED}❌ $1${NC}"
}

# Mostrar uso
show_usage() {
    echo "🔄 Script de Restauración de Claves SOPS"
    echo
    echo "Uso: $0 [opciones]"
    echo
    echo "Opciones:"
    echo "  -f, --file FILE     Archivo de clave específico para restaurar"
    echo "  -l, --local         Restaurar solo clave local"
    echo "  -c, --cluster       Restaurar solo clave del cluster"
    echo "  -a, --all           Restaurar todo (por defecto)"
    echo "  -h, --help          Mostrar esta ayuda"
    echo
    echo "Ejemplos:"
    echo "  $0                                    # Restaurar todo"
    echo "  $0 -f ~/.sops-backup/current_key.txt # Restaurar desde archivo específico"
    echo "  $0 --local                           # Solo restaurar clave local"
}

# Verificar dependencias
check_dependencies() {
    info "Verificando dependencias..."
    
    if ! command -v kubectl &> /dev/null; then
        error "kubectl no está instalado"
        exit 1
    fi
    
    if ! command -v base64 &> /dev/null; then
        error "base64 no está disponible"
        exit 1
    fi
    
    success "Dependencias verificadas"
}

# Listar respaldos disponibles
list_backups() {
    info "Respaldos disponibles en $BACKUP_DIR:"
    
    if [[ ! -d "$BACKUP_DIR" ]]; then
        warning "Directorio de respaldo no existe: $BACKUP_DIR"
        return 1
    fi
    
    local found=false
    
    for file in "$BACKUP_DIR"/*.txt; do
        if [[ -f "$file" ]]; then
            local basename=$(basename "$file")
            local date=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$file" 2>/dev/null || date -r "$file" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "Fecha desconocida")
            echo "  📄 $basename ($date)"
            found=true
        fi
    done
    
    if [[ "$found" == false ]]; then
        warning "No se encontraron respaldos"
        return 1
    fi
}

# Validar archivo de clave
validate_key_file() {
    local file="$1"
    
    if [[ ! -f "$file" ]]; then
        error "Archivo no existe: $file"
        return 1
    fi
    
    if ! grep -q "AGE-SECRET-KEY-" "$file"; then
        error "Archivo no contiene una clave age válida: $file"
        return 1
    fi
    
    success "Archivo de clave válido: $file"
    return 0
}

# Restaurar clave local
restore_local_key() {
    local key_file="$1"
    
    info "Restaurando clave local..."
    
    # Crear directorio si no existe
    mkdir -p "$(dirname "$LOCAL_KEY_PATH")"
    
    # Hacer backup de la clave existente si existe
    if [[ -f "$LOCAL_KEY_PATH" ]]; then
        local backup_path="${LOCAL_KEY_PATH}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$LOCAL_KEY_PATH" "$backup_path"
        warning "Clave existente respaldada en: $backup_path"
    fi
    
    # Copiar la nueva clave
    cp "$key_file" "$LOCAL_KEY_PATH"
    chmod 600 "$LOCAL_KEY_PATH"
    
    success "Clave local restaurada en: $LOCAL_KEY_PATH"
}

# Restaurar clave del cluster
restore_cluster_key() {
    local key_file="$1"
    
    info "Restaurando clave del cluster..."
    
    # Verificar si el secret existe
    if kubectl get secret sops-age -n argocd &> /dev/null; then
        warning "Secret sops-age ya existe. Será reemplazado."
        kubectl delete secret sops-age -n argocd
    fi
    
    # Crear el nuevo secret
    kubectl create secret generic sops-age \
        --namespace=argocd \
        --from-file=keys.txt="$key_file"
    
    success "Clave del cluster restaurada en secret sops-age"
}

# Verificar restauración
verify_restoration() {
    info "Verificando restauración..."
    
    local errors=0
    local sops_pubkey=$(yq '.creation_rules[0].age' .sops.yaml)

    # Verificar clave local
    if [[ -f "$LOCAL_KEY_PATH" ]]; then
        if grep -q "AGE-SECRET-KEY-" "$LOCAL_KEY_PATH"; then
            success "Clave local: ✅"
        else
            error "Clave local: ❌ (formato inválido)"
            ((errors++))
        fi
    else
        warning "Clave local: ❌ (no existe)"
    fi
    
    # Verificar clave del cluster
    if kubectl get secret sops-age -n argocd &> /dev/null; then
        local cluster_key_b64=$(kubectl get secret sops-age -n argocd -o jsonpath='{.data.keys\.txt}')
        local cluster_key=$(echo "$cluster_key_b64" | base64 -d)
        if echo "$cluster_key" | grep -q "AGE-SECRET-KEY-"; then
            success "Clave del cluster: ✅"

            # Nueva verificación: Coincidencia de clave pública
            local restored_pubkey=$(echo "$cluster_key" | grep -o 'age1[a-zA-Z0-9]*' | head -1)
            if [[ "$restored_pubkey" == "$sops_pubkey" ]]; then
                success "Coincidencia de clave pública: ✅ (La clave restaurada coincide con .sops.yaml)"
            else
                error "Coincidencia de clave pública: ❌ (La clave en el cluster NO COINCIDE con .sops.yaml)"
                warning "   Clave en .sops.yaml: ${sops_pubkey}"
                warning "   Clave en el secret:  ${restored_pubkey}"
                ((errors++))
            fi
        else
            error "Clave del cluster: ❌ (formato inválido)"
            ((errors++))
        fi
    else
        warning "Clave del cluster: ❌ (secret no existe)"
    fi
    
    if [[ $errors -eq 0 ]]; then
        success "Verificación completada sin errores"
    else
        error "Verificación completada con $errors errores"
        return 1
    fi
}

# Función principal
main() {
    local key_file=""
    local restore_local=true
    local restore_cluster=true
    
    # Parsear argumentos
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--file)
                key_file="$2"
                shift 2
                ;;
            -l|--local)
                restore_cluster=false
                shift
                ;;
            -c|--cluster)
                restore_local=false
                shift
                ;;
            -a|--all)
                restore_local=true
                restore_cluster=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                error "Opción desconocida: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    echo -e "${BLUE}🔄 Iniciando restauración de claves SOPS...${NC}"
    
    check_dependencies
    
    # Si no se especifica archivo, usar el current_key.txt o listar opciones
    if [[ -z "$key_file" ]]; then
        local current_key="$BACKUP_DIR/current_key.txt"
        if [[ -f "$current_key" ]]; then
            key_file="$current_key"
            info "Usando clave actual: $key_file"
        else
            echo
            list_backups
            echo
            error "No se especificó archivo de clave y no existe current_key.txt"
            echo "Usa -f para especificar un archivo de respaldo"
            exit 1
        fi
    fi
    
    # Validar archivo de clave
    if ! validate_key_file "$key_file"; then
        exit 1
    fi
    
    # Mostrar información de la clave
    local public_key=$(grep -o 'age1[a-zA-Z0-9]*' "$key_file" | head -1)
    info "Clave pública: $public_key"
    
    # Confirmar restauración
    echo
    warning "⚠️  ADVERTENCIA: Esta operación reemplazará las claves existentes"
    read -p "¿Continuar? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Operación cancelada"
        exit 0
    fi
    
    # Realizar restauración
    if [[ "$restore_local" == true ]]; then
        restore_local_key "$key_file"
    fi
    
    if [[ "$restore_cluster" == true ]]; then
        restore_cluster_key "$key_file"
    fi
    
    # Verificar restauración
    verify_restoration
    
    success "🎉 Restauración completada exitosamente"
    
    echo
    info "📋 Próximos pasos recomendados:"
    echo "  1. Verificar que SOPS puede desencriptar archivos"
    echo "  2. Reiniciar pods de ArgoCD si es necesario"
    echo "  3. Verificar sincronización de aplicaciones"
}

# Ejecutar si se llama directamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
