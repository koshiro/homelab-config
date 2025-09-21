#!/bin/bash

# 🔧 Script de Corrección: PostgreSQL + Immich Connection
# Autor: Daniel Riquelme
# Descripción: Corrige los problemas de conexión entre PostgreSQL e Immich
# Fecha: Septiembre 2025

set -euo pipefail

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuración
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
POSTGRES_SECRET_FILE="$PROJECT_ROOT/cluster/apps/postgresql/01-superuser-secret.yaml"
POSTGRES_SECRET_SOPS_FILE="$PROJECT_ROOT/cluster/apps/postgresql/01-superuser-secret.sops.yaml"
IMMICH_SECRETS_FILE="$PROJECT_ROOT/cluster/apps/immich/secrets.sops.yaml"

echo -e "${BLUE}🔧 Iniciando corrección de conexión PostgreSQL + Immich...${NC}"

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
    exit 1
}

# Verificar dependencias
check_dependencies() {
    info "Verificando dependencias..."
    
    if ! command -v sops &> /dev/null; then
        error "SOPS no está instalado. Instálalo con: brew install sops"
    fi
    
    if ! command -v kubectl &> /dev/null; then
        error "kubectl no está instalado"
    fi
    
    if ! command -v base64 &> /dev/null; then
        error "base64 no está disponible"
    fi
    
    success "Todas las dependencias están disponibles"
}

# Generar contraseña segura
generate_password() {
    # Generar una contraseña segura de 32 caracteres (compatible con PostgreSQL)
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-32
}

# Decodificar contraseña actual
get_current_password() {
    if [[ -f "$POSTGRES_SECRET_FILE" ]]; then
        info "Decodificando contraseña actual de PostgreSQL..."
        local encoded_password=$(grep "password:" "$POSTGRES_SECRET_FILE" | awk '{print $2}')
        echo "$encoded_password" | base64 -d
    else
        warning "No se encontró archivo de secreto actual"
        echo ""
    fi
}

# Crear secreto cifrado para PostgreSQL
create_encrypted_postgres_secret() {
    local password="$1"
    
    info "Creando secreto cifrado para PostgreSQL..."
    
    # Crear archivo temporal sin cifrar
    local temp_file=$(mktemp)
    cat > "$temp_file" << EOF
apiVersion: v1
kind: Secret
metadata:
  name: homelab-postgres-superuser
  namespace: postgresql
type: Opaque
stringData:
  password: $password
  username: postgres
EOF

    # Cifrar con SOPS usando la misma configuración que Immich
    if ! sops -e --age age1ga4dqzwv2wrf5c0dduz0vsjkzlda9xzrp787u2mnhhj6zh5qxaws4mlhhs "$temp_file" > "$POSTGRES_SECRET_SOPS_FILE"; then
        rm -f "$temp_file"
        error "Falló el cifrado con SOPS"
    fi
    
    rm -f "$temp_file"
    success "Secreto de PostgreSQL cifrado creado: $POSTGRES_SECRET_SOPS_FILE"
}

# Actualizar secreto de Immich con la misma contraseña
update_immich_secret() {
    local password="$1"
    
    info "Actualizando secreto de Immich..."
    
    if [[ ! -f "$IMMICH_SECRETS_FILE" ]]; then
        error "No se encontró archivo de secretos de Immich: $IMMICH_SECRETS_FILE"
    fi
    
    # Desencriptar, actualizar y volver a encriptar
    local temp_file=$(mktemp)
    local temp_updated=$(mktemp)
    
    # Desencriptar
    if ! sops -d "$IMMICH_SECRETS_FILE" > "$temp_file"; then
        rm -f "$temp_file" "$temp_updated"
        error "Falló la desencriptación del secreto de Immich"
    fi
    
    # Actualizar la contraseña de la base de datos
    # Usar yq o sed para actualizar el valor
    if command -v yq &> /dev/null; then
        yq eval ".stringData.DB_PASSWORD = \"$password\"" "$temp_file" > "$temp_updated"
    else
        # Fallback con sed (más básico pero funcional)
        sed "s/DB_PASSWORD:.*/DB_PASSWORD: $password/" "$temp_file" > "$temp_updated"
    fi
    
    # Volver a encriptar
    if ! sops -e --age age1ga4dqzwv2wrf5c0dduz0vsjkzlda9xzrp787u2mnhhj6zh5qxaws4mlhhs "$temp_updated" > "$IMMICH_SECRETS_FILE"; then
        rm -f "$temp_file" "$temp_updated"
        error "Falló el cifrado del secreto actualizado de Immich"
    fi
    
    rm -f "$temp_file" "$temp_updated"
    success "Secreto de Immich actualizado con la nueva contraseña"
}

# Hacer backup del archivo actual
backup_current_files() {
    info "Creando backup de archivos actuales..."
    local backup_dir="$PROJECT_ROOT/backups/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    if [[ -f "$POSTGRES_SECRET_FILE" ]]; then
        cp "$POSTGRES_SECRET_FILE" "$backup_dir/"
        success "Backup creado: $backup_dir/$(basename "$POSTGRES_SECRET_FILE")"
    fi
    
    if [[ -f "$IMMICH_SECRETS_FILE" ]]; then
        cp "$IMMICH_SECRETS_FILE" "$backup_dir/"
        success "Backup creado: $backup_dir/$(basename "$IMMICH_SECRETS_FILE")"
    fi
}

# Función principal
main() {
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                    Corrección PostgreSQL + Immich                           ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    
    check_dependencies
    
    # Opción para usar contraseña actual o generar nueva
    echo
    info "Opciones disponibles:"
    echo "1. Mantener contraseña actual y sincronizar"
    echo "2. Generar nueva contraseña segura"
    echo
    read -p "Selecciona una opción (1-2): " option
    
    local password=""
    case $option in
        1)
            password=$(get_current_password)
            if [[ -z "$password" ]]; then
                warning "No se pudo obtener la contraseña actual. Generando nueva..."
                password=$(generate_password)
            else
                info "Usando contraseña actual decodificada"
            fi
            ;;
        2)
            password=$(generate_password)
            info "Generada nueva contraseña segura"
            ;;
        *)
            error "Opción inválida"
            ;;
    esac
    
    info "Contraseña a usar: ${password:0:4}***${password: -4}"
    
    # Confirmar antes de proceder
    echo
    warning "¿Estás seguro de continuar? Esto modificará los archivos de secretos."
    read -p "Continuar? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        info "Operación cancelada"
        exit 0
    fi
    
    # Crear backups
    backup_current_files
    
    # Crear nuevo secreto cifrado para PostgreSQL
    create_encrypted_postgres_secret "$password"
    
    # Actualizar secreto de Immich
    update_immich_secret "$password"
    
    # Remover archivo sin cifrar
    if [[ -f "$POSTGRES_SECRET_FILE" ]]; then
        rm "$POSTGRES_SECRET_FILE"
        success "Removido archivo sin cifrar: $POSTGRES_SECRET_FILE"
    fi
    
    echo
    success "¡Corrección completada exitosamente!"
    echo
    info "Pasos siguientes:"
    echo "1. Aplica los cambios: kubectl apply -f cluster/apps/postgresql/"
    echo "2. Reinicia el cluster PostgreSQL si es necesario"
    echo "3. Redespliega Immich: kubectl rollout restart deployment -n immich"
    echo "4. Verifica la conexión en los logs de Immich"
    echo
    warning "Los backups están disponibles en: $PROJECT_ROOT/backups/"
}

# Ejecutar función principal
main "$@"
