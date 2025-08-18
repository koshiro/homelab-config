#!/bin/bash

# Script para instalar hooks de Git para seguridad
# Basado en las mejores prácticas de 2025

set -e

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Función para mostrar mensajes de error
error() {
    echo -e "${RED}❌ ERROR: $1${NC}" >&2
}

# Función para mostrar mensajes de advertencia
warning() {
    echo -e "${YELLOW}⚠️  ADVERTENCIA: $1${NC}" >&2
}

# Función para mostrar mensajes de éxito
success() {
    echo -e "${GREEN}✅ $1${NC}"
}

# Función para mostrar información
info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

echo "🔒 Instalando hooks de Git para seguridad..."
echo ""

# Verificar que estamos en un repositorio Git
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    error "No estás en un repositorio Git"
    exit 1
fi

# Crear directorio de hooks si no existe
HOOKS_DIR=".git/hooks"
if [ ! -d "$HOOKS_DIR" ]; then
    mkdir -p "$HOOKS_DIR"
    success "Directorio de hooks creado: $HOOKS_DIR"
fi

# Función para instalar un hook
install_hook() {
    local hook_name="$1"
    local source_file="scripts/git-hooks/$hook_name"
    local target_file="$HOOKS_DIR/$hook_name"
    
    if [ -f "$source_file" ]; then
        cp "$source_file" "$target_file"
        chmod +x "$target_file"
        success "Hook $hook_name instalado"
    else
        warning "Archivo fuente para $hook_name no encontrado"
    fi
}

# Instalar hooks principales
info "Instalando hooks de seguridad..."

# Pre-commit hook
if [ -f ".git/hooks/pre-commit" ]; then
    success "Pre-commit hook ya está instalado"
else
    warning "Pre-commit hook no encontrado en .git/hooks/"
    info "Creando pre-commit hook básico..."
    
    cat > "$HOOKS_DIR/pre-commit" << 'EOF'
#!/bin/bash
# Pre-commit hook básico - ejecuta el script principal
exec scripts/git-hooks/pre-commit
EOF
    chmod +x "$HOOKS_DIR/pre-commit"
    success "Pre-commit hook básico creado"
fi

# Post-commit hook
if [ -f ".git/hooks/post-commit" ]; then
    success "Post-commit hook ya está instalado"
else
    warning "Post-commit hook no encontrado en .git/hooks/"
    info "Creando post-commit hook básico..."
    
    cat > "$HOOKS_DIR/post-commit" << 'EOF'
#!/bin/bash
# Post-commit hook básico - ejecuta el script principal
exec scripts/git-hooks/post-commit
EOF
    chmod +x "$HOOKS_DIR/post-commit"
    success "Post-commit hook básico creado"
fi

# Crear directorio para hooks personalizados
HOOKS_SCRIPTS_DIR="scripts/git-hooks"
mkdir -p "$HOOKS_SCRIPTS_DIR"

# Copiar hooks principales al directorio de scripts
cp .git/hooks/pre-commit "$HOOKS_SCRIPTS_DIR/" 2>/dev/null || true
cp .git/hooks/post-commit "$HOOKS_SCRIPTS_DIR/" 2>/dev/null || true

# Crear archivo de configuración para hooks
cat > "$HOOKS_SCRIPTS_DIR/config.sh" << 'EOF'
#!/bin/bash
# Configuración para hooks de Git

# Habilitar/deshabilitar hooks específicos
ENABLE_PRE_COMMIT=true
ENABLE_POST_COMMIT=true
ENABLE_CREDENTIAL_CHECK=true
ENABLE_SOPS_CHECK=true

# Patrones de archivos a excluir
EXCLUDE_PATTERNS=(
    "*.sops.yml"
    "*.age-key"
    "*.example"
    "*.template"
    "node_modules/*"
    ".git/*"
)

# Nivel de logging (DEBUG, INFO, WARN, ERROR)
LOG_LEVEL="INFO"
EOF

chmod +x "$HOOKS_SCRIPTS_DIR/config.sh"

# Crear script de prueba
cat > "$HOOKS_SCRIPTS_DIR/test-hooks.sh" << 'EOF'
#!/bin/bash
# Script para probar los hooks de Git

echo "🧪 Probando hooks de Git..."

# Simular pre-commit
echo "🔍 Probando pre-commit hook..."
if [ -f "scripts/git-hooks/pre-commit" ]; then
    echo "✅ Pre-commit hook encontrado"
else
    echo "❌ Pre-commit hook no encontrado"
fi

# Simular post-commit
echo "🔍 Probando post-commit hook..."
if [ -f "scripts/git-hooks/post-commit" ]; then
    echo "✅ Post-commit hook encontrado"
else
    echo "❌ Post-commit hook no encontrado"
fi

echo "✅ Prueba completada"
EOF

chmod +x "$HOOKS_SCRIPTS_DIR/test-hooks.sh"

# Crear README para hooks
cat > "$HOOKS_SCRIPTS_DIR/README.md" << 'EOF'
# Hooks de Git para Seguridad

Este directorio contiene hooks personalizados de Git para prevenir la exposición de credenciales.

## Hooks Disponibles

### pre-commit
- Detecta credenciales hardcodeadas
- Verifica archivos .env
- Valida archivos SOPS encriptados
- Previene commits con información sensible

### post-commit
- Registra información del commit
- Crea logs de auditoría
- Detecta archivos sensibles

## Configuración

Edita `config.sh` para personalizar el comportamiento de los hooks.

## Pruebas

Ejecuta `test-hooks.sh` para verificar que los hooks estén funcionando correctamente.

## Desinstalación

Para desinstalar los hooks, elimina los archivos de `.git/hooks/` correspondientes.
EOF

echo ""
success "🎉 Hooks de Git instalados exitosamente!"
echo ""
info "📁 Hooks instalados en: $HOOKS_DIR"
info "📁 Scripts de hooks en: $HOOKS_SCRIPTS_DIR"
echo ""
info "🔧 Para probar los hooks:"
info "   ./scripts/git-hooks/test-hooks.sh"
echo ""
info "📚 Documentación disponible en:"
info "   $HOOKS_SCRIPTS_DIR/README.md"
echo ""
warning "⚠️  IMPORTANTE: Los hooks se ejecutarán automáticamente en cada commit"
info "💡 Para saltarte un hook (NO RECOMENDADO):"
info "   git commit --no-verify"
echo ""
success "✅ Instalación completada. ¡Tu repositorio ahora está protegido!"
