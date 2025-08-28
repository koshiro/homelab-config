# Solución al Error 404 en Immich en Kubernetes

## Problema

Al intentar acceder a Immich a través de la URL `https://immich.danielriquelme.cl`, se presentaba un error 404. Este error se debía a que Traefik no podía enrutar el tráfico correctamente porque los pods de Immich no estaban funcionando correctamente.

## Causas Identificadas

1. **Discrepancia en las rutas de montaje**: Los volúmenes se montaban en rutas diferentes entre el contenedor init y el contenedor principal.
   - En el contenedor init: `/mnt/upload` y `/mnt/library`
   - En el contenedor principal: `/usr/src/app/upload` y `/usr/src/app/library`

2. **Falta de archivos `.immich` para verificación de integridad**: Immich realiza una verificación de integridad de los directorios buscando archivos `.immich` en cada subdirectorio importante.

3. **Problemas de permisos**: Los contenedores no tenían permisos adecuados para escribir en los directorios montados.

4. **Estructura de directorios incompleta**: Faltaba el directorio `upload/upload` que Immich esperaba encontrar.

## Solución Implementada

### 1. Corrección de las Rutas de Montaje

Se modificó el contenedor init para crear los directorios en las mismas rutas que utiliza el contenedor principal:

```yaml
- name: init-folders
  image: busybox:1.36
  securityContext:
    runAsUser: 0
    runAsGroup: 0
  command: ['sh', '-c']
  args:
    - |
      mkdir -p /usr/src/app/upload/encoded-video
      mkdir -p /usr/src/app/upload/profile
      mkdir -p /usr/src/app/upload/library
      mkdir -p /usr/src/app/upload/thumbs
      mkdir -p /usr/src/app/upload/backups
      mkdir -p /usr/src/app/upload/upload
      
      mkdir -p /usr/src/app/library
      mkdir -p /usr/src/app/config
```

### 2. Creación de Archivos `.immich` para Verificación de Integridad

Se añadieron comandos para crear los archivos `.immich` en cada subdirectorio:

```yaml
# Crear archivos .immich para verificación de integridad
touch /usr/src/app/upload/encoded-video/.immich
touch /usr/src/app/upload/profile/.immich
touch /usr/src/app/upload/library/.immich
touch /usr/src/app/upload/thumbs/.immich
touch /usr/src/app/upload/backups/.immich
touch /usr/src/app/upload/upload/.immich
touch /usr/src/app/library/.immich
```

### 3. Configuración de Permisos Adecuados

Se utilizó un contenedor init con permisos de root para configurar los permisos adecuados:

```yaml
securityContext:
  runAsUser: 0
  runAsGroup: 0
```

Y se establecieron los permisos correctos para los directorios:

```yaml
# Asegurar permisos adecuados
chown -R 1000:1000 /usr/src/app/upload
chown -R 1000:1000 /usr/src/app/library
chown -R 1000:1000 /usr/src/app/config
chmod -R 755 /usr/src/app/upload
chmod -R 755 /usr/src/app/library
chmod -R 755 /usr/src/app/config
```

### 4. Actualización de los Servicios

Se actualizaron los servicios para asegurar que apuntaran a los pods correctos:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: immich-server
  namespace: immich
spec:
  selector:
    app: immich-server
  ports:
    - port: 3001
      targetPort: 3001
      protocol: TCP
```

## Resultados

Después de aplicar estas correcciones, los pods de Immich comenzaron a funcionar correctamente. Los logs del servidor de Immich muestran que la verificación de integridad de los directorios se completa con éxito:

```
[Nest] 7  - 08/28/2025, 4:43:41 PM     LOG [Microservices:StorageService] Verifying system mount folder checks, current state: {"mountChecks":{"thumbs":true,"upload":true,"backups":true,"library":true,"profile":true,"encoded-video":true}}
[Nest] 7  - 08/28/2025, 4:43:41 PM     LOG [Microservices:StorageService] Successfully verified system mount folder checks
```

## Lecciones Aprendidas

1. **Verificar las rutas de montaje**: Es crucial asegurarse de que los volúmenes se monten en las mismas rutas en todos los contenedores que los utilizan.

2. **Revisar la documentación de la aplicación**: Immich requiere archivos `.immich` para su verificación de integridad, lo cual está documentado en su página de administración.

3. **Gestionar adecuadamente los permisos**: Los contenedores deben tener los permisos adecuados para escribir en los directorios montados.

4. **Verificar los endpoints de los servicios**: Es importante asegurarse de que los servicios estén apuntando a los pods correctos y que estos estén funcionando correctamente.

## Próximos Pasos

1. Monitorear el funcionamiento de Immich para asegurar que no haya más problemas.
2. Considerar la migración a volúmenes persistentes en lugar de emptyDir para una solución más robusta.
3. Implementar pruebas automatizadas para verificar la integridad de la instalación de Immich.
