# 🔒 Hooks de Git para Seguridad - 2025

## 📋 **Resumen Ejecutivo**

Este documento describe la implementación de hooks de Git para prevenir la exposición de credenciales y archivos sensibles en el repositorio. Los hooks se basan en las mejores prácticas de seguridad de 2025 y están diseñados para ser robustos, configurables y fáciles de mantener.

## 🎯 **Objetivos de Seguridad**

### **Prevención de Exposición de Credenciales**
- Detectar credenciales hardcodeadas en código
- Prevenir commits de archivos `.env`
- Validar archivos SOPS encriptados
- Detectar claves privadas (Age, GPG, SSH)

### **Auditoría y Compliance**
- Logging automático de commits
- Registro de archivos sensibles
- Trazabilidad de cambios
- Cumplimiento de políticas de seguridad

## 🏗️ **Arquitectura de los Hooks**

```
.git/hooks/
├── pre-commit          # Hook principal de pre-commit
├── post-commit         # Hook de auditoría post-commit
└── logs/               # Directorio de logs
    ├── commit-history.log
    └── security-audit.log

scripts/git-hooks/
├── pre-commit          # Script principal de pre-commit
├── post-commit         # Script de auditoría
├── config.sh           # Configuración de hooks
├── test-hooks.sh       # Script de pruebas
└── README.md           # Documentación
```

## 🔧 **Instalación**

### **Instalación Automática (Recomendada)**
```bash
./scripts/install-git-hooks.sh
```

### **Instalación Manual**
```bash
# Crear directorio de hooks
mkdir -p .git/hooks

# Copiar hooks
cp scripts/git-hooks/pre-commit .git/hooks/
cp scripts/git-hooks/post-commit .git/hooks/

# Hacer ejecutables
chmod +x .git/hooks/pre-commit
chmod +x .git/hooks/post-commit
```

## 📖 **Hooks Disponibles**

### **1. Pre-commit Hook**

#### **Funcionalidades**
- **Detección de Credenciales**: Busca patrones de credenciales hardcodeadas
- **Validación de Archivos**: Verifica archivos `.env` y claves privadas
- **Verificación SOPS**: Valida que archivos `.sops.yml` estén encriptados
- **Análisis de Configuración**: Revisa archivos de configuración por credenciales
- **Verificación de Scripts**: Analiza scripts por credenciales hardcodeadas

#### **Patrones Detectados**
```bash
# Credenciales básicas
password.*=.*["'][^"']{3,}["']  # Ejemplo: password="123"
api_key.*=.*["'][^"']{10,}["']  # Ejemplo: api_key="abc123def"
secret.*=.*["'][^"']{3,}["']    # Ejemplo: secret="xyz"
token.*=.*["'][^"']{10,}["']    # Ejemplo: token="auth123456"
auth.*=.*["'][^"']{3,}["']      # Ejemplo: auth="user"
key.*=.*["'][^"']{10,}["']      # Ejemplo: key="secret123"

# Comentarios con credenciales
password.*:.*[a-zA-Z0-9]{3,}
api_key.*:.*[a-zA-Z0-9]{10,}
```

#### **Archivos Excluidos**
```bash
*.sops.yml          # Archivos SOPS encriptados
*.age-key           # Claves Age
*.example           # Archivos de ejemplo
*.template          # Plantillas
node_modules/*      # Dependencias
.git/*             # Metadatos de Git
```

### **2. Post-commit Hook**

#### **Funcionalidades**
- **Logging de Commits**: Registra información detallada de cada commit
- **Auditoría de Seguridad**: Detecta archivos sensibles en commits
- **Historial de Cambios**: Mantiene log de todos los commits
- **Alertas de Seguridad**: Notifica sobre archivos potencialmente sensibles

#### **Información Registrada**
```bash
# Log de commit
[2025-01-18 15:30:45] Commit: abc123 | Author: User <user@example.com> | Files: 3 | Message: Update configuration

# Log de auditoría
[2025-01-18 15:30:45] COMMIT: abc123 | AUTHOR: User <user@example.com> | SENSITIVE_FILES: config.env
```

## ⚙️ **Configuración**

### **Archivo de Configuración**
```bash
# scripts/git-hooks/config.sh

# Habilitar/deshabilitar hooks
ENABLE_PRE_COMMIT=true
ENABLE_POST_COMMIT=true
ENABLE_CREDENTIAL_CHECK=true
ENABLE_SOPS_CHECK=true

# Patrones de exclusión personalizados
EXCLUDE_PATTERNS=(
    "*.sops.yml"
    "*.age-key"
    "*.example"
    "*.template"
    "node_modules/*"
    ".git/*"
)

# Nivel de logging
LOG_LEVEL="INFO"  # DEBUG, INFO, WARN, ERROR
```

### **Personalización de Patrones**
```bash
# Agregar nuevos patrones de credenciales
CREDENTIAL_PATTERNS+=(
    "custom_pattern.*=.*[\"'][^\"']{5,}[\"']"
)

# Agregar nuevos tipos de archivos a verificar
SCRIPT_FILES+=(
    "*.pl"
    "*.lua"
)
```

