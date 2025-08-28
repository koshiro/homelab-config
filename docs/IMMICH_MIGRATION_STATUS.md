# Estado Actual de la Migración de Immich

Este documento resume el estado actual de la migración de Immich desde CasaOS a Kubernetes y los próximos pasos a seguir.

## Estado de la Migración

### Completado

1. **Preparación y Análisis**
   - Se ha analizado la estructura actual de Immich en CasaOS
   - Se han identificado los volúmenes y datos críticos a migrar

2. **Infraestructura en Kubernetes**
   - Se han creado todos los manifiestos YAML para Immich
   - Se han configurado los volúmenes persistentes para almacenamiento local y NFS
   - Se han implementado políticas de red para seguridad
   - Se ha configurado el ingress para acceso externo

3. **Datos y Configuración**
   - Se han creado datasets en TrueNAS para almacenamiento de imágenes
   - Se ha realizado respaldo de la base de datos PostgreSQL
   - Se han migrado las imágenes al almacenamiento NFS en TrueNAS

4. **Documentación y Herramientas**
   - Se ha creado un script de verificación para comprobar el estado del despliegue
   - Se ha documentado el proceso completo con guías detalladas
   - Se ha desarrollado un script para convertir la Raspberry Pi en nodo del clúster

### En Progreso

1. **Despliegue en Kubernetes**
   - Los recursos de Immich han sido aplicados al clúster
   - Se ha corregido la política de red para permitir comunicación interna
   - La inicialización de los pods está en curso

2. **Migración de Datos**
   - El job de migración ha sido creado y está en ejecución
   - Se requiere configurar la clave SSH para continuar la migración

## Problemas Detectados

1. **Políticas de Red**
   - Se detectó que la política de red original bloqueaba el tráfico egress entre pods del mismo namespace
   - Se ha aplicado una corrección para permitir este tráfico

2. **Inicialización de la Base de Datos**
   - La base de datos se ha creado correctamente pero el servidor de Immich aún no puede conectarse

3. **Configuración de Job de Migración**
   - El job de migración requiere que se agregue manualmente una clave SSH a la Raspberry Pi

## Próximos Pasos

1. **Verificar Conectividad al Clúster**
   - Asegurarse de que la conexión al clúster Kubernetes es estable
   - Evitar el uso simultáneo de kubectl por múltiples agentes

2. **Completar Despliegue de Immich**
   - Verificar que todos los pods estén en estado "Running"
   - Verificar las comunicaciones internas entre servicios

3. **Configurar la Migración de Datos**
   - Obtener la clave SSH del job de migración
   - Agregarla a la Raspberry Pi para permitir la transferencia de datos

4. **Verificar Funcionalidad**
   - Acceder a la interfaz web de Immich
   - Comprobar que las imágenes se muestran correctamente

5. **Finalizar la Migración**
   - Una vez confirmado el funcionamiento correcto, eliminar la instancia de CasaOS
   - Convertir la Raspberry Pi en nodo del clúster

## Comandos y Verificaciones

Para continuar con la migración, ejecutar:

```bash
# Verificar conectividad con el clúster
kubectl get nodes

# Verificar el estado de los pods de Immich
kubectl get pods -n immich

# Ver los logs del job de migración para obtener la clave SSH
kubectl logs -n immich $(kubectl get pods -n immich -l job-name=immich-migration -o jsonpath='{.items[0].metadata.name}')

# Agregar la clave SSH a la Raspberry Pi
ssh daniel@pibot.local "mkdir -p ~/.ssh && echo 'CLAVE_PUBLICA' >> ~/.ssh/authorized_keys"
```

## Notas y Recomendaciones

- Si persisten los problemas de conectividad, considerar reiniciar el acceso a la API del clúster
- Si los pods no avanzan en su inicialización, considerar reiniciarlos uno por uno
- Los volúmenes persistentes configurados garantizan que los datos permanezcan incluso si se reinician los pods

Este documento será actualizado a medida que avance la migración.
