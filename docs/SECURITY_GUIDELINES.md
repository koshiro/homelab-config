# 🔒 Guía de Seguridad - Homelab

## 🚨 **CRÍTICO: Nunca versionar credenciales**

### **Reglas Fundamentales:**
1. **NUNCA** committear credenciales en texto plano
2. **SIEMPRE** usar SOPS para encriptar secretos
3. **NUNCA** hardcodear contraseñas en scripts
4. **SIEMPRE** usar variables de entorno para credenciales

## 📁 **Manejo de Credenciales**

### **Para Scripts:**
- Usar archivos `.env` para credenciales locales
- Crear `.env.example` como plantilla
- Agregar `.env` al `.gitignore`

### **Para Kubernetes:**
- Usar SOPS para encriptar secretos
- NUNCA committear archivos `*.sops.yml` sin encriptar
- Usar `kubectl create secret` para secretos temporales

## 🔐 **Configuración de SOPS**

### **Instalación:**
```bash
# macOS
brew install sops

# Linux
wget https://github.com/mozilla/sops/releases/download/v3.7.3/sops-v3.7.3.linux
sudo mv sops-v3.7.3.linux /usr/local/bin/sops
sudo chmod +x /usr/local/bin/sops
```

### **Uso Básico:**
```bash
# Encriptar archivo
sops -e -i archivo.yml

# Desencriptar archivo
sops -d archivo.yml

# Editar archivo encriptado
sops archivo.yml
```

## 🛡️ **Checklist de Seguridad**

### **Antes de hacer commit:**
- [ ] ¿Hay credenciales en texto plano?
- [ ] ¿Están encriptados todos los secretos?
- [ ] ¿Está actualizado el `.gitignore`?
- [ ] ¿Se han removido credenciales hardcodeadas?

### **Después de cambios:**
- [ ] ¿Funcionan los scripts con variables de entorno?
- [ ] ¿Se pueden desplegar los manifiestos de Kubernetes?
- [ ] ¿Están funcionando los servicios?

## 📋 **Archivos Sensibles Identificados**

### **Scripts corregidos:**
- ✅ `scripts/setup-timemachine-truenas.sh` - Usa variables de entorno
- ✅ `scripts/verify-timemachine-setup.sh` - Usa variables de entorno

### **Archivos SOPS (ya seguros):**
- ✅ `cluster/monitoring/secret-proxmox.sops.yml`
- ✅ `cluster/monitoring/secret-truenas-credentials.sops.yml`
- ✅ `cluster/monitoring/secret-grafana.sops.yml`
- ✅ `cluster/homepage/secret-credentials.sops.yml`

### **Archivos eliminados:**
- ✅ `cluster/flux-ssh-key.sops.yml` - Eliminado (no se usa Flux)
- ✅ `cluster/flux-system/` - Eliminado (no se usa Flux)

## 🚀 **Próximos Pasos Recomendados**

1. **Regenerar API keys** de TrueNAS que fueron expuestas
2. **Cambiar contraseñas** de usuarios que fueron expuestas
3. **Configurar SOPS** para todos los secretos futuros
4. **Revisar logs** de GitGuardian para más detecciones
5. **Implementar pre-commit hooks** para prevenir futuras exposiciones

## 📚 **Recursos Adicionales**

- [SOPS Documentation](https://github.com/mozilla/sops)
- [GitGuardian Best Practices](https://docs.gitguardian.com/)
- [Kubernetes Secrets Management](https://kubernetes.io/docs/concepts/configuration/secret/)
- [ArgoCD Security](https://argo-cd.readthedocs.io/en/stable/security/)
