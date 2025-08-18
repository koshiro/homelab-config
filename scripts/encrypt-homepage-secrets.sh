#!/bin/bash

# 🔐 Script para Encriptar Secretos de Homepage con SOPS
# Este script encripta todos los archivos de secretos de Homepage

set -e

echo "🔐 Encriptando Secretos de Homepage con SOPS..."
echo "================================================"

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
if [[ ! -f "cluster/homepage/secret-credentials.sops.yml" ]]; then
    log_error "Este script debe ejecutarse desde el directorio raíz del proyecto"
    exit 1
fi

# Verificar que SOPS esté instalado
if ! command -v sops &> /dev/null; then
    log_error "SOPS no está instalado. Instálalo primero:"
    echo "  macOS: brew install sops"
    echo "  Ubuntu: sudo apt install sops"
    echo "  O descárgalo desde: https://github.com/mozilla/sops/releases"
    exit 1
fi

# Verificar que la clave GPG esté configurada
if [[ -z "$SOPS_AGE_KEY_FILE" ]] && [[ -z "$SOPS_AGE_KEY" ]]; then
    log_warning "No se detectó configuración de SOPS con Age"
    log_info "Asegúrate de tener configurado SOPS con tu clave Age o GPG"
fi

# Función para encriptar archivo
encrypt_file() {
    local file_path="$1"
    local file_name=$(basename "$file_path")
    
    if [[ -f "$file_path" ]]; then
        log_info "Encriptando: $file_name"
        
        # Crear backup antes de encriptar
        cp "$file_path" "${file_path}.backup"
        
        # Encriptar con SOPS
        if sops -e -i "$file_path"; then
            log_success "✅ $file_name encriptado exitosamente"
            # Eliminar backup si la encriptación fue exitosa
            rm "${file_path}.backup"
        else
            log_error "❌ Error al encriptar $file_name"
            # Restaurar backup en caso de error
            mv "${file_path}.backup" "$file_path"
            return 1
        fi
    else
        log_warning "⚠️  Archivo no encontrado: $file_path"
    fi
}

# Lista de archivos a encriptar
SECRET_FILES=(
    "cluster/homepage/secret-credentials.sops.yml"
)

# Encriptar cada archivo
log_info "Iniciando encriptación de secretos..."
for file in "${SECRET_FILES[@]}"; do
    encrypt_file "$file"
done

echo ""
echo "🎯 Encriptación Completada"
echo "=========================="
echo ""
echo "📁 Archivos Encriptados:"
for file in "${SECRET_FILES[@]}"; do
    if [[ -f "$file" ]]; then
        echo "   ✅ $(basename "$file")"
    else
        echo "   ❌ $(basename "$file") - No encontrado"
    fi
done

echo ""
echo "🔐 Verificación de Encriptación:"
echo "   - Los archivos ahora están encriptados con SOPS"
echo "   - Puedes verificar con: sops -d $file"
echo "   - Para aplicar al clúster: kubectl apply -f $file"
echo ""

log_success "¡Secretos encriptados exitosamente!"
log_info "Ahora puedes aplicar los secretos al clúster de forma segura"

