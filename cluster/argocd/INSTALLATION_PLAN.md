# Plan de Instalación de ArgoCD

## 1. Instalación Limpia
- Usar el manifiesto oficial de ArgoCD
- Instalar solo los componentes esenciales
- No modificar la configuración base

## 2. Configuración para Repositorios SSH Privados
- **Método 1**: Usar Repository como recurso separado (RECOMENDADO)
  - Crear Secret con tipo `argocd.argoproj.io/secret-type: repository`
  - Incluir `sshPrivateKey` en el secret
  - Referenciar desde la Application

- **Método 2**: Configurar en ConfigMap (ALTERNATIVO)
  - Agregar `repositories` en `argocd-cm`
  - Incluir `sshPrivateKey` directamente

## 3. Orden de Aplicación
1. Instalar ArgoCD base
2. Configurar repositorio SSH
3. Crear Application
4. Verificar sincronización

## 4. Archivos Necesarios
- `install.yaml` - Instalación oficial de ArgoCD
- `repository-github.yml` - Secret para credenciales SSH
- `argocd-app-homelab.yml` - Application del cluster
- `kustomization.yml` - Orden de aplicación

## 5. Verificaciones
- Namespace `argocd` creado
- Todos los pods de ArgoCD funcionando
- Repositorio SSH configurado correctamente
- Application sincronizando sin errores
