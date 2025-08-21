#!/bin/bash

# 🔐 Script de Respaldo de Claves SOPS
# Autor: Daniel Riquelme
# Fecha: 21 de Agosto, 2025
# Descripción: Respalda las claves age de SOPS desde el cluster y localmente

set -euo pipefail

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuración
BACKUP_DIR="$HOME/.sops-backup"
DATE=$(date +"%Y%m%d_%H%M%S")
CLUSTER_BACKUP_FILE="$BACKUP_DIR/cluster_keys_$DATE.txt"
LOCAL_BACKUP_FILE="$BACKUP_DIR/local_keys_$DATE.txt"
CURRENT_KEY_FILE="$BACKUP_DIR/current_key.txt"

echo -e "${BLUE}🔐 Iniciando respaldo de claves SOPS...${NC}"

# Crear directorio de respaldo
mkdir -p "$BACKUP_DIR"

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

# Respaldar clave del cluster
backup_cluster_key() {
    info "Respaldando clave del cluster..."
    
    if kubectl get secret sops-age -n argocd &> /dev/null; then
        # Extraer la clave del cluster
        kubectl get secret sops-age -n argocd -o jsonpath='{.data.keys\.txt}' | base64 -d > "$CLUSTER_BACKUP_FILE"
        
        # Obtener la clave pública correspondiente
        PUBLIC_KEY=$(grep -o 'age1[a-zA-Z0-9]*' "$CLUSTER_BACKUP_FILE" | head -1)
        
        cat >> "$CLUSTER_BACKUP_FILE" << EOF

# Información de la clave
# Fecha de respaldo: $(date)
# Clave pública: $PUBLIC_KEY
# Namespace: argocd
# Secret: sops-age
EOF
        
        success "Clave del cluster respaldada en: $CLUSTER_BACKUP_FILE"
        info "Clave pública: $PUBLIC_KEY"
    else
        warning "Secret sops-age no encontrado en el cluster"
    fi
}

# Respaldar clave local
backup_local_key() {
    info "Verificando clave local..."
    
    LOCAL_KEY_PATH="$HOME/.config/sops/age/keys.txt"
    
    if [[ -f "$LOCAL_KEY_PATH" ]]; then
        cp "$LOCAL_KEY_PATH" "$LOCAL_BACKUP_FILE"
        
        # Obtener la clave pública correspondiente
        PUBLIC_KEY=$(grep -o 'age1[a-zA-Z0-9]*' "$LOCAL_BACKUP_FILE" | head -1)
        
        cat >> "$LOCAL_BACKUP_FILE" << EOF

# Información de la clave local
# Fecha de respaldo: $(date)
# Clave pública: $PUBLIC_KEY
# Ubicación original: $LOCAL_KEY_PATH
EOF
        
        success "Clave local respaldada en: $LOCAL_BACKUP_FILE"
        info "Clave pública: $PUBLIC_KEY"
    else
        warning "No se encontró clave local en: $LOCAL_KEY_PATH"
    fi
}

# Crear respaldo de la clave actual
create_current_backup() {
    info "Creando respaldo de la clave actual..."
    
    # Usar la clave del cluster como referencia
    if [[ -f "$CLUSTER_BACKUP_FILE" ]]; then
        cp "$CLUSTER_BACKUP_FILE" "$CURRENT_KEY_FILE"
        success "Clave actual respaldada en: $CURRENT_KEY_FILE"
    elif [[ -f "$LOCAL_BACKUP_FILE" ]]; then
        cp "$LOCAL_BACKUP_FILE" "$CURRENT_KEY_FILE"
        success "Clave actual respaldada en: $CURRENT_KEY_FILE"
    else
        error "No se pudo crear respaldo de la clave actual"
    fi
}

# Verificar integridad
verify_backups() {
    info "Verificando integridad de los respaldos..."
    
    for file in "$CLUSTER_BACKUP_FILE" "$LOCAL_BACKUP_FILE" "$CURRENT_KEY_FILE"; do
        if [[ -f "$file" ]]; then
            if grep -q "AGE-SECRET-KEY-" "$file"; then
                success "$(basename "$file") - Formato válido"
            else
                warning "$(basename "$file") - Formato inválido o vacío"
            fi
        fi
    done
}

# Mostrar resumen
show_summary() {
    echo
    info "📋 Resumen del respaldo:"
    echo "  📁 Directorio: $BACKUP_DIR"
    echo "  📅 Fecha: $DATE"
    echo
    
    if [[ -f "$CLUSTER_BACKUP_FILE" ]]; then
        echo "  🏗️  Clave del cluster: ✅"
    else
        echo "  🏗️  Clave del cluster: ❌"
    fi
    
    if [[ -f "$LOCAL_BACKUP_FILE" ]]; then
        echo "  💻 Clave local: ✅"
    else
        echo "  💻 Clave local: ❌"
    fi
    
    if [[ -f "$CURRENT_KEY_FILE" ]]; then
        echo "  🔑 Clave actual: ✅"
    else
        echo "  🔑 Clave actual: ❌"
    fi
    
    echo
    warning "⚠️  IMPORTANTE: Guarda estos archivos en un lugar seguro"
    warning "⚠️  Sin estas claves, los archivos SOPS serán irrecuperables"
}

# Función principal
main() {
    check_dependencies
    backup_cluster_key
    backup_local_key
    create_current_backup
    verify_backups
    show_summary
    
    success "🎉 Respaldo completado exitosamente"
}

# Ejecutar si se llama directamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