## 🧪 **Pruebas y Validación**

### **Script de Pruebas**
```bash
./scripts/git-hooks/test-hooks.sh
```

### **Pruebas Manuales**
```bash
# Probar pre-commit hook
git add .
git commit -m "Test commit"

# Verificar logs
cat .git/logs/commit-history.log
cat .git/logs/security-audit.log
```

### **Simulación de Errores**
```bash
# Crear archivo con credenciales (para prueba)
echo 'API_KEY="test123456789"' > test-credentials.yml

# Intentar commit (debería fallar)
git add test-credentials.yml
git commit -m "Test credentials"  # ❌ Debería fallar

# Limpiar
rm test-credentials.yml
git reset HEAD~1
```

## 🚨 **Manejo de Errores**

### **Tipos de Errores**
1. **Credenciales Hardcodeadas**: Bloquea el commit
2. **Archivos .env**: Bloquea el commit
3. **Claves Privadas**: Bloquea el commit
4. **Archivos SOPS sin Encriptar**: Bloquea el commit

### **Advertencias**
1. **Comentarios con Credenciales**: Muestra advertencia
2. **Archivos de Configuración**: Muestra advertencia
3. **Scripts con Credenciales**: Muestra advertencia

### **Bypass de Hooks (NO RECOMENDADO)**
```bash
# Saltarse verificación de pre-commit
git commit --no-verify

# Saltarse verificación de post-commit
git commit --no-verify
```

## 📊 **Monitoreo y Logs**

### **Logs Disponibles**
```bash
.git/logs/
├── commit-history.log    # Historial de commits
└── security-audit.log    # Auditoría de seguridad
```

### **Análisis de Logs**
```bash
# Ver commits recientes
tail -f .git/logs/commit-history.log

# Buscar commits con archivos sensibles
grep "SENSITIVE_FILES" .git/logs/security-audit.log

# Estadísticas de commits
wc -l .git/logs/commit-history.log
```

## 🔄 **Mantenimiento y Actualización**

### **Actualización de Hooks**
```bash
# Reinstalar hooks
./scripts/install-git-hooks.sh

# Actualizar configuración
vim scripts/git-hooks/config.sh
```

### **Backup de Configuración**
```bash
# Crear backup
cp -r .git/hooks hooks-backup-$(date +%Y%m%d)

# Restaurar backup
cp -r hooks-backup-20250118/* .git/hooks/
```

## 🆘 **Solución de Problemas**

### **Problemas Comunes**

#### **1. Hook no se ejecuta**
```bash
# Verificar permisos
ls -la .git/hooks/pre-commit

# Verificar que sea ejecutable
chmod +x .git/hooks/pre-commit

# Verificar sintaxis
bash -n .git/hooks/pre-commit
```

#### **2. Falsos positivos**
```bash
# Agregar patrón a exclusiones
echo "*.test.yml" >> scripts/git-hooks/config.sh

# Personalizar patrones de credenciales
vim scripts/git-hooks/pre-commit
```

#### **3. Hook muy lento**
```bash
# Optimizar exclusiones
# Reducir archivos verificados
# Usar patrones más específicos
```

### **Debugging**
```bash
# Habilitar modo debug
export LOG_LEVEL="DEBUG"

# Ejecutar hook manualmente
.git/hooks/pre-commit

# Ver logs detallados
tail -f .git/logs/security-audit.log
```

## 📚 **Mejores Prácticas**

### **1. Configuración de Repositorio**
- Instalar hooks en todos los repositorios
- Configurar exclusiones específicas por proyecto
- Mantener hooks actualizados

### **2. Desarrollo de Equipo**
- Documentar patrones de credenciales
- Entrenar equipo en uso de variables de entorno
- Revisar logs regularmente

### **3. Integración Continua**
- Incluir hooks en pipelines de CI/CD
- Validar hooks en pull requests
- Automatizar auditoría de seguridad

### **4. Monitoreo**
- Revisar logs semanalmente
- Configurar alertas para archivos sensibles
- Mantener estadísticas de seguridad

## 🔮 **Roadmap Futuro**

### **Versión 2.0 (Q2 2025)**
- Integración con GitGuardian Shield
- Detección de credenciales en imágenes
- Análisis de dependencias por credenciales
- Dashboard web de seguridad

### **Versión 3.0 (Q4 2025)**
- Machine Learning para detección
- Integración con herramientas de compliance
- API para auditoría externa
- Plugins para IDEs

## 📞 **Soporte y Contacto**

### **Recursos de Ayuda**
- [Documentación de Git Hooks](https://git-scm.com/docs/githooks)
- [Mejores Prácticas de SOPS](https://github.com/mozilla/sops)
- [GitGuardian Shield](https://github.com/GitGuardian/ggshield)

### **Reportar Problemas**
- Crear issue en el repositorio
- Incluir logs de error
- Describir pasos para reproducir

---

**⚠️ IMPORTANTE**: Los hooks de seguridad son una capa de protección, pero no reemplazan las buenas prácticas de desarrollo. Siempre usa variables de entorno, SOPS para secretos, y revisa manualmente el código antes de hacer commit.
