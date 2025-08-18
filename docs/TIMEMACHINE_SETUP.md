# 🕒 Configuración de Time Machine en el Homelab

Este documento describe cómo configurar y usar el servicio de Time Machine para macOS en el cluster Kubernetes.

## 📋 Requisitos Previos

- Cluster Kubernetes funcionando
- TrueNAS configurado con acceso API
- Disco de 3TB disponible en TrueNAS
- Dominio `tm.danielriquelme.cl` configurado en Cloudflare

## 🚀 Instalación

### 1. Configurar TrueNAS

Ejecutar el script de configuración:

```bash
./scripts/setup-timemachine-truenas.sh
```

Este script:
- Crea un dataset de 3TB llamado `timemachine` en el pool `homelab-storage`
- Configura compresión LZ4 y atime OFF para optimizar rendimiento
- Crea el usuario `timemachine` con UID 1000
- Crea un share NFS para el dataset con permisos apropiados

### 2. Verificar la Configuración

Ejecutar el script de verificación:

```bash
./scripts/verify-timemachine-setup.sh
```

Este script verifica:
- ✅ Dataset creado correctamente
- ✅ Usuario timemachine configurado
- ✅ Share NFS habilitado
- ✅ Espacio disponible (10.3TB)

### 3. Desplegar en Kubernetes

```bash
kubectl apply -k cluster/timemachine/
```

### 4. Verificar el despliegue

```bash
kubectl get pods -n timemachine
kubectl get svc -n timemachine
kubectl get ingress -n timemachine
```

## 🔧 Configuración en macOS

### 1. Conectar al servidor AFP

1. Abrir **Finder**
2. Presionar `Cmd + K` o ir a **Go > Connect to Server**
3. Ingresar: `afp://tm.danielriquelme.cl`
4. Usar credenciales:
   - Usuario: `timemachine`
   - Contraseña: `TimeMachine2024!`

### 2. Configurar Time Machine

1. Abrir **System Preferences > Time Machine**
2. Hacer clic en **Select Backup Disk**
3. Seleccionar el volumen montado desde `tm.danielriquelme.cl`
4. Hacer clic en **Use Disk**

## 📊 Monitoreo

### Ver logs del servicio

```bash
kubectl logs -f deployment/timemachine -n timemachine
```

### Verificar estado del PVC

```bash
kubectl describe pvc timemachine-storage-pvc -n timemachine
```

### Verificar conectividad AFP

```bash
# Desde macOS
afp_client -c afp://tm.danielriquelme.cl
```

## 🔒 Seguridad

- El servicio solo acepta conexiones desde Traefik
- Las credenciales están almacenadas como Secret de Kubernetes
- Network Policies restringen el acceso al puerto AFP (548)
- El dataset tiene permisos específicos para el usuario timemachine
- Share NFS configurado con redes permitidas específicas

## 🚨 Troubleshooting

### Problema: No se puede conectar al servidor AFP

1. Verificar que el pod esté corriendo:
   ```bash
   kubectl get pods -n timemachine
   ```

2. Verificar logs del pod:
   ```bash
   kubectl logs deployment/timemachine -n timemachine
   ```

3. Verificar que el servicio esté expuesto:
   ```bash
   kubectl get svc -n timemachine
   ```

### Problema: Error de autenticación

1. Verificar que el usuario se haya creado correctamente:
   ```bash
   kubectl exec -it deployment/timemachine -n timemachine -- id timemachine
   ```

2. Verificar permisos del directorio:
   ```bash
   kubectl exec -it deployment/timemachine -n timemachine -- ls -la /timemachine
   ```

### Problema: Error de permisos en TrueNAS

1. Verificar que el dataset existe:
   ```bash
   curl -H "Authorization: Bearer $API_KEY" \
        "http://192.168.1.20/api/v2.0/pool/dataset" | jq
   ```

2. Verificar permisos del dataset:
   ```bash
   curl -H "Authorization: Bearer $API_KEY" \
        "http://192.168.1.20/api/v2.0/pool/dataset/homelab-storage/timemachine" | jq
   ```

3. Verificar share NFS:
   ```bash
   curl -H "Authorization: Bearer $API_KEY" \
        "http://192.168.1.20/api/v2.0/sharing/nfs" | jq
   ```

## 📝 Notas Importantes

- **Compresión**: El dataset usa compresión LZ4 para optimizar espacio
- **Atime**: Deshabilitado para mejorar rendimiento
- **Usuario**: timemachine con UID 1000 y grupo users
- **Share NFS**: Configurado con maproot_user para permisos apropiados
- **Backup**: Time Machine creará automáticamente backups incrementales
- **Retención**: Configurar la retención de backups desde macOS según necesidades

## 🔄 Actualizaciones

Para actualizar el servicio:

```bash
kubectl rollout restart deployment/timemachine -n timemachine
```

## 📚 Referencias

- [Netatalk Documentation](https://netatalk.sourceforge.net/)
- [Time Machine Documentation](https://support.apple.com/en-us/HT201250)
- [Kubernetes Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
- [TrueNAS API Documentation](https://www.truenas.com/docs/api/)

## 🎯 Estado Actual

✅ **Configuración Completada:**
- Dataset `homelab-storage/timemachine` creado (10.3TB disponible)
- Usuario `timemachine` configurado (UID: 1000)
- Share NFS habilitado en `/mnt/homelab-storage/timemachine`
- Servicio Kubernetes listo para desplegar

🚀 **Próximo Paso:**
- Desplegar el servicio en Kubernetes con `kubectl apply -k cluster/timemachine/`
